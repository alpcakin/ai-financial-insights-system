"""
Groups articles that report the same event, so each event is analyzed once.

An event ("story") is represented by its first article, the lead. A new
article is compared only with leads, never with other members, so a story
cannot drift from one event to another through a chain of similar articles.
Embedding similarity only picks the candidates; SubQ Snap decides every match,
because recurring reports (daily roundups, price updates) are nearly identical
text from one day to the next. User API keys never reach this module: in manual
mode the user can only turn grouping on, and the same system then runs inside
their own articles. This is the system frozen on 2026-11-01; changing any of it
invalidates the measurements (DEVELOPMENT_JOURNAL.md 2.57, 2.60).
"""

import logging
import math
from dataclasses import dataclass, field
from datetime import datetime, timedelta, timezone

import requests
from openai import OpenAI
from supabase import Client

from app.core.config import settings

logger = logging.getLogger(__name__)

EMBEDDING_MODEL = "text-embedding-3-small"

SNAP_URL = "https://api.subq.ai/v1/systemone"
SNAP_TIMEOUT_SECONDS = 30

SAME_EVENT_QUESTION = (
    "Do the NEW REPORT and the EARLIER REPORT describe the same event? "
    "Use their titles, summaries and publication times."
)

SAME_EVENT_RULE = """## Same event

Both reports are about one single occurrence: the same actor doing or saying the same thing at the same time. One occurrence is, for example, one announcement, one deal, one ruling, one data release, one company's results, one statement by one person, or one move of one index, asset or stock in one trading session. A report that only adds detail to the same picture is still the same event: a name for someone already in the story, exact figures, or quotes from the same statement. Different outlets, different wording, or the same piece republished under a new title do not make it a different event.

Examples:
- "A defendant walks into the courthouse" and "Adil B. walks into the courthouse" are the same event; the second report only names the defendant.
- "Governor Y says rates will stay on hold" and "Y signals no change in rates" are the same event: one statement by one person.

## Different events

The main subject or the main action is not exactly the same. In particular:

1. Different speakers: each statement, comment, interview or forecast is its own event. Statements by different people are different events, even on the same topic. Example: "Ahmet A. comments on the fall in bitcoin" and "Behzat C. comments on the fall in bitcoin" are different events.
2. A statement about an occurrence is a different event from the occurrence. Example: "Bitcoin falls 10%" and "Ahmet A. says the fall in bitcoin is temporary" are different events.
3. Analysis and opinion: a report whose main content is analysis, explanation or opinion about an occurrence (what it means, why it happened, what comes next) is a different event from the occurrence and from other analyses. Example: "Bank X reports third-quarter results" and "What Bank X's results mean for investors" are different events.
4. Reactions and consequences: what happens because of an occurrence is a different event: a price move, a market reaction, a company's response, an investigation. Example: "Company X announces layoffs" and "Company X shares fall after the layoff announcement" are different events.
5. Different market subjects are different events, even in the same session. Example: "The Nasdaq falls 2%" and "The S&P 500 falls 1.5%" are different events, and so are "Stocks plunge" and "Volatility jumps as stocks plunge".
6. The same company, person or topic is not enough: different news about the same subject is a different event.
7. A follow-up with a new development (new figures, a second deal, a next step) is a different event.
8. Recurring reports from different days or sessions are different events: market wraps, price updates, lists of movers.
9. A preview of a scheduled event (a budget, a rate decision, company results) and the report of its outcome are different events.
10. A newsletter, show or roundup covering several stories is the same event as another report only if its main story is that same occurrence.
"""

_same_event, _different_events = SAME_EVENT_RULE.split("## Different events")
SAME_EVENT_CRITERIA = {
    "true": "Same event: " + _same_event.replace("## Same event", "").strip(),
    "false": "Different events: " + _different_events.strip(),
}


class GroupingUnavailable(Exception):
    """Grouping could not run at all. In manual mode the analysis waits instead,
    because every duplicate would otherwise be analyzed with the user's own key."""


@dataclass
class SnapTally:
    asked: int = 0
    failed: int = 0


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


