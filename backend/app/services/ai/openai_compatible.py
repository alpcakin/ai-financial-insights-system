import httpx
from openai import OpenAI

from app.services.ai.base import AIProvider


class OpenAICompatibleProvider(AIProvider):
    """Provider for any API that speaks the OpenAI chat-completions protocol.

    Used for OpenAI itself. Vendors that differ only by endpoint and model
    name can be added with a single line in the registry.

    Reasoning models reject any temperature other than the default, so when
    ``reasoning_effort`` is set it is sent instead of ``temperature``. A user's
    model may be either kind, so neither is sent when both are None.

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
        temperature: float | None = 0.3,
        reasoning_effort: str | None = None,
        timeout: float = 60,
        http_client: httpx.Client | None = None,
    ) -> None:
        super().__init__(name, display_name, model)
        self._api_key = api_key
        self._base_url = base_url
        self._temperature = temperature
        self._reasoning_effort = reasoning_effort
        self._timeout = timeout
        self._http_client = http_client
        self._client: OpenAI | None = None

    def _get_client(self) -> OpenAI:
        if self._client is None:
            self._client = OpenAI(
                api_key=self._api_key,
                base_url=self._base_url,
                timeout=self._timeout,
                http_client=self._http_client,
            )
        return self._client

    def complete(self, system_prompt: str, user_prompt: str) -> str:
        if self._reasoning_effort:
            tuning = {"reasoning_effort": self._reasoning_effort}
        elif self._temperature is not None:
            tuning = {"temperature": self._temperature}
        else:
            tuning = {}
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
