import os
from dataclasses import dataclass
from decimal import Decimal


@dataclass(frozen=True)
class Settings:
    supabase_url: str
    anon_key: str
    service_key: str
    openai_key: str
    room_pepper: str
    languages: tuple[str, ...] = ("en", "de", "ru", "tr")
    transcribe_model: str = "gpt-4o-mini-transcribe"
    translate_model: str = "gpt-4.1-mini"
    tts_model: str = "gpt-4o-mini-tts"
    estimated_usd_per_minute: Decimal = Decimal("0.10")

    @classmethod
    def from_env(cls):
        required = [
            "SUPABASE_URL",
            "SUPABASE_ANON_KEY",
            "SUPABASE_SERVICE_ROLE_KEY",
            "OPENAI_API_KEY",
            "ROOM_CODE_PEPPER",
        ]
        if any(not os.getenv(key) for key in required):
            raise RuntimeError(
                "Missing server configuration. See .env.example; values are not logged."
            )
        languages = tuple(os.getenv("ENABLED_LANGUAGES", "en,de,ru,tr").split(","))
        if "uz" in languages and os.getenv("EXPERIMENTAL_UZBEK") != "true":
            raise RuntimeError("Uzbek requires EXPERIMENTAL_UZBEK=true and acceptance testing.")
        if len(os.environ["ROOM_CODE_PEPPER"]) < 32:
            raise RuntimeError("ROOM_CODE_PEPPER must have at least 32 random characters.")
        estimate = Decimal(os.getenv("ESTIMATED_USD_PER_MINUTE", "0.10"))
        if not estimate.is_finite() or estimate <= 0:
            raise RuntimeError("ESTIMATED_USD_PER_MINUTE must be a finite positive estimate.")
        return cls(
            *(os.environ[key] for key in required),
            languages=languages,
            transcribe_model=os.getenv("OPENAI_TRANSCRIBE_MODEL", "gpt-4o-mini-transcribe"),
            translate_model=os.getenv("OPENAI_TRANSLATE_MODEL", "gpt-4.1-mini"),
            tts_model=os.getenv("OPENAI_TTS_MODEL", "gpt-4o-mini-tts"),
            estimated_usd_per_minute=estimate,
        )
