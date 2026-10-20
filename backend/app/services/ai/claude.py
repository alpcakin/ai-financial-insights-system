from app.services.ai.base import AIProvider


class ClaudeRefusal(Exception):
    """The model declined to answer. Retrying the same prompt would not help."""


class ClaudeProvider(AIProvider):
    """Provider for Anthropic Claude via the ``anthropic`` SDK.

    Current Claude models reject non-default sampling parameters, so unlike
    the other providers no temperature is sent. Thinking is adaptive on these
    models; ``effort`` keeps it short for a task this small. There is no
    schema-free JSON mode, so the shared prompt's "respond only with JSON"
    rule is what keeps the output parseable.

    The SDK already retries rate limits and server errors with backoff, so
    ``is_transient`` keeps its default.
    """

    def __init__(
        self,
        api_key: str,
        model: str,
        name: str = "claude",
        display_name: str = "Claude",
        effort: str = "low",
        max_tokens: int = 4096,
    ) -> None:
        super().__init__(name, display_name, model)
        self._api_key = api_key
        self._effort = effort
        self._max_tokens = max_tokens
        self._client = None

    def _get_client(self):
        if self._client is None:
            # Imported lazily so the backend runs without the SDK when Claude is disabled.
            import anthropic

            self._client = anthropic.Anthropic(api_key=self._api_key)
        return self._client

    def complete(self, system_prompt: str, user_prompt: str) -> str:
        response = self._get_client().messages.create(
            model=self.model,
            max_tokens=self._max_tokens,
            system=system_prompt,
            output_config={"effort": self._effort},
            messages=[{"role": "user", "content": user_prompt}],
        )
        if response.stop_reason == "refusal":
            category = getattr(response.stop_details, "category", None)
            raise ClaudeRefusal(f"model declined the request (category: {category})")
        # Thinking blocks come before the answer, so pick text blocks by type.
        return "".join(block.text for block in response.content if block.type == "text").strip()
