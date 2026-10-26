# Allowance SQL reapplication — 2026-10-26

Changed the allowance migration to `CREATE OR REPLACE FUNCTION` so rerunning it in SQL Editor
updates the existing `get_allowance(uuid)` instead of failing with PostgreSQL error 42723.
The function signature, security-definer settings and service-role-only execution remain intact.
Fresh isolated PostgreSQL 18 run: all three migrations applied, **10 integration tests passed**.
The new regression reapplied the allowance migration twice and verified unchanged function identity,
allowance data and role permissions. Ruff lint/format checks passed. Hosted SQL was not executed.

# Interface localization — 2026-10-26

- Added Uzbek (default), English and Russian UI copy for auth, home, rooms, live audio controls,
  device routing guidance, history, usage, profile/privacy and known error/status messages.
- Added a language menu on every page, including before login. Selection persists on the device.
  Device language mode resolves supported regional locales and falls back to Uzbek.
- Language changes preserve navigation and in-progress login form fields. They do not change the
  room's speech language pair. No database migration is needed for this device preference.
- Flutter Material localizations and the browser HTML language attribute follow the selected UI
  language. The initial web loading message is Uzbek.
- Flutter analyze: **no issues**. Dart format: **24 files, no changes**. Flutter tests: **6 passed**,
  including actual menu switching, form preservation, preference restoration, locale fallback and
  translated runtime values. Tests use no live accounts or paid provider requests.
- Fresh web release build: passed (the existing optional Cupertino font warning remains).
- Browser: Uzbek welcome/menu rendered; Russian selection updated the interface and HTML `lang`
  to `ru` and survived reload. Device mode matched browser `en-US` to English with HTML `lang=en`.
  The app remains available at `http://127.0.0.1:8001/app/`.
  Uzbek viewport screenshot: `docs/browser-uzbek-interface.png` (390×844). No JavaScript page
  errors were reported. The new web bundle was also scanned for configured server secrets;
  the AI key, service-role key and room pepper were absent.
- The previously built debug APK below predates this localization change; this check rebuilt the
  web app. Native platform behavior was not revalidated on a physical device.

# Startup recheck — 2026-10-26

- Backend offline/API tests: **41 passed**, 9 database integration cases deselected.
- Fresh isolated PostgreSQL 18 cluster: all **3 migrations applied**, **9 integration tests
  passed**. The cluster was stopped afterward. This uses the documented Auth SQL shim.
- Ruff lint and format checks: passed, **25 files**. Dart format: **19 files, no changes**.
- Flutter analyze: no issues. Flutter tests: **3 passed**.
- Fresh Flutter web release build: passed. An optional Cupertino icon-font warning remains.
- Hosted Supabase: Auth settings, admin permission checks, all six application tables and
  allowance RPC passed. The temporary-account flow passed confirmed-password login, signup
  triggers, private profile/preferences RLS, two-user room admission, outsider denial,
  allowance/history, two-client audio socket admission, ticket replay denial and room revocation.
  All three temporary accounts were deleted. No email or speech was sent by this flow.
- Browser callback allowlist check: passed. **Hosted Android callback allowlist: failed**.
  Local `supabase/config.toml` now matches the browser origin and native callback, but changing
  this file does not update the hosted project. Add `ai.live.translator://auth-callback/` under
  hosted Supabase Authentication → URL Configuration → Redirect URLs. No Supabase management
  credential is configured in the repository, so the hosted setting was not changed.
- OpenAI API-key identity endpoint: HTTP 200; the account email was reported privately in chat
  and was not saved in this document or the service report. Model access: HTTP 200.
  **Actual paid request: HTTP 429, `credit_balance_exhausted` (type `insufficient_quota`)**.
  The configured organization's prepaid API credits are exhausted. Diagnostics now recognize
  specific billing codes before the broader quota type, without exposing upstream messages.
  Real STT/translation/TTS was skipped after this rejection. Fix API billing/quota for the
  configured account, then rerun `python scripts/check_services.py --audio-smoke`.
- Local app started at `http://127.0.0.1:8001/app/`. `/health`, `/app/` and
  `/app/main.dart.js`: HTTP 200. `/usage/me` without authentication: HTTP 401.
