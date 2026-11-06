"""A user's stored model as a provider, and what its failures mean.

Sampling settings are left at each model's default: a user's model can be of any
kind and some reject settings others need. Prompt, schema and validation are the
shared ones in ai_service, so only the transport differs from the package.
"""

import httpx

from app.core.config import settings
from app.core.safe_http import BlockedAddress, guarded_client
from app.services.ai import AIProvider
from app.services.ai.claude import ClaudeProvider
from app.services.ai.gemini import GeminiProvider
from app.services.ai.openai_compatible import OpenAICompatibleProvider

MAX_MODEL_RESPONSE_BYTES = 2 * 1024 * 1024

#: Longer than the read timeout, which covers the wait for the first byte alone.
_DEADLINE_MARGIN_SECONDS = 30

_CONNECTION_ERRORS = ("APIConnectionError", "APITimeoutError")


def build_provider(name: str, kind: str, model: str, label: str, api_key: str, base_url: str | None = None) -> AIProvider:
    """``name`` is what the analysis is stored under: the model's id."""
    timeout = settings.ai_request_timeout_seconds
    if kind == "openai":
        provider = OpenAICompatibleProvider(
            name=name, display_name=label, model=model, api_key=api_key, temperature=None, timeout=timeout,
        )
    elif kind == "compatible":
        provider = OpenAICompatibleProvider(
            name=name, display_name=label, model=model, api_key=api_key, base_url=base_url,
            temperature=None, timeout=timeout,
            http_client=guarded_client(
                MAX_MODEL_RESPONSE_BYTES,
                timeout + _DEADLINE_MARGIN_SECONDS,
                timeout,
                headers={"Accept-Encoding": "identity"},
                allow_compressed=False,
            ),
        )
    elif kind == "gemini":
        provider = GeminiProvider(api_key=api_key, model=model, name=name, display_name=label, timeout=timeout)
    elif kind == "claude":
        provider = ClaudeProvider(api_key=api_key, model=model, name=name, display_name=label, effort=None, timeout=timeout)
    else:
        raise ValueError(f"Unknown model kind: {kind!r}")
    provider.private = True
    return provider


def classify_failure(error: Exception) -> str:
    """Why a model failed. The error text is read here but never stored or logged.

    - "auth": the key or model was rejected. Retrying cannot help.
    - "quota": the account is out of credit. Retrying cannot help.
    - "unreachable": rate limit, server or network trouble, worth trying later.
    - "article": anything else, such as malformed output for this one article.
    """
    status = getattr(error, "status_code", None)
    code = getattr(error, "code", None)
    if status is None and isinstance(code, int):
        status = code
    text = str(error).lower()

    if status == 402 or code == "insufficient_quota" or "credit balance" in text:
        return "quota"
    # Gemini answers a bad key with 400.
    if status in (401, 403, 404) or (status == 400 and "api key" in text):
        return "auth"
    if status == 429 or (isinstance(status, int) and status >= 500):
        return "unreachable"
    if isinstance(error, (httpx.TransportError, BlockedAddress, OSError)) or type(error).__name__ in _CONNECTION_ERRORS:
        return "unreachable"
    return "article"
