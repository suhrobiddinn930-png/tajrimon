"""Check configured services without printing credentials or upstream response bodies.

Default checks are read-only. --audio-smoke makes small billable OpenAI requests using
synthetic speech, exercises the real translation adapter, and saves no audio/transcript.
No users, rooms, subscriptions or database schemas are created or changed.
"""

import argparse
import asyncio
import base64
import io
import json
import struct
import sys
import wave
from dataclasses import asdict, dataclass
from pathlib import Path

import httpx
from dotenv import load_dotenv

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from backend.config import Settings  # noqa: E402
from backend.services.audio import OpenAITranslator, audio_seconds  # noqa: E402


@dataclass
class Check:
    name: str
    status: str
    detail: str


def declared_role(key: str) -> str:
    """Diagnostic only: unverified claims are never used for authentication."""
    try:
        segment = key.split(".")[1]
        claims = json.loads(base64.urlsafe_b64decode(segment + "=" * (-len(segment) % 4)))
        role = claims.get("role")
        return role if role in ("anon", "service_role") else "unknown"
    except (ValueError, IndexError, TypeError):
        return "not-legacy-jwt"


def failure(response: httpx.Response) -> str:
    # Map only known codes, never return arbitrary server errors or request data.
    try:
        body = response.json()
        value = body.get("error", body)
        codes = (value.get("code"), value.get("type")) if isinstance(value, dict) else ()
    except (ValueError, AttributeError):
        codes = ()
    explanations = {
        "credit_balance_exhausted": "OpenAI prepaid credit balance exhausted",
        "organization_spend_limit_exceeded": "OpenAI organization spend limit reached",
        "project_spend_limit_exceeded": "OpenAI project spend limit reached",
        "organization_usage_limit_exceeded": "OpenAI approved organization usage limit reached",
        "insufficient_quota": "OpenAI billing quota/credits unavailable",
        "invalid_api_key": "API key rejected",
        "model_not_found": "Model unavailable to this API project",
        "rate_limit_exceeded": "Provider request rate exceeded",
        "PGRST205": "Database table not found; apply migrations",
        "PGRST202": "Database RPC not found; apply migrations",
        "42501": "Insufficient database privileges",
    }
    for code in codes:
        if isinstance(code, str) and code in explanations:
            return explanations[code]
    return f"HTTP {response.status_code}; upstream body hidden"


