import httpx

from app.services.ai.base import AIProvider


class GeminiProvider(AIProvider):
    """Provider for Google Gemini via the ``google-genai`` SDK.

    Temperature stays at the API default of 1.0: Google recommends it for Gemini 3,
    lower values can make the model loop or reason worse, and 1.0 is what was measured.
    """

    def __init__(
        self,
        api_key: str,
        model: str,
        name: str = "gemini",
        display_name: str = "Gemini",
        temperature: float = 1.0,
        thinking_level: str | None = None,
        timeout: float = 60,
    ) -> None:
        super().__init__(name, display_name, model)
        self._api_key = api_key
        self._temperature = temperature
        self._thinking_level = thinking_level
        self._timeout = timeout
        self._client = None

    def _get_client(self):
        if self._client is None:
            # Imported lazily so the backend runs without the SDK when Gemini is disabled.
            from google import genai
            from google.genai import types

            # The SDK has no timeout by default and takes milliseconds.
            self._client = genai.Client(
                api_key=self._api_key,
                http_options=types.HttpOptions(timeout=int(self._timeout * 1000)),
            )
        return self._client

    def complete(self, system_prompt: str, user_prompt: str) -> str:
        from google.genai import types

        thinking = types.ThinkingConfig(thinking_level=self._thinking_level) if self._thinking_level else None
        response = self._get_client().models.generate_content(
            model=self.model,
            contents=user_prompt,
            config=types.GenerateContentConfig(
                system_instruction=system_prompt,
                temperature=self._temperature,
                response_mime_type="application/json",
                thinking_config=thinking,
            ),
        )
        return (response.text or "").strip()

    def is_transient(self, error: Exception) -> bool:
        from google.genai import errors

        if isinstance(error, (errors.ServerError, httpx.TransportError)):
            return True
        return isinstance(error, errors.ClientError) and error.code == 429
