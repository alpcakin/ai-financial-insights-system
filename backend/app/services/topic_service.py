import logging

from fastapi import HTTPException, status
from postgrest.exceptions import APIError
from supabase import Client

from app.core.rate_limit import topic_check_limiter
from app.services.topic_matching import check_topic_text

logger = logging.getLogger(__name__)

#: Topics a user follows besides the fixed categories. Each one is a question
#: about every new story, so the list stays short.
MAX_OWN_TOPICS = 10
MIN_NAME_LENGTH = 2
MAX_NAME_LENGTH = 40
#: The name sits inside a quoted question to Snap, so quotes and markup are out.
_ALLOWED_PUNCTUATION = set(" &+-.,'()/")
#: Either gate answer at or above this rejects a new topic text.
GATE_PROBABILITY = 0.5

TOPIC_COLUMNS = "id, name, level, parent_id, kind"


def _followable(row: dict) -> bool:
    return row["kind"] == "topic" or row["level"] in (1, 2)


def _with_status(row: dict, followed_ids: set[str]) -> dict:
    return {**{k: row.get(k) for k in TOPIC_COLUMNS.split(", ")}, "followed": row["id"] in followed_ids}


def _followed_ids(db: Client, user_id: str) -> set[str]:
    rows = db.table("followed_topics").select("category_id").eq("user_id", user_id).execute().data
    return {row["category_id"] for row in rows}


def get_topics_with_status(db: Client, user_id: str) -> list[dict]:
    """The fixed categories, then the user's own topics in the order they followed them."""
    followed_ids = _followed_ids(db, user_id)
    cats = (
        db.table("categories").select(TOPIC_COLUMNS).eq("kind", "category").in_("level", [1, 2])
        .order("level").order("name").execute().data
    )
    own = []
    if followed_ids:
        own = (
            db.table("categories").select(TOPIC_COLUMNS).eq("kind", "topic").in_("id", list(followed_ids))
            .order("name").execute().data
        )
    return [_with_status(row, followed_ids) for row in cats + own]


def _own_topic_count(db: Client, user_id: str) -> int:
    followed_ids = _followed_ids(db, user_id)
    if not followed_ids:
        return 0
    return len(db.table("categories").select("id").eq("kind", "topic").in_("id", list(followed_ids)).execute().data)


def _check_own_limit(db: Client, user_id: str) -> None:
    if _own_topic_count(db, user_id) >= MAX_OWN_TOPICS:
        raise HTTPException(
            status.HTTP_400_BAD_REQUEST,
            f"You can follow at most {MAX_OWN_TOPICS} topics of your own. Remove one to add another.",
        )


def _follow(db: Client, user_id: str, row: dict) -> None:
    if row["kind"] == "topic" and row["id"] not in _followed_ids(db, user_id):
        _check_own_limit(db, user_id)
    db.table("followed_topics").upsert(
        {"user_id": user_id, "category_id": row["id"], "source": "manual"},
        on_conflict="user_id,category_id",
    ).execute()


def follow_topic(db: Client, user_id: str, category_id: str) -> None:
    rows = db.table("categories").select(TOPIC_COLUMNS).eq("id", category_id).execute().data
    if not rows or not _followable(rows[0]):
        raise HTTPException(status_code=404, detail="Topic not found")
    _follow(db, user_id, rows[0])


def unfollow_topic(db: Client, user_id: str, category_id: str) -> None:
    db.table("followed_topics").delete().eq("user_id", user_id).eq(
        "category_id", category_id
    ).execute()


def normalize_topic_name(name: str) -> str:
    name = " ".join(name.split())
    if not MIN_NAME_LENGTH <= len(name) <= MAX_NAME_LENGTH:
        raise HTTPException(
            status.HTTP_422_UNPROCESSABLE_ENTITY,
            f"A topic is {MIN_NAME_LENGTH} to {MAX_NAME_LENGTH} characters long.",
        )
    if not all(ch.isalnum() or ch in _ALLOWED_PUNCTUATION for ch in name):
        raise HTTPException(
            status.HTTP_422_UNPROCESSABLE_ENTITY,
            "Use letters, numbers, spaces and & + - . , ' ( ) / only.",
        )
    return name


