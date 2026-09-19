"""
Central article analysis.

Every provider receives exactly the same prompt and every response goes
through the same parsing and validation, so results from different vendors
are comparable and the rest of the pipeline never needs to know which one
produced them.
"""

import json
import logging
import re
import time
from concurrent.futures import ThreadPoolExecutor

from app.services.ai import AIProvider, get_registry

logger = logging.getLogger(__name__)

MAX_ATTEMPTS = 3

#: Articles whose overall severity is at or below this are not shown to users.
MIN_SEVERITY = 4

SYSTEM_PROMPT = (
    "You are a financial news analyst. Analyze news articles and determine their impact on specific assets."
)

_FENCE_RE = re.compile(r"^```(?:json)?\s*|\s*```$", re.IGNORECASE)


def build_user_prompt(
    title: str,
    description: str,
    asset_pool: list[str],
    category_list: list[str],
) -> str:
    return f"""ARTICLE:
Title: "{title}"
Description: "{description}"

ACTIVE ASSETS IN SYSTEM:
{json.dumps(asset_pool)}

CATEGORY SYSTEM:
{json.dumps(category_list)}

Respond in this exact JSON format:
{{
  "summary": "One sentence summary (max 15 words)",
  "sentiment": "positive" | "negative" | "neutral",
  "severity": 1-10,
  "categories": ["category1", "category2"],
  "impacted_assets": [
    {{
      "symbol": "F",
      "impact": "positive" | "negative" | "neutral",
      "severity": 1-10,
      "reason": "One sentence explanation"
    }}
  ]
}}
Rules:
- Only include assets from the ACTIVE ASSETS list
- Evaluate EVERY asset in the list for potential impact — including indirect effects via competition, market shifts, regulatory changes, or sector dynamics
- Only include assets where the asset-level severity is 4 or above
- A competitor losing market share is a POSITIVE impact for rivals — reason this through
- severity 1-3: low, 4-6: moderate, 7-10: high impact
- If no active assets meet the threshold, return empty array
- Categories must be from the provided list
- Respond ONLY with valid JSON"""


def _parse_json(raw: str) -> dict:
    text = _FENCE_RE.sub("", raw.strip())
    data = json.loads(text)
    if not isinstance(data, dict):
        raise ValueError("AI response is not a JSON object")
    return data


def _validate_response(data: dict, asset_pool: list[str], category_list: list[str]) -> dict:
    data["severity"] = max(1, min(10, int(data.get("severity", 5))))

    if data.get("sentiment") not in ("positive", "negative", "neutral"):
        data["sentiment"] = "neutral"

    valid_assets = []
    for asset in data.get("impacted_assets", []):
        if asset.get("symbol") not in asset_pool:
            continue
        if asset.get("impact") not in ("positive", "negative", "neutral"):
            asset["impact"] = "neutral"
        asset["severity"] = max(1, min(10, int(asset.get("severity", 5))))
        valid_assets.append(asset)
    data["impacted_assets"] = valid_assets

    data["categories"] = [c for c in data.get("categories", []) if c in category_list]
    data.setdefault("summary", "")

    return data


def analyze_article(
    title: str,
    description: str,
    asset_pool: list[str],
    category_list: list[str],
    provider: AIProvider | None = None,
) -> dict | None:
    """Analyze one article with one provider.

    Returns the validated analysis plus ``provider``, ``model``,
    ``raw_response`` and ``latency_ms``, or None when the provider failed.
    """
    if provider is None:
        provider = get_registry().default
        if provider is None:
            logger.error("analyze_article called with no AI provider configured")
            return None

    user_prompt = build_user_prompt(title, description, asset_pool, category_list)

    for attempt in range(1, MAX_ATTEMPTS + 1):
        started = time.perf_counter()
        try:
            raw = provider.complete(SYSTEM_PROMPT, user_prompt)
            latency_ms = int((time.perf_counter() - started) * 1000)
            data = _validate_response(_parse_json(raw), asset_pool, category_list)
            data["provider"] = provider.name
            data["model"] = provider.model
            data["raw_response"] = raw
            data["latency_ms"] = latency_ms
            return data
        except (json.JSONDecodeError, KeyError, ValueError, TypeError) as e:
            logger.warning("[%s] attempt %d returned malformed output: %s", provider.name, attempt, e)
        except Exception as e:
            logger.error("[%s] unexpected error on attempt %d: %s", provider.name, attempt, e)
            break

    return None


def analyze_article_all(
    title: str,
    description: str,
    asset_pool: list[str],
    category_list: list[str],
    providers: list[AIProvider] | None = None,
) -> dict[str, dict]:
    """Analyze one article with every enabled provider in parallel.

    Returns a mapping of provider name to analysis, containing only the
    providers that succeeded. An empty mapping means nobody could analyze
    the article.
    """
    if providers is None:
        providers = get_registry().all()
    if not providers:
        return {}

    results: dict[str, dict] = {}
    with ThreadPoolExecutor(max_workers=len(providers)) as executor:
        futures = {
            executor.submit(analyze_article, title, description, asset_pool, category_list, p): p
            for p in providers
        }
        for future, provider in futures.items():
            analysis = future.result()
            if analysis is not None:
                results[provider.name] = analysis
    return results


def qualifies(analysis: dict) -> bool:
    """Whether an analysis is strong enough to be shown to users at all."""
    return analysis.get("severity", 0) >= MIN_SEVERITY
