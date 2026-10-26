"""Real PostgreSQL role tests. Run only against a disposable LOCAL Supabase database."""

import os
from pathlib import Path
from uuid import uuid4

import pytest

pytestmark = pytest.mark.integration


@pytest.fixture
def db():
    dsn = os.getenv("TEST_DATABASE_URL")
    if not dsn:
        pytest.skip("TEST_DATABASE_URL unset; real PostgreSQL/RLS not exercised")
    psycopg = pytest.importorskip("psycopg")
    if not any(host in dsn for host in ("localhost", "127.0.0.1")):
        pytest.fail("RLS fixtures are restricted to a disposable localhost database")
    with psycopg.connect(dsn) as conn:
        # Every test rolls back all fixture data and role changes.
        try:
            yield conn
        finally:
            conn.rollback()


def users(db):
    ids = [uuid4() for _ in range(3)]
    for uid in ids:
        db.execute("insert into auth.users(id,email) values(%s,%s)", (uid, f"{uid}@test.invalid"))
    return ids


def as_user(db, uid):
    db.execute("set local role authenticated")
    db.execute(
        "select set_config('request.jwt.claims',%s,true)",
        (f'{{"sub":"{uid}","role":"authenticated"}}',),
    )


def test_allowance_migration_can_be_reapplied_without_changing_access_or_usage(db):
    a, _, _ = users(db)
    before = db.execute("select public.get_allowance(%s)", (a,)).fetchone()[0]
    function_id = db.execute("select 'public.get_allowance(uuid)'::regprocedure::oid").fetchone()[0]
    migration = (
        Path(__file__).resolve().parents[2] / "supabase/migrations/202610230002_allowance.sql"
    ).read_text(encoding="utf-8")
    db.execute(migration)
    db.execute(migration)
    assert db.execute("select public.get_allowance(%s)", (a,)).fetchone()[0] == before
    assert (
        db.execute("select 'public.get_allowance(uuid)'::regprocedure::oid").fetchone()[0]
        == function_id
    )
    for role, expected in (("anon", False), ("authenticated", False), ("service_role", True)):
        assert (
            db.execute(
                "select has_function_privilege(%s, 'public.get_allowance(uuid)', 'EXECUTE')",
                (role,),
            ).fetchone()[0]
            is expected
        )


def test_rls_profile_isolation_and_room_isolation(db):
    a, b, outsider = users(db)
    room = db.execute("select public.create_room(%s,'hash-one','en','de')", (a,)).fetchone()[0]
    db.execute("select public.join_room(%s,'hash-one','de','en')", (b,))
    as_user(db, outsider)
    assert db.execute("select id from public.profiles").fetchall() == [(outsider,)]
    assert db.execute("select id from public.conversations").fetchall() == []
    assert db.execute("select id from public.conversation_participants").fetchall() == []
    db.execute("reset role")
    as_user(db, a)
    assert db.execute("select id from public.conversations").fetchall() == [(room,)]
    assert len(db.execute("select id from public.conversation_participants").fetchall()) == 2


@pytest.mark.parametrize(
    "statement",
    [
        "update public.subscriptions set plan='business'",
        "insert into public.usage_records(user_id,duration_seconds,estimated_cost) "
        "values(auth.uid(),1,0)",
        "select public.create_room(auth.uid(),'stolen','en','de')",
        "select public.reserve_usage(auth.uid(),gen_random_uuid(),1,0)",
        "select join_code_hash from public.conversations",
    ],
)
def test_clients_cannot_write_billing_call_privileged_rpcs_or_read_hash(db, statement):
    a, _, _ = users(db)
    as_user(db, a)
    from psycopg.errors import InsufficientPrivilege

    with pytest.raises(InsufficientPrivilege):
        db.execute(statement)


def test_capacity_code_single_use_language_pair_and_quota(db):
    a, b, c = users(db)
    room = db.execute("select public.create_room(%s,'hash-two','en','de')", (a,)).fetchone()[0]
    with db.transaction():
        db.execute("select public.join_room(%s,'hash-two','de','en')", (b,))
    with pytest.raises(Exception, match="invalid_room"):
        with db.transaction():
            db.execute("select public.join_room(%s,'hash-two','de','en')", (c,))
    with pytest.raises(Exception, match="room_full"):
        with db.transaction():
            db.execute(
                "insert into public.conversation_participants"
                "(conversation_id,user_id,source_language,target_language) values(%s,%s,%s,%s)",
                (room, c, "de", "en"),
            )
    for _ in range(40):
        db.execute("select public.reserve_usage(%s,%s,15,0.01)", (a, room))
    with pytest.raises(Exception, match="quota_exceeded"):
        with db.transaction():
            db.execute("select public.reserve_usage(%s,%s,1,0.01)", (a, room))
    report = db.execute("select public.get_allowance(%s)", (a,)).fetchone()[0]
    assert report["remaining_seconds"] == 0


def test_concurrent_join_and_quota_reservations_are_serialized(db):
    from concurrent.futures import ThreadPoolExecutor

    import psycopg

    ids = users(db)
    a, b, c = ids
    room = db.execute("select public.create_room(%s,'race-code','en','de')", (a,)).fetchone()[0]
    db.commit()  # Independent connections must see these fixtures.

    def attempt(statement, params):
        try:
            with psycopg.connect(os.environ["TEST_DATABASE_URL"]) as conn:
                conn.execute(statement, params)
            return "ok"
        except psycopg.Error as error:
            return str(error)

    try:
        with ThreadPoolExecutor(max_workers=2) as pool:
            results = list(
                pool.map(
                    lambda uid: attempt(
                        "select public.join_room(%s,'race-code','de','en')", (uid,)
                    ),
                    [b, c],
                )
            )
        assert results.count("ok") == 1
        assert sum("invalid_room" in result for result in results) == 1
        for _ in range(39):
            db.execute("select public.reserve_usage(%s,%s,15,0.01)", (a, room))
        db.commit()
        with ThreadPoolExecutor(max_workers=2) as pool:
            results = list(
                pool.map(
                    lambda _: attempt("select public.reserve_usage(%s,%s,15,0.01)", (a, room)),
                    [0, 1],
                )
            )
        assert results.count("ok") == 1
        assert sum("quota_exceeded" in result for result in results) == 1
        report = db.execute("select public.get_allowance(%s)", (a,)).fetchone()[0]
        assert report["used_seconds"] == 600
    finally:
        db.rollback()
        db.execute("delete from auth.users where id = any(%s)", (ids,))
        db.commit()


def test_wrong_code_language_mismatch_expiry_and_nonowner_close(db):
    from psycopg.errors import RaiseException

    a, b, _ = users(db)
    room = db.execute("select public.create_room(%s,'expiry-code','en','de')", (a,)).fetchone()[0]
    for code, source, target, message in [
        ("wrong-code", "de", "en", "invalid_room"),
        ("expiry-code", "ru", "en", "language_mismatch"),
    ]:
        with pytest.raises(RaiseException, match=message):
            with db.transaction():
                db.execute("select public.join_room(%s,%s,%s,%s)", (b, code, source, target))
    db.execute("select public.join_room(%s,'expiry-code','de','en')", (b,))
    with pytest.raises(RaiseException, match="forbidden"):
        with db.transaction():
            db.execute("select public.close_room(%s,%s,true)", (b, room))
    db.execute(
        "update public.conversations set created_at=now()-interval '2 hours', "
        "expires_at=now()-interval '1 hour' where id=%s",
        (room,),
    )
    with pytest.raises(RaiseException, match="forbidden"):
        with db.transaction():
            db.execute("select public.reserve_usage(%s,%s,1,0)", (a, room))