def _stored_candidates(
    db: Client,
    embedding: list[float],
    published_from: datetime,
    published_to: datetime,
    owner_id: str | None,
) -> list[dict]:
    result = db.rpc("match_story_leads", {
        "query_embedding": embedding,
        "min_similarity": settings.dedup_candidate_threshold,
        "published_from": published_from.isoformat(),
        "published_to": published_to.isoformat(),
        "p_owner_id": owner_id,
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


def build_snap_request(article: dict, candidate: dict) -> dict:
    state = f"NEW REPORT:\n{_describe(article)}\n\nEARLIER REPORT:\n{_describe(candidate, _published(article))}"
    return {
        "model": settings.snap_model,
        "state": state,
        "questions": {"same_event": {
            "type": "noul",
            "instructions": SAME_EVENT_QUESTION,
            "criteria": SAME_EVENT_CRITERIA,
        }},
    }


def _same_event_probability(article: dict, candidate: dict) -> float | None:
    try:
        response = requests.post(
            SNAP_URL,
            headers={"Authorization": f"Bearer {settings.subq_api_key}"},
            json=build_snap_request(article, candidate),
            timeout=SNAP_TIMEOUT_SECONDS,
        )
        response.raise_for_status()
        probability = float(response.json()["answers"]["same_event"]["noul"])
        if not 0 <= probability <= 1:
            raise ValueError(f"probability out of range: {probability}")
    except Exception as e:
        logger.warning("Same-event judge failed for %s: %s", article["url"], e)
        return None
    return probability


def judge_same_event(article: dict, candidates: list[dict], tally: SnapTally | None = None) -> int | None:
    """Index of the candidate most likely to report the same event, or None.

    Each candidate is a separate request, the form that was measured. A failed
    request counts as "not the same": the worst outcome is then a duplicate card,
    never a story hidden inside another.
    """
    if not settings.subq_api_key:
        logger.warning("SUBQ_API_KEY is not set, %s becomes a new story", article["url"])
        return None
    answers = [_same_event_probability(article, c) for c in candidates]
    if tally is not None:
        tally.asked += len(answers)
        tally.failed += answers.count(None)
    probabilities = [0.0 if p is None else p for p in answers]
    # max keeps the first of equal values, and candidates come closest first.
    best = max(range(len(candidates)), key=probabilities.__getitem__)
    logger.info("Snap asked about %d candidates, best p %.3f: %s", len(candidates), probabilities[best], article["title"])
    return best if probabilities[best] >= settings.dedup_match_probability else None


def assign_stories(
    db: Client,
    articles: list[dict],
    owner_id: str | None = None,
    require_judge: bool = False,
) -> tuple[list[Story], list[Attachment]]:
    """Split new articles, oldest first, into new stories and attachments to stored ones.

    Compares only inside one workspace: the shared one, or ``owner_id``'s. Sets
    ``embedding`` on every article and ``duplicate_similarity`` on articles that
    joined a story from the same cycle.

    With ``require_judge``, raises GroupingUnavailable when there are no embeddings
    or when every Snap request failed. A single failed request still counts as
    "not the same", as in the frozen system.
    """
    if not articles:
        return [], []
    if require_judge and not settings.subq_api_key:
        raise GroupingUnavailable
    try:
        embeddings = embed_articles(articles)
    except Exception as e:
        logger.error("Embedding failed, every article becomes its own story: %s", e)
        embeddings = None
    if embeddings is None:
        if require_judge:
            raise GroupingUnavailable
        for article in articles:
            article["embedding"] = None
        return [Story(lead=a) for a in articles], []

    window = timedelta(hours=settings.dedup_window_hours)
    stories: list[Story] = []
    attachments: list[Attachment] = []
    tally = SnapTally()

    for article, embedding in zip(articles, embeddings):
        article["embedding"] = embedding
        published = _published(article)
        candidates = _stored_candidates(db, embedding, published - window, published + window, owner_id) + [
            {
                "story": story,
                "source": story.lead["source"],
                "title": story.lead["title"],
                "description": story.lead["description"],
                "published_at": story.lead["published_at"],
                "similarity": _cosine(embedding, story.lead["embedding"]),
            }
            for story in stories
            if abs(_published(story.lead) - published) <= window
        ]
        candidates = sorted(
            (c for c in candidates if c["similarity"] >= settings.dedup_candidate_threshold),
            key=lambda c: c["similarity"],
            reverse=True,
        )

        match = None
        if candidates:
            index = judge_same_event(article, candidates, tally)
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

    if require_judge and tally.asked and tally.failed == tally.asked:
        raise GroupingUnavailable
    return stories, attachments
