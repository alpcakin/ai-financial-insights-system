import logging

from app.services.ai.base import AIProvider, ProviderInfo

logger = logging.getLogger(__name__)

#: Labels for providers that may appear in stored data even if the provider
#: is later disabled, so the app can still show who produced an analysis.
DISPLAY_NAMES = {
    "openai": "GPT-4o mini",
    "gemini": "Gemini",
    "grok": "Grok",
}


def display_name_for(provider_name: str | None) -> str:
    if not provider_name:
        return "Unknown"
    registry = get_registry()
    provider = registry.get(provider_name) if registry else None
    if provider is not None:
        return provider.display_name
    return DISPLAY_NAMES.get(provider_name, provider_name.capitalize())


class ProviderRegistry:
    """Holds the enabled providers in a stable order plus the default one."""

    def __init__(self, providers: list[AIProvider], default_name: str | None = None) -> None:
        self._providers: dict[str, AIProvider] = {}
        for provider in providers:
            if provider.name in self._providers:
                raise ValueError(f"Duplicate AI provider name: {provider.name}")
            self._providers[provider.name] = provider

        if not self._providers:
            self._default: AIProvider | None = None
        elif default_name and default_name in self._providers:
            self._default = self._providers[default_name]
        else:
            if default_name:
                logger.warning(
                    "Default AI provider %r is not enabled, falling back to %r",
                    default_name, next(iter(self._providers)),
                )
            self._default = next(iter(self._providers.values()))

    def all(self) -> list[AIProvider]:
        return list(self._providers.values())

    def names(self) -> list[str]:
        return list(self._providers.keys())

    def get(self, name: str | None) -> AIProvider | None:
        if name is None:
            return None
        return self._providers.get(name)

    def has(self, name: str | None) -> bool:
        return name is not None and name in self._providers

    @property
    def default(self) -> AIProvider | None:
        return self._default

    def resolve(self, preferred: str | None) -> AIProvider | None:
        """Return the preferred provider when enabled, otherwise the default."""
        return self.get(preferred) or self._default

    def infos(self) -> list[dict]:
        return [
            {**provider.info().__dict__, "is_default": provider is self._default}
            for provider in self._providers.values()
        ]

    def __len__(self) -> int:
        return len(self._providers)


def build_registry(settings) -> ProviderRegistry:
    """Create providers for every vendor that has an API key configured."""
    from app.services.ai.openai_compatible import OpenAICompatibleProvider
    from app.services.ai.gemini import GeminiProvider

    providers: list[AIProvider] = []

    if settings.openai_api_key:
        providers.append(OpenAICompatibleProvider(
            name="openai",
            display_name=DISPLAY_NAMES["openai"],
            model=settings.openai_model,
            api_key=settings.openai_api_key,
        ))

    if settings.gemini_api_key:
        providers.append(GeminiProvider(
            api_key=settings.gemini_api_key,
            model=settings.gemini_model,
            display_name=DISPLAY_NAMES["gemini"],
        ))

    if settings.xai_api_key:
        providers.append(OpenAICompatibleProvider(
            name="grok",
            display_name=DISPLAY_NAMES["grok"],
            model=settings.grok_model,
            api_key=settings.xai_api_key,
            base_url=settings.xai_base_url,
        ))

    registry = ProviderRegistry(providers, settings.default_ai_provider)
    if len(registry) == 0:
        logger.warning("No AI providers configured; article analysis is disabled")
    else:
        logger.info(
            "AI providers enabled: %s (default: %s)",
            ", ".join(registry.names()), registry.default.name,
        )
    return registry


_registry: ProviderRegistry | None = None


def get_registry() -> ProviderRegistry:
    global _registry
    if _registry is None:
        from app.core.config import settings

        _registry = build_registry(settings)
    return _registry


def set_registry(registry: ProviderRegistry | None) -> None:
    """Replace the process-wide registry. Used by tests and by tools that
    want to run the pipeline with a hand-picked set of providers."""
    global _registry
    _registry = registry
