from supabase import Client


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
