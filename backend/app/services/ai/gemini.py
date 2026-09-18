from app.services.ai.base import AIProvider


class GeminiProvider(AIProvider):
    """Provider for Google Gemini via the ``google-genai`` SDK."""

    def __init__(
        self,
        api_key: str,
        model: str,
        name: str = "gemini",
        display_name: str = "Gemini",
        temperature: float = 0.3,
    ) -> None:
        super().__init__(name, display_name, model)
        self._api_key = api_key
        self._temperature = temperature
        self._client = None

    def _get_client(self):
        if self._client is None:
            # Imported lazily so the backend runs without the SDK when Gemini is disabled.
            from google import genai

            self._client = genai.Client(api_key=self._api_key)
        return self._client

    def complete(self, system_prompt: str, user_prompt: str) -> str:
        from google.genai import types

        response = self._get_client().models.generate_content(
            model=self.model,
            contents=user_prompt,
            config=types.GenerateContentConfig(
                system_instruction=system_prompt,
                temperature=self._temperature,
                response_mime_type="application/json",
            ),
        )
        return (response.text or "").strip()
