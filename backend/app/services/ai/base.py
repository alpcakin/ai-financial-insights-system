from abc import ABC, abstractmethod
from dataclasses import dataclass


@dataclass(frozen=True)
class ProviderInfo:
    """Public description of a provider, safe to send to the mobile app."""

    name: str
    display_name: str
    model: str


class AIProvider(ABC):
    """One vendor-specific way of turning a prompt into a JSON string.

    Subclasses only implement transport. The prompt, the JSON parsing, the
    validation, the retries and the severity thresholds all live in
    ``app.services.ai_service`` so every provider is judged by the same rules.
    """

    #: Stable key stored in the database and chosen by users, e.g. "openai".
    name: str
    #: Human readable label shown in the app, e.g. "GPT-4o mini".
    display_name: str
    #: Vendor model identifier actually called.
    model: str

    def __init__(self, name: str, display_name: str, model: str) -> None:
        self.name = name
        self.display_name = display_name
        self.model = model

    @abstractmethod
    def complete(self, system_prompt: str, user_prompt: str) -> str:
        """Send the prompts to the model and return the raw response text.

        The text is expected to be a JSON object. Implementations should
        enable the vendor's JSON mode when one exists but must not parse or
        validate the result themselves.
        """

    def info(self) -> ProviderInfo:
        return ProviderInfo(name=self.name, display_name=self.display_name, model=self.model)

    def __repr__(self) -> str:
        return f"<{type(self).__name__} name={self.name!r} model={self.model!r}>"
