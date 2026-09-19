"""
Pluggable AI providers for article analysis.

The rest of the backend never talks to a vendor SDK directly. It asks the
registry for a provider (or for all enabled providers) and calls the
provider's ``complete`` method with the shared prompt built in
``app.services.ai_service``. Adding a new vendor means writing one small
subclass of ``AIProvider`` and registering it in ``registry.build_registry``.
"""

from app.services.ai.base import AIProvider, ProviderInfo
from app.services.ai.registry import (
    ProviderRegistry,
    build_registry,
    get_registry,
    set_registry,
    display_name_for,
)

__all__ = [
    "AIProvider",
    "ProviderInfo",
    "ProviderRegistry",
    "build_registry",
    "get_registry",
    "set_registry",
    "display_name_for",
]
