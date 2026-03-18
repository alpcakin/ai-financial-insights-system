import logging
import requests
from datetime import date
from urllib.parse import urlparse
from supabase import Client

logger = logging.getLogger(__name__)

TRUSTED_DOMAINS = {
    "reuters.com",
    "bloomberg.com",
    "ft.com",
    "wsj.com",
    "cnbc.com",
    "marketwatch.com",
    "barrons.com",
    "economist.com",
    "seekingalpha.com",
    "investing.com",
    "finance.yahoo.com",
    "thestreet.com",
    "benzinga.com",
    "fool.com",
    "forbes.com",
    "businessinsider.com",
    "financialpost.com",
    "nasdaq.com",
    "fortune.com",
}


def _is_trusted(url: str) -> bool:
    try:
        host = urlparse(url).hostname or ""
        return any(host == d or host.endswith("." + d) for d in TRUSTED_DOMAINS)
    except Exception:
        return False


def fetch_articles(api_key: str, page_size: int) -> list[dict]:
    url = "http://api.mediastack.com/v1/news"
    params = {
        "access_key": api_key,
        "languages": "en",
        "categories": "business,technology",
        "sort": "popularity",
        "date": date.today().isoformat(),
        "limit": page_size,
    }
    response = requests.get(url, params=params, timeout=15)
    response.raise_for_status()
    data = response.json()

    articles = []
    for item in data.get("data", []):
        if not item.get("url") or not item.get("title"):
            continue
        articles.append({
            "title": item.get("title", ""),
            "url": item["url"],
            "description": item.get("description") or "",
            "source": item.get("source") or "",
            "published_at": item.get("published_at") or "",
        })
    return articles


def filter_new_articles(db: Client, articles: list[dict]) -> list[dict]:
    if not articles:
        return []

    trusted = [a for a in articles if _is_trusted(a["url"])]
    untrusted_count = len(articles) - len(trusted)
    if untrusted_count:
        logger.info("Dropped %d articles from untrusted domains", untrusted_count)

    if not trusted:
        return []

    urls = [a["url"] for a in trusted]
    result = db.table("articles").select("url").in_("url", urls).execute()
    existing_urls = {row["url"] for row in result.data}

    return [a for a in trusted if a["url"] not in existing_urls]