- All generated web files were scanned for the actual configured AI key, service-role key
  and room pepper; none contained those server secrets.
- Browser welcome → login → signup navigation passed against the fresh build. Email/password,
  Sign in, Sign up and Forgot password controls rendered; no JavaScript page errors were reported.
  Screenshot: `docs/browser-recheck-2026-10-26.png`. No real-user login was attempted.
- `adb devices`: no attached Android device, so no APK installation or device audio test was run.
- Android build memory configuration corrected for this 8 GB PC: Gradle heap 2 GB,
  metaspace 1 GB, two workers, Kotlin daemon heap 768 MB. The first build was deliberately
  stopped after its Java processes committed over 10 GB and the host became slow; the build
  was restarted with these limits. This was not an application-code compilation failure.
- Android debug APK: **build passed**, 161 seconds in the restarted Gradle run. Artifact:
  `mobile/build/app/outputs/flutter-apk/app-debug.apk` (177,976,875 bytes). Android SDK Platform 35
  and CMake 3.22.1 were installed by the SDK build tooling. A future Flutter compatibility warning
  remains for `record_android` using the Kotlin Gradle Plugin; it did not fail this build.
  Every uncompressed APK entry was scanned for the actual server AI key, service-role key
  and room pepper; none were present. The project Gradle daemon was stopped after the build.
- iOS builds and physical-device microphone/Bluetooth/latency/background tests were not performed
  on this Windows host.

# Implementation and verification — 2026-10-23

## Browser and Android preparation — 2026-10-23

Implemented account-scoped history/allowance caches and language-pair reset, serialized audio
pause cleanup, and prevented a recording stopped during disconnect from being sent after a
reconnect. Participant initials use grapheme characters. Supabase network failures now become
safe HTTP 503 errors. The Flutter bootstrap discovers the project-local SDK; CI formatting now
fails on unformatted source instead of modifying it.

- Backend offline tests: **38 passed**, 9 integration tests deselected.
- Flutter analyzer: **no issues**; Flutter tests: **3 passed**, including account-switch cache isolation.
- Ruff lint/format: passed, **25 files** formatted.
- Flutter web release build: passed after these changes. The compiler emitted an optional
  Cupertino icon-font warning; no missing rendered icon was observed in login/signup checks.
- Browser at 390×844: login and signup navigation passed; no JavaScript page errors reported.
  Screenshot: `docs/browser-mobile-ready.png`.
- Actual server credentials/room pepper were absent from all **35 web build files**.
- `python scripts/check_user_flow.py`: real hosted Auth confirmed-password login, signup
  profile/preferences triggers, profile/preferences RLS, two-user room admission and outsider
  denial through REST and direct RLS, Free 600-second allowance/history, audio ticket issuance,
  two real local WebSocket connections, used-ticket replay denial, and both socket closures
  on partner leave all passed. Three temporary accounts were removed afterward.
- No email was sent and no AI request or usage reservation occurred during that user-flow check.
  This does not verify email confirmation/reset callbacks, Realtime or translated speech.
- Android/iOS runners generated. Microsoft JDK 21, Android SDK/NDK and project-local build
  scripts prepared; Android APK build verification is recorded separately when complete.
- `adb devices`: no attached device at this check.

The earlier OpenAI paid-request HTTP 429 still prevents real translation acceptance.
An additional recovery-link-generation check (no email delivery) accepted browser
`http://127.0.0.1:8001/app/`, but **rejected the native callback**
`ai.live.translator://auth-callback/`. Add that native URL under Supabase Authentication →
URL Configuration → Redirect URLs, then retest. The same later diagnostic encountered a
transient connection/response failure at room creation; it still deleted its temporary accounts.
The earlier complete user-flow pass remains the executed evidence above.
Production HTTPS hosting, release signing and physical-device audio acceptance
remain required. iOS runners were generated but not built on this Windows host.

## Earlier recheck — 2026-10-23

This recheck supersedes the earlier hosted-schema failures below. Both versioned migrations
applied to a fresh isolated PostgreSQL 18 cluster; all 9 database/RLS/concurrency tests passed.
The offline backend suite passed all 37 tests separately. Ruff lint and format checks passed
(22 files already formatted). Flutter analyze found no issues, and both Flutter tests passed.

