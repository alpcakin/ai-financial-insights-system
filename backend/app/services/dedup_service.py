"""
Groups articles that report the same event, so each event is analyzed once.

An event ("story") is represented by its first article, the lead. A new
article is compared only with leads, never with other members, so a story
cannot drift from one event to another through a chain of similar articles.
Embedding similarity only picks the candidates; the judge decides every
match, because recurring reports (daily roundups, price updates) are nearly
identical text from one day to the next. Measurements behind this:
DEVELOPMENT_JOURNAL.md, sections 2.14 and 2.29.
"""

import logging
import math
from dataclasses import dataclass, field
from datetime import datetime, timedelta, timezone

from openai import OpenAI
from supabase import Client

from app.core.config import settings
from app.services.ai import get_registry
from app.services.ai_service import _parse_json

logger = logging.getLogger(__name__)

EMBEDDING_MODEL = "text-embedding-3-small"

#: Closest leads shown to the judge.
MAX_CANDIDATES = 3

JUDGE_SYSTEM_PROMPT = "You decide whether financial news reports describe the same event."


@dataclass
class Story:
    """A new event: its lead plus the articles about it that arrived in the same cycle."""

    lead: dict
    members: list[dict] = field(default_factory=list)


@dataclass
class Attachment:
    """A new article about an event that was stored in an earlier cycle."""

    article: dict
    lead_id: str
    similarity: float


def embed_articles(articles: list[dict]) -> list[list[float]] | None:
    """One embedding per article, or None when no OpenAI key is configured."""
    if not settings.openai_api_key:
        return None
    client = OpenAI(api_key=settings.openai_api_key, timeout=settings.ai_request_timeout_seconds)
    response = client.embeddings.create(
        model=EMBEDDING_MODEL,
        input=[f"{a['title']}. {a['description']}" for a in articles],
    )
    return [item.embedding for item in response.data]


def _cosine(a: list[float], b: list[float]) -> float:
    dot = sum(x * y for x, y in zip(a, b))
    return dot / (math.sqrt(sum(x * x for x in a)) * math.sqrt(sum(y * y for y in b)))


def _stored_candidates(db: Client, embedding: list[float], since: datetime) -> list[dict]:
    result = db.rpc("match_story_leads", {
        "query_embedding": embedding,
        "since": since.isoformat(),
        "match_count": MAX_CANDIDATES,
    }).execute()
    return [
        {
            "lead_id": row["id"],
            "source": row["source"],
            "title": row["title"],
            "description": row["description"] or "",
            "published_at": row["published_at"],
            "similarity": row["similarity"],
        }
        for row in result.data
    ]


def _published(report: dict) -> datetime | None:
    value = report.get("published_at")
    return datetime.fromisoformat(value).astimezone(timezone.utc) if value else None


def _describe(report: dict, new_report_time: datetime | None = None) -> str:
    published = _published(report)
    if published is None:
        when = "Publication time unknown."
    elif new_report_time is None:
        when = f"Published {published:%Y-%m-%d %H:%M} UTC."
    else:
        hours = abs(new_report_time - published).total_seconds() / 3600
        when = f"Published {published:%Y-%m-%d %H:%M} UTC ({hours:.0f} h apart)."
    return f'{when} {report["source"]}: "{report["title"]}" - "{report["description"]}"'


def build_judge_prompt(article: dict, candidates: list[dict]) -> str:
    new_report_time = _published(article)
    earlier = "\n".join(f"{i}. {_describe(c, new_report_time)}" for i, c in enumerate(candidates, 1))
    return f"""NEW REPORT:
{_describe(article)}

EARLIER REPORTS:
{earlier}

Does the new report describe the same event as one of the earlier reports?
- Same event: one specific occurrence, such as an announcement, deal, ruling, data release or market move, reported by different outlets or rewritten by the same outlet.
- Not the same event: a follow-up that reports a new development, different news about the same company or topic, or a recurring report (market wrap, price update, list of movers) from a different day or session.
- A preview of a scheduled event (a budget, a rate decision, company results) and the report of its outcome are different events.

Respond ONLY with valid JSON: {{"match": <number of the earlier report that describes the same event, or 0 if none>}}"""


def judge_same_event(article: dict, candidates: list[dict]) -> int | None:
    """Index of the candidate reporting the same event, or None.

    Uses the default provider. Any failure counts as "no match": the worst
    outcome is then a duplicate card, never a story hidden inside another.
    """
    provider = get_registry().default
    if provider is None:
        return None
    try:
        raw = provider.complete(JUDGE_SYSTEM_PROMPT, build_judge_prompt(article, candidates))
        match = int(_parse_json(raw)["match"])
    except Exception as e:
        logger.warning("Same-event judge failed for %s: %s", article["url"], e)
        return None
    return match - 1 if 1 <= match <= len(candidates) else None


def assign_stories(db: Client, articles: list[dict]) -> tuple[list[Story], list[Attachment]]:
    """Split new articles, oldest first, into new stories and attachments to stored ones.

    Sets ``embedding`` on every article and ``duplicate_similarity`` on
    articles that joined a story from the same cycle.
    """
    if not articles:
        return [], []
    try:
        embeddings = embed_articles(articles)
    except Exception as e:
        logger.error("Embedding failed, every article becomes its own story: %s", e)
        embeddings = None
    if embeddings is None:
        for article in articles:
            article["embedding"] = None
        return [Story(lead=a) for a in articles], []

    since = datetime.now(timezone.utc) - timedelta(hours=settings.dedup_window_hours)
    stories: list[Story] = []
    attachments: list[Attachment] = []

    for article, embedding in zip(articles, embeddings):
        article["embedding"] = embedding
        candidates = _stored_candidates(db, embedding, since) + [
            {
                "story": story,
                "source": story.lead["source"],
                "title": story.lead["title"],
                "description": story.lead["description"],
                "published_at": story.lead["published_at"],
                "similarity": _cosine(embedding, story.lead["embedding"]),
            }
            for story in stories
        ]
        candidates = sorted(
            (c for c in candidates if c["similarity"] >= settings.dedup_candidate_threshold),
            key=lambda c: c["similarity"],
            reverse=True,
        )[:MAX_CANDIDATES]

        match = None
        if candidates:
            index = judge_same_event(article, candidates)
            if index is not None:
                match = candidates[index]

        if match is None:
            stories.append(Story(lead=article))
        elif "story" in match:
            article["duplicate_similarity"] = match["similarity"]
            match["story"].members.append(article)
        else:
            attachments.append(Attachment(article, match["lead_id"], match["similarity"]))

        if match is not None:
            logger.info(
                "Same event (%.2f): %s -> %s", match["similarity"], article["title"], match["title"],
            )

    return stories, attachments
