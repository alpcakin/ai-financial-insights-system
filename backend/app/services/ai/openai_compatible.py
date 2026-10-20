from openai import OpenAI

from app.services.ai.base import AIProvider


class OpenAICompatibleProvider(AIProvider):
    """Provider for any API that speaks the OpenAI chat-completions protocol.

    Used for OpenAI itself and for xAI's Grok, which exposes the same
    protocol at a different base URL. Vendors that differ only by endpoint
    and model name can be added with a single line in the registry.

    Reasoning models reject any temperature other than the default, so when
    ``reasoning_effort`` is set it is sent instead of ``temperature``.

    The OpenAI SDK already retries rate limits and server errors with
    backoff, so ``is_transient`` keeps its default.
    """

    def __init__(
        self,
        name: str,
        display_name: str,
        model: str,
        api_key: str,
        base_url: str | None = None,
        temperature: float = 0.3,
        reasoning_effort: str | None = None,
    ) -> None:
        super().__init__(name, display_name, model)
        self._api_key = api_key
        self._base_url = base_url
        self._temperature = temperature
        self._reasoning_effort = reasoning_effort
        self._client: OpenAI | None = None

    def _get_client(self) -> OpenAI:
        if self._client is None:
            self._client = OpenAI(api_key=self._api_key, base_url=self._base_url)
        return self._client

    def complete(self, system_prompt: str, user_prompt: str) -> str:
        tuning = (
            {"reasoning_effort": self._reasoning_effort}
            if self._reasoning_effort
            else {"temperature": self._temperature}
        )
        response = self._get_client().chat.completions.create(
            model=self.model,
            response_format={"type": "json_object"},
            messages=[
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": user_prompt},
            ],
            **tuning,
        )
        return (response.choices[0].message.content or "").strip()