def to_transport_wav(payload: bytes) -> bytes:
    """Resample tiny synthetic test audio to the exact mobile transport format."""
    with wave.open(io.BytesIO(payload), "rb") as source:
        if source.getnchannels() != 1 or source.getsampwidth() != 2:
            raise ValueError("Unexpected synthetic audio format")
        rate = source.getframerate()
        raw = source.readframes(rate * 12)
    samples = struct.unpack("<" + "h" * (len(raw) // 2), raw)
    frames = int(len(samples) * 16000 / rate)
    resampled = [samples[min(int(i * rate / 16000), len(samples) - 1)] for i in range(frames)]
    output = io.BytesIO()
    with wave.open(output, "wb") as target:
        target.setnchannels(1)
        target.setsampwidth(2)
        target.setframerate(16000)
        target.writeframes(struct.pack("<" + "h" * len(resampled), *resampled))
    return output.getvalue()


async def check_services(audio_smoke: bool):
    load_dotenv(ROOT / ".env", override=True)
    results = []

    def record(name, status, detail):
        results.append(Check(name, status, detail))
        print(f"{name}: {status} - {detail}", flush=True)

    try:
        settings = Settings.from_env()
    except Exception:
        record("configuration", "FAIL", "Required server settings are missing or invalid")
        return results
    record("configuration", "PASS", "Required settings loaded; values hidden")
    role = declared_role(settings.service_key)
    if role == "anon":
        record("service_key_role", "FAIL", "Anon key was placed in the server service-role setting")
    elif settings.service_key == settings.anon_key:
        record("service_key_role", "FAIL", "Public and privileged keys are identical")
    else:
        record("service_key_role", "INFO", "Remote permission checks will verify server access")

    async with httpx.AsyncClient(timeout=20, follow_redirects=False) as client:

        async def probe(name, url, headers, params=None):
            try:
                response = await client.get(url, headers=headers, params=params)
                record(
                    name,
                    "PASS" if response.is_success else "FAIL",
                    f"HTTP {response.status_code}" if response.is_success else failure(response),
                )
                return response
            except httpx.HTTPError:
                record(name, "FAIL", "Connection failed or timed out; details hidden")
                return None

        base = settings.supabase_url.rstrip("/")
        public = {"apikey": settings.anon_key}
        privileged = {
            "apikey": settings.service_key,
            "Authorization": f"Bearer {settings.service_key}",
        }
        await probe("supabase_auth", base + "/auth/v1/settings", public)
        admin = await probe(
            "supabase_server_access",
            base + "/auth/v1/admin/users",
            privileged,
            {"page": 1, "per_page": 1},
        )
        if admin is not None and admin.is_success:
            tables = [
                "profiles",
                "conversations",
                "conversation_participants",
                "usage_records",
                "subscriptions",
                "user_preferences",
            ]
            await asyncio.gather(
                *(
                    probe(
                        "table_" + table,
                        base + "/rest/v1/" + table,
                        privileged,
                        {"select": "*", "limit": 0},
                    )
                    for table in tables
                )
            )
            try:
                rpc = await client.post(
                    base + "/rest/v1/rpc/get_allowance",
                    headers=privileged,
                    json={"p_user": "00000000-0000-0000-0000-000000000000"},
                )
                record(
                    "allowance_rpc",
                    "PASS" if rpc.is_success else "FAIL",
                    f"HTTP {rpc.status_code}" if rpc.is_success else failure(rpc),
                )
            except httpx.HTTPError:
                record("allowance_rpc", "FAIL", "Connection failed; details hidden")
        else:
            record("database_schema", "SKIP", "Fix server key access before checking schema")

        ai_headers = {"Authorization": f"Bearer {settings.openai_key}"}
        model = await probe(
            "openai_auth_model",
            "https://api.openai.com/v1/models/" + settings.translate_model,
            ai_headers,
        )
        if not audio_smoke:
            record(
                "audio_pipeline", "SKIP", "Pass --audio-smoke for a small billable synthetic test"
            )
        elif model is not None and model.is_success:
            try:
                # Check actual billing using a tiny text request before generating audio.
                text = await client.post(
                    "https://api.openai.com/v1/responses",
                    headers=ai_headers,
                    json={
                        "model": settings.translate_model,
                        "store": False,
                        "input": "Translate Hello to German. Only the translation.",
                        "max_output_tokens": 32,
                    },
                )
                if not text.is_success:
                    record("openai_paid_request", "FAIL", failure(text))
                    record("audio_pipeline", "SKIP", "Resolve OpenAI paid-request failure first")
                    return results
                record("openai_paid_request", "PASS", "Small Responses request succeeded")
                speech = await client.post(
                    "https://api.openai.com/v1/audio/speech",
                    headers=ai_headers,
                    timeout=60,
                    json={
                        "model": settings.tts_model,
                        "voice": "coral",
                        "input": "Hello, how are you?",
                        "response_format": "wav",
                    },
                )
                if not speech.is_success:
                    record("audio_pipeline", "FAIL", failure(speech))
                    return results
                audio = to_transport_wav(speech.content)
                duration = audio_seconds(audio)
                translator = OpenAITranslator(settings, client)
                result = await translator.translate(audio, "en", "de", "coral")
                if not result.original or not result.translated or not result.audio:
                    raise ValueError("Empty pipeline result")
                record(
                    "audio_pipeline",
                    "PASS",
                    f"{duration}s synthetic WAV -> STT -> German translation -> audio; "
                    "nothing saved",
                )
            except Exception:
                record(
                    "audio_pipeline",
                    "FAIL",
                    "Audio adapter failed; secrets and response bodies hidden",
                )
        else:
            record("audio_pipeline", "SKIP", "Fix OpenAI authentication/model access first")
    return results


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--audio-smoke", action="store_true")
    args = parser.parse_args()
    results = asyncio.run(check_services(args.audio_smoke))
    report = ROOT / "docs/SERVICE_CHECK.json"
    report.write_text(
        json.dumps([asdict(item) for item in results], indent=2) + "\n", encoding="utf-8"
    )
    return 1 if any(item.status == "FAIL" for item in results) else 0


if __name__ == "__main__":
    raise SystemExit(main())
