from fastapi import HTTPException
from supabase import Client


def get_topics_with_status(db: Client, user_id: str) -> list[dict]:
    cats = (
        db.table("categories")
        .select("id, name, level, parent_id")
        .in_("level", [1, 2])
        .order("level")
        .order("name")
        .execute()
    )
    followed = (
        db.table("followed_topics")
        .select("category_id")
        .eq("user_id", user_id)
        .execute()
    )
    followed_ids = {row["category_id"] for row in followed.data}
    return [
        {
            "id": row["id"],
            "name": row["name"],
            "level": row["level"],
            "parent_id": row.get("parent_id"),
            "followed": row["id"] in followed_ids,
        }
        for row in cats.data
    ]


def follow_topic(db: Client, user_id: str, category_id: str) -> None:
    cat = (
        db.table("categories")
        .select("id, level")
        .eq("id", category_id)
        .in_("level", [1, 2])
        .execute()
    )
    if not cat.data:
        raise HTTPException(status_code=404, detail="Category not found")
    db.table("followed_topics").upsert(
        {"user_id": user_id, "category_id": category_id, "source": "manual"},
        on_conflict="user_id,category_id",
    ).execute()


def unfollow_topic(db: Client, user_id: str, category_id: str) -> None:
    db.table("followed_topics").delete().eq("user_id", user_id).eq(
        "category_id", category_id
    ).execute()


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