The configured hosted Supabase Auth and admin endpoints, all six application tables, and
`get_allowance` RPC returned HTTP 200. This confirms schema availability, not an authenticated
two-user end-to-end session. No hosted schema changes were made by this diagnostic.

OpenAI model access returned HTTP 200, but the tiny paid Responses request again returned
HTTP 429 with no recognized error classification. The audio smoke test therefore skipped
speech generation and translation. Actual speech translation remains unverified; the precise
reason for the provider rejection is unknown.

Started the existing local web build with `python scripts/run_web.py --no-build`;
`/health`, `/app/`, and `/app/main.dart.js` returned HTTP 200 on port 8001. This recheck
did not rebuild the web bundle or exercise browser interactions or physical devices.
The latest sanitized service report is `docs/SERVICE_CHECK.json`.

## Earlier executed results

| Check | Actual result |
| --- | --- |
| Offline unit / HTTP / two-client WebSocket / safe diagnostics tests | **37 passed** in latest run |
| PostgreSQL 18 migrations | Both migrations applied successfully |
| PostgreSQL RLS / permissions / room / quota / concurrency tests | **9 passed**, 34 unrelated tests deselected |
| SQL parser (`pglast`) | Both migration files parsed successfully |
| Ruff lint | `All checks passed!` |
| Python bytecode compilation | Passed |
| Flutter bootstrap | Stopped with `Install Flutter stable and add flutter to PATH first.` |
| Flutter analyze (follow-up) | Passed: No issues found |
| Flutter tests (follow-up) | 2 passed: WAV encoding and welcome/login/signup navigation |
| Flutter web release build (follow-up) | Passed; served with FastAPI at `/app/` on local port 8001 |
| Android/iOS builds | Not run; no mobile SDK/device configured |
| Supabase hosted connectivity (later service check) | Auth settings and server admin access: HTTP 200; all six application tables and allowance RPC missing |
| OpenAI hosted connectivity (later service check) | Configured translation model accessible: HTTP 200; tiny paid Responses request returned HTTP 429 |
| Real speech translation / semantic quality | Not run: stopped after paid-request rejection |
| Supabase Auth / PostgREST / Realtime end-to-end | Not complete: hosted application migrations have not been applied |
| Bluetooth / background / physical-device endurance | Not run |
| GitHub Actions | Workflow added; not executed remotely |
| Hosted deploy / store publication | Not performed |

## Local browser application follow-up

Installed project-local Flutter 3.47.7 / Dart 3.13.5 under ignored `.sdk/`. Resolved dependencies
and retained `mobile/pubspec.lock`. Fixed router type inference, overlapping audio library names,
non-constant audio session options and analyzer findings. Web skips native Bluetooth discovery
and uses the browser/system audio route. Native and browser auth redirect targets are separate.

`python scripts/run_web.py` builds the same Flutter app and serves it alongside its API at
`http://127.0.0.1:8001/app/`. `/app/`, `/app/main.dart.js` and `/health` returned HTTP 200.
Browser automation rendered the welcome screen, clicked Get started, and confirmed the real
login form (Email, Password, Sign in, Create an account, Forgot password). No account was created
or signed in during the browser check. The test browser was closed; the local server stayed running.
Screenshot: `docs/browser-app.png`. Actual OpenAI key, service-role key and room pepper were checked
against generated JS/JSON/HTML client files and were absent.

This validates local UI startup/navigation, not live translation. Hosted database migrations and
the previously observed OpenAI paid-request HTTP 429 remain unresolved until separately retested.
Supabase Auth redirect allowlist needs `http://127.0.0.1:8001/app/` for browser email callbacks.

## Follow-up with user-configured services

`python scripts/check_services.py --audio-smoke` loaded the saved `.env` without displaying
credentials. Internet access required the approved network-enabled run. The report is in
`docs/SERVICE_CHECK.json` and contains only fixed diagnostic labels/statuses.

- Supabase Auth settings: HTTP 200.
- Supabase server credential/admin access: HTTP 200.
- All six application tables: not found by PostgREST.
- `get_allowance` RPC: not found.
- OpenAI configured translation-model access: HTTP 200.
- Actual small Responses request: HTTP 429; the returned body was not displayed. The precise
  cause was not classified, so do not claim definitively that billing credit is exhausted.