def _find_by_name(db: Client, name: str) -> dict | None:
    # No % or _ can reach here (normalize_topic_name), so this is a case-insensitive equality.
    rows = db.table("categories").select(TOPIC_COLUMNS).ilike("name", name).execute().data
    return rows[0] if rows else None


def _gate(db: Client, user_id: str, name: str) -> bool:
    """Whether Snap lets this text in, asked once per text for all users."""
    key = name.lower()
    known = db.table("topic_checks").select("accepted").eq("text_key", key).execute().data
    if known:
        return known[0]["accepted"]

    retry_after = topic_check_limiter.hit(user_id)
    if retry_after:
        raise HTTPException(
            status.HTTP_429_TOO_MANY_REQUESTS,
            "Too many new topics. Please try again later.",
            headers={"Retry-After": str(retry_after)},
        )
    try:
        answers = check_topic_text(name)
    except Exception as e:
        logger.warning("Topic check failed: %s", type(e).__name__)
        raise HTTPException(status.HTTP_503_SERVICE_UNAVAILABLE, "Topics cannot be checked right now. Please try again.") from e

    accepted = answers["instruction"] < GATE_PROBABILITY and answers["offensive"] < GATE_PROBABILITY
    db.table("topic_checks").upsert({
        "text_key": key,
        "accepted": accepted,
        "instruction_probability": answers["instruction"],
        "offensive_probability": answers["offensive"],
    }, on_conflict="text_key").execute()
    return accepted


def add_topic(db: Client, user: dict, name: str) -> dict:
    """Follow a topic by name. An existing category or topic is followed as it is;
    a new text first passes the gate and then joins the shared list."""
    user_id = user["id"]
    name = normalize_topic_name(name)

    row = _find_by_name(db, name)
    if row is None:
        _check_own_limit(db, user_id)
        if not _gate(db, user_id, name):
            raise HTTPException(
                status.HTTP_422_UNPROCESSABLE_ENTITY,
                "This can't be added as a topic. Name a subject, such as a company, a sector or an event.",
            )
        try:
            row = db.table("categories").insert(
                {"name": name, "kind": "topic", "created_by": user_id}
            ).execute().data[0]
        except APIError as e:
            # Someone added the same name a moment ago.
            if e.code != "23505":
                raise
            row = _find_by_name(db, name)
    elif not _followable(row):
        raise HTTPException(status_code=404, detail="Topic not found")

    _follow(db, user_id, row)
    return _with_status(row, {row["id"]})


def search_topics(db: Client, user_id: str, query: str) -> list[dict]:
    """Existing categories and topics whose name contains the text, to pick from
    before adding a new one."""
    query = " ".join(query.split())
    if len(query) < MIN_NAME_LENGTH or not all(ch.isalnum() or ch in _ALLOWED_PUNCTUATION for ch in query):
        return []
    rows = db.table("categories").select(TOPIC_COLUMNS).ilike("name", f"%{query}%").order("name").limit(20).execute().data
    followed_ids = _followed_ids(db, user_id)
    return [_with_status(row, followed_ids) for row in rows if _followable(row)][:10]


def auto_subscribe(db: Client, user_id: str, category_name: str | None) -> None:
    if not category_name:
        return

    cat_result = (
        db.table('categories')
        .select('id')
        .eq('name', category_name)
        .execute()
    )
    if not cat_result.data:
        return

    category_id = cat_result.data[0]['id']
    db.table('followed_topics').upsert(
        {'user_id': user_id, 'category_id': category_id, 'source': 'auto'},
        on_conflict='user_id,category_id',
    ).execute()


def auto_unsubscribe(db: Client, user_id: str, category_name: str | None) -> None:
    if not category_name:
        return

    remaining_portfolio = (
        db.table('portfolio')
        .select('id')
        .eq('user_id', user_id)
        .eq('category', category_name)
        .execute()
    )
    remaining_watchlist = (
        db.table('watchlist')
        .select('id')
        .eq('user_id', user_id)
        .eq('category', category_name)
        .execute()
    )
    if remaining_portfolio.data or remaining_watchlist.data:
        return

    cat_result = (
        db.table('categories')
        .select('id')
        .eq('name', category_name)
        .execute()
    )
    if not cat_result.data:
        return

    category_id = cat_result.data[0]['id']
    db.table('followed_topics').delete().eq('user_id', user_id).eq('category_id', category_id).eq('source', 'auto').execute()
