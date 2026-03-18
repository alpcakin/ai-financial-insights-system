import json
import logging
from openai import OpenAI
from app.core.config import settings

logger = logging.getLogger(__name__)

_client: OpenAI | None = None


def _get_client() -> OpenAI:
    global _client
    if _client is None:
        _client = OpenAI(api_key=settings.openai_api_key)
    return _client


def analyze_article(
    title: str,
    description: str,
    asset_pool: list[str],
    category_list: list[str],
) -> dict | None:
    system_prompt = (
        "You are a financial news analyst. Analyze news articles and determine their impact on specific assets."
    )
    user_prompt = f"""ARTICLE:
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
- Only include assets that are MEANINGFULLY impacted
- severity 1-3: low, 4-6: moderate, 7-10: high impact
- If no active assets impacted, return empty array
- Categories must be from the provided list
- Respond ONLY with valid JSON"""

    client = _get_client()
    for attempt in range(3):
        try:
            response = client.chat.completions.create(
                model="gpt-4o-mini",
                temperature=0.3,
                messages=[
                    {"role": "system", "content": system_prompt},
                    {"role": "user", "content": user_prompt},
                ],
            )
            raw = response.choices[0].message.content.strip()
            data = json.loads(raw)
            return _validate_response(data, asset_pool, category_list)
        except (json.JSONDecodeError, KeyError, ValueError) as e:
            logger.warning("analyze_article attempt %d failed: %s", attempt + 1, e)
        except Exception as e:
            logger.error("analyze_article unexpected error on attempt %d: %s", attempt + 1, e)
            break

    return None


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

    return data
