"""
Which categories and user topics a story relates to, and who follows them.

Snap answers for the package and, unless the user picked one of their own models,
for a manual-mode user's stories (DEVELOPMENT_JOURNAL.md 2.71). A story whose
matching failed is stored with topics_pending_since and asked about again by later
cycles, without analyzing it again, for up to RETRY_WINDOW.
"""

import logging
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone

from supabase import Client

from app.core.config import settings
from app.services.ai import AIProvider
from app.services.ai_service import match_topics
from app.services.topic_matching import snap_probabilities

logger = logging.getLogger(__name__)

MATCHED_BY_SNAP = "snap"

#: A story found this late is no longer news to the people following its topics.
RETRY_WINDOW = timedelta(hours=24)

PENDING_COLUMNS = "id, title, description, source, url"


@dataclass
class TopicMatch:
    #: One row per asked topic: topic_id, probability (None from a user's model), matched.
    rows: list[dict]
    matched_by: str

    @property
    def matched_ids(self) -> set[str]:
        return {row["topic_id"] for row in self.rows if row["matched"]}


def question_sets(db: Client, owner_id: str | None = None) -> tuple[dict[str, str], dict[str, str]]:
    """The fixed categories, and the user topics someone follows (only the owner,
    for a manual-mode story), each as id to name in the order they are asked."""
    categories = {
        row["id"]: row["name"]
        for row in db.table("categories").select("id, name").eq("kind", "category").eq("level", 2)
        .order("name").execute().data
    }
    followed = db.table("followed_topics").select("category_id")
    if owner_id:
        followed = followed.eq("user_id", owner_id)
    followed_ids = list({row["category_id"] for row in followed.execute().data})
    topics = {}
    if followed_ids:
        topics = {
            row["id"]: row["name"]
            for row in db.table("categories").select("id, name").eq("kind", "topic").in_("id", followed_ids)
            .order("created_at").execute().data
        }
    return categories, topics


def match_story(
    lead: dict,
    categories: dict[str, str],
    topics: dict[str, str],
    model: AIProvider | None = None,
) -> TopicMatch | None:
    """``model`` is a manual-mode user's own topic model; when it fails, Snap answers.
    None means nobody could answer."""
    if model is not None:
        asked = {**categories, **topics}
        related = match_topics(model, lead["title"], lead["description"] or "", asked)
        if related is not None:
            return TopicMatch(
                [{"topic_id": t, "probability": None, "matched": t in related} for t in asked], model.name,
            )
        logger.warning("Topic model failed on %s, Snap answers instead", lead.get("url"))

    probabilities = snap_probabilities(lead, [categories, topics])
    if probabilities is None:
        return None
    threshold = settings.topic_match_threshold
    return TopicMatch(
        [{"topic_id": t, "probability": p, "matched": p >= threshold} for t, p in probabilities.items()],
        MATCHED_BY_SNAP,
    )


def store_match(db: Client, article_id: str, match: TopicMatch) -> None:
    if match.rows:
        db.table("article_topics").upsert(
            [{**row, "article_id": article_id, "matched_by": match.matched_by} for row in match.rows],
            on_conflict="article_id,topic_id",
        ).execute()


def topic_followers(db: Client, matched_ids: set[str], only_user: str | None = None) -> dict[str, set[str]]:
    """Users following a matched topic or the parent of a matched category, each
    with the topics of theirs that matched."""
    if not matched_ids:
        return {}
    rows = db.table("categories").select("id, parent_id").in_("id", list(matched_ids)).execute().data
    wanted = {row["id"] for row in rows} | {row["parent_id"] for row in rows if row.get("parent_id")}
    query = db.table("followed_topics").select("user_id, category_id").in_("category_id", list(wanted))
    if only_user:
        query = query.eq("user_id", only_user)
    followers: dict[str, set[str]] = {}
    for row in query.execute().data:
        followers.setdefault(row["user_id"], set()).add(row["category_id"])
    return followers


def pending_stories(db: Client, owner_id: str | None = None) -> list[dict]:
    """Stories of one workspace still waiting for their topics, oldest first.
    Those past RETRY_WINDOW are given up on."""
    cutoff = (datetime.now(timezone.utc) - RETRY_WINDOW).isoformat()

    def scoped(query):
        return query.eq("owner_id", owner_id) if owner_id else query.is_("owner_id", "null")

    expired = scoped(db.table("articles").update({"topics_pending_since": None})).lt("topics_pending_since", cutoff)
    for row in expired.execute().data:
        logger.warning("Gave up matching topics of %s after %s", row.get("url"), RETRY_WINDOW)
    return (
        scoped(db.table("articles").select(PENDING_COLUMNS)).gte("topics_pending_since", cutoff)
        .order("topics_pending_since").execute().data
    )


def pending_owners(db: Client, user_ids: list[str]) -> set[str]:
    """Which of these manual-mode users have stories waiting for their topics."""
    if not user_ids:
        return set()
    cutoff = (datetime.now(timezone.utc) - RETRY_WINDOW).isoformat()
    rows = db.table("articles").select("owner_id").in_("owner_id", user_ids).gte("topics_pending_since", cutoff).execute()
    return {row["owner_id"] for row in rows.data}


def clear_pending(db: Client, article_id: str) -> None:
    db.table("articles").update({"topics_pending_since": None}).eq("id", article_id).execute()


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()