- Real audio pipeline: skipped after that rejection; no synthetic audio was generated or stored.
- Backend startup with the real configuration: `/health` HTTP 200 (`ok`).
- Protected `/usage/me` without a token: HTTP 401, as expected.
- Offline tests initially rerun: 34 passed; after adding diagnostic redaction/resampling checks,
  the final run had **37 passed**, 9 database integration cases deselected.

Next: apply both versioned migrations in the hosted Supabase project, check OpenAI billing and
request limits, then rerun the diagnostic. It performs no schema changes or account creation.
An audio smoke test, when enabled, makes small billable requests using only synthetic speech.

Total: **46 passing test cases across separate runs** (37 offline in the latest run plus 9
PostgreSQL cases in the earlier database run). Do not report this as a single
end-to-end mobile test run. Integration tests used an isolated local PostgreSQL 18.3 cluster,
real database roles and SQL row-level policies, plus a minimal `auth.users` / `auth.uid()` /
`auth.jwt()` compatibility shim. They did not mock SQL execution or the row locks. The shim does
not exercise the actual Supabase Auth server, JWT verification service, PostgREST or Realtime.

Executed commands:

```text
python -m pytest -q --tb=short -p no:cacheprovider
34 passed; integration cases skipped without TEST_DATABASE_URL

python scripts/test_postgres.py --bin "C:\Program Files\PostgreSQL\18\bin"
9 passed, 34 deselected

python -m ruff check backend scripts
All checks passed!
```

`scripts/test_postgres.py` creates a fresh cluster under ignored `.test-postgres/`, uses a free
loopback port and stops its own server in `finally`. It never targets the installed database
service. Test fixture commits in the concurrency test are cleaned up using their exact UUIDs.

The environment's Python 3.14 emitted upstream FastAPI/Starlette `asyncio.iscoroutinefunction`
deprecation warnings. The configured deployment image uses Python 3.12. There were no assertions
failed in the final runs. Initial verification issues (oversized pytest parameter IDs, lint
findings and Windows inherited subprocess pipes) were corrected before the final results.

## Delivery stages

| Stage | Main files | State |
| --- | --- | --- |
| 1. Architecture / repository | `docs/ARCHITECTURE.md`, `pyproject.toml`, `AGENTS.md` | Created; Git initialized, no commits |
| 2. Database / RLS | `supabase/migrations/202610230001_foundation.sql`, `202610230002_allowance.sql` | Applied/tested on isolated PostgreSQL |
| 3. Authentication / rooms | `backend/api/app.py`, `services/database.py`, Flutter `features/auth`, `features/conversation` | Server API tested; mobile/auth-service integration pending |
| 4. Two-person connection | `services/hub.py`, room RPCs, `live_controller.dart` | Two-client WS tests and real concurrent DB admission passed |
| 5. AI adapter | `services/audio.py` | Actual HTTP request contracts tested with stubbed provider; paid API pending |
| 6. Two-way translation | WS relay + `features/translation` | Both routing directions tested with test-only adapter; real speech pending |
| 7. Platform audio | `features/devices`, live controller, bootstrap script | Capture/playback/lifecycle code written; devices pending |
| 8. UI / history | `mobile/lib/features`, `app/app.dart` | Source written; analyzer/build/accessibility/device QA pending |
| 9. Plans / limits | allowance migration, `reserve_usage`, `features/subscription` | Real SQL quota/race tests passed; payment provider absent |
| 10. Tests / deploy | `backend/tests`, Dockerfile, `.github/workflows/verify.yml`, README | Local server/SQL checks passed; hosted/mobile deployment pending |

## Important limits

This is a foundation/MVP implementation, not the full continuous live-audio product in the brief.
Translation uses explicit short speech turns, not automatic VAD/continuous Realtime. Uzbek is
experimental and disabled by default. Translation quality, Bluetooth routing and app builds need
real validation. There is no background audio, saved-transcript feature, production payment flow,
actual token-level cost reconciliation, release signing or high-availability deployment.
Follow `DEVICE_ACCEPTANCE.md` before presenting it as a verified investor demo.
