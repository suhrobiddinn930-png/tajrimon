import io
import wave

import httpx

from backend.services.audio import audio_seconds
from scripts.check_services import declared_role, failure, to_transport_wav


def test_unknown_upstream_secrets_are_not_in_diagnostic_output():
    response = httpx.Response(429, json={"error": {"message": "sensitive-secret-value"}})
    assert failure(response) == "HTTP 429; upstream body hidden"
    response = httpx.Response(
        429, json={"error": {"code": "insufficient_quota", "message": "sensitive-secret-value"}}
    )
    assert failure(response) == "OpenAI billing quota/credits unavailable"


def test_untrusted_key_claims_are_not_returned():
    assert declared_role("not-a-jwt") == "not-legacy-jwt"
    assert declared_role("a.e30.b") == "unknown"


def test_quota_error_type_is_recognized_without_disclosing_message():
    response = httpx.Response(
        429,
        json={"error": {"code": None, "type": "insufficient_quota", "message": "secret"}},
    )
    assert failure(response) == "OpenAI billing quota/credits unavailable"


def test_malformed_upstream_error_fields_are_safe():
    for body in ({"error": {"code": {"secret": "value"}}}, ["secret"], {"error": "secret"}):
        assert failure(httpx.Response(429, json=body)) == "HTTP 429; upstream body hidden"


def test_specific_billing_code_takes_precedence_over_broad_quota_type():
    for code, expected in (
        ("credit_balance_exhausted", "OpenAI prepaid credit balance exhausted"),
        ("organization_spend_limit_exceeded", "OpenAI organization spend limit reached"),
        ("project_spend_limit_exceeded", "OpenAI project spend limit reached"),
        ("organization_usage_limit_exceeded", "OpenAI approved organization usage limit reached"),
    ):
        response = httpx.Response(
            429,
            json={"error": {"code": code, "type": "insufficient_quota", "message": "secret"}},
        )
        assert failure(response) == expected


def test_synthetic_speech_resampling_matches_mobile_transport():
    original = io.BytesIO()
    with wave.open(original, "wb") as stream:
        stream.setnchannels(1)
        stream.setsampwidth(2)
        stream.setframerate(24000)
        stream.writeframes(b"\x00\x01" * 24000)
    transport = to_transport_wav(original.getvalue())
    assert audio_seconds(transport) == 1
    with wave.open(io.BytesIO(transport)) as stream:
        assert stream.getframerate() == 16000
        assert stream.getnframes() == 16000
