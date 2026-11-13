from datetime import datetime, timedelta, timezone
from types import SimpleNamespace
from unittest.mock import patch

import pytest

from app.services import asset_check_service as svc
from app.services.asset_check_service import Quote, check_asset, run_asset_check, same_name
from tests.catalog import catalog_row
from tests.fake_db import FakeDB

# Names below are what Yahoo returned on 2026-11-12 (DEVELOPMENT_JOURNAL.md 2.69).
ARB = catalog_row("ARB-USD", "Arbitrum", "crypto", "DeFi")
TON = catalog_row("TON-USD", "Toncoin", "crypto", "Altcoins")
XOM = catalog_row("XOM", "Exxon Mobil Corporation", "stock", "Oil & Gas")


@pytest.mark.parametrize("a, b", [
    ("Salesforce Inc.", "Salesforce, Inc."),
    ("The Coca-Cola Company", "Coca-Cola Company (The)"),
    ("Bitcoin", "Bitcoin USD"),
    ("Gold Futures", "Gold Dec 26"),
    ("Wheat Futures", "Chicago SRW Wheat Futures,Dec-2026"),
    ("SPDR S&P 500 ETF Trust", "State Street SPDR S&P 500 ETF Trust"),
    ("Polygon (prev. MATIC)", "Polygon (prev. MATIC) USD"),
])
def test_spellings_of_one_name_match(a, b):
    assert same_name(a, b)


@pytest.mark.parametrize("a, b", [
    ("Arbitrum", "ARbit USD"),
    ("Toncoin", "TON Token USD"),
    ("Exxon Mobil Corporation", "ExxonMobil Holdings Corporation"),
    ("Apple Inc.", None),
    ("Inc.", "Corporation"),
])
def test_different_names_do_not_match(a, b):
    assert not same_name(a, b)


def _yahoo(quotes: dict[str, Quote | None | Exception], searches: dict[str, list[Quote] | Exception]):
    def quote(symbol):
        result = quotes.get(symbol)
        if isinstance(result, Exception):
            raise result
        return result

    def search(query, asset_type):
        result = searches.get(query, [])
        if isinstance(result, Exception):
            raise result
        return result

    return patch.multiple(svc, _quote=quote, _search=search)


def test_matching_name_confirms_the_symbol():
    with _yahoo({"XOM": Quote("XOM", "Exxon Mobil Corp", None)}, {}):
        outcome = check_asset(XOM, [XOM])
    assert (outcome.action, outcome.yahoo_name) == ("confirmed", "Exxon Mobil Corp")


def test_a_search_that_leads_back_confirms_a_changed_name():
    quote = Quote("XOM", "ExxonMobil Holdings Corporation", None)
    with _yahoo({"XOM": quote}, {"Exxon Mobil Corporation": [quote]}):
        outcome = check_asset(XOM, [XOM])
    assert (outcome.action, outcome.yahoo_name) == ("confirmed", "ExxonMobil Holdings Corporation")


def test_the_confirmed_yahoo_name_is_the_reference_once_stored():
    asset = {**XOM, "yahoo_name": "ExxonMobil Holdings Corporation"}
    with _yahoo({"XOM": Quote("XOM", "ExxonMobil Holdings Corporation", None)}, {}):
        assert check_asset(asset, [asset]).action == "confirmed"


def test_a_single_candidate_takes_the_asset():
    with _yahoo(
        {"ARB-USD": Quote("ARB-USD", "ARbit USD", None), "ARB11841-USD": Quote("ARB11841-USD", "Arbitrum USD", "Arbitrum USD")},
        {"Arbitrum": [Quote("ARB11841-USD", "Arbitrum USD", "Arbitrum USD")]},
    ):
        outcome = check_asset(ARB, [ARB])
    assert outcome.action == "renamed"
    assert (outcome.new_symbol, outcome.new_name, outcome.yahoo_name) == ("ARB11841-USD", "Arbitrum", "Arbitrum USD")


def test_two_candidates_wait_for_a_decision():
    with _yahoo(
        {"TON-USD": Quote("TON-USD", "TON Token USD", None)},
        {"Toncoin": [
            Quote("GRAM-USD", "Gram (prev. Toncoin) USD", None),
            Quote("TON11419-USD", "Toncoin USD", None),
        ]},
    ):
        outcome = check_asset(TON, [TON])
    assert outcome.action == "review"
    assert outcome.note == (
        "Yahoo now names TON-USD 'TON Token USD'. "
        "Candidates: GRAM-USD (Gram (prev. Toncoin) USD), TON11419-USD (Toncoin USD)."
    )


def test_search_results_with_another_name_are_not_candidates():
    with _yahoo(
        {"ARB-USD": Quote("ARB-USD", "ARbit USD", None)},
        {"Arbitrum": [Quote("XYZ-USD", "Something Else USD", None)]},
    ):
        outcome = check_asset(ARB, [ARB])
    assert outcome.action == "review" and outcome.note.endswith("Candidates: none.")


def test_a_candidate_already_in_the_catalog_waits_for_a_decision():
    other = catalog_row("ARB11841-USD", "Arbitrum", "crypto", "DeFi")
    with _yahoo(
        {"ARB-USD": Quote("ARB-USD", "ARbit USD", None)},
        {"Arbitrum": [Quote("ARB11841-USD", "Arbitrum USD", None)]},
    ):
        outcome = check_asset(ARB, [ARB, other])
    assert outcome.action == "review" and "already in the catalog" in outcome.note


def test_a_candidate_without_a_price_waits_for_a_decision():
    with _yahoo(
        {"ARB-USD": Quote("ARB-USD", "ARbit USD", None), "ARB11841-USD": None},
        {"Arbitrum": [Quote("ARB11841-USD", "Arbitrum USD", None)]},
    ):
        outcome = check_asset(ARB, [ARB])
    assert outcome.action == "review" and "has no price" in outcome.note


@pytest.mark.parametrize("quote", [None, RuntimeError("404")])
def test_no_data_from_yahoo_is_a_missed_check(quote):
    with _yahoo({"XOM": quote}, {}):
        assert check_asset(XOM, [XOM]).action == "missed"


def test_a_failed_search_changes_nothing():
    with _yahoo({"ARB-USD": Quote("ARB-USD", "ARbit USD", None)}, {"Arbitrum": RuntimeError("timeout")}):
        assert check_asset(ARB, [ARB]).action == "skipped"


# ── run_asset_check ──────────────────────────────────────────────────────────

def _outcomes(**by_symbol):
    return patch.object(svc, "check_asset", side_effect=lambda asset, catalog: by_symbol[asset["symbol"]])


def test_outcomes_are_written_to_the_catalog():
    db = FakeDB(assets=[XOM, {**ARB, "missed_checks": 2}, TON])
    with _outcomes(
        XOM=svc.Outcome("XOM", "confirmed", yahoo_name="Exxon Mobil Corp"),
        **{"ARB-USD": svc.Outcome("ARB-USD", "missed"), "TON-USD": svc.Outcome("TON-USD", "review", note="Two candidates.")},
    ):
        assert run_asset_check(db) == {"confirmed": 1, "missed": 1, "review": 1}

    xom, arb, ton = (db.rows("assets", symbol=s)[0] for s in ("XOM", "ARB-USD", "TON-USD"))
    assert xom["yahoo_name"] == "Exxon Mobil Corp" and xom["checked_at"] and xom["status"] == "active"
    assert arb["status"] == "inactive" and arb["missed_checks"] == 3
    assert ton["status"] == "needs_review" and ton["review_note"] == "Two candidates."


def test_a_first_missed_check_keeps_the_asset():
    db = FakeDB(assets=[XOM])
    with _outcomes(XOM=svc.Outcome("XOM", "missed")):
        run_asset_check(db)
    assert db.rows("assets")[0]["status"] == "active" and db.rows("assets")[0]["missed_checks"] == 1


def test_a_rename_goes_through_the_database_function():
    db = FakeDB(assets=[ARB])
    outcome = svc.Outcome("ARB-USD", "renamed", yahoo_name="Arbitrum USD", new_symbol="ARB11841-USD", new_name="Arbitrum")
    with _outcomes(**{"ARB-USD": outcome}):
        run_asset_check(db)
    assert db.rpc_calls == [("rename_asset", {
        "p_old": "ARB-USD", "p_new": "ARB11841-USD", "p_name": "Arbitrum", "p_yahoo_name": "Arbitrum USD",
    })]


def test_a_failed_rename_waits_for_a_decision():
    class FailingRpc(FakeDB):
        def rpc(self, name, params):
            return SimpleNamespace(execute=lambda: (_ for _ in ()).throw(RuntimeError("asset is already in the catalog")))

    db = FailingRpc(assets=[ARB])
    outcome = svc.Outcome("ARB-USD", "renamed", yahoo_name="Arbitrum USD", new_symbol="ARB11841-USD", new_name="Arbitrum")
    with _outcomes(**{"ARB-USD": outcome}):
        run_asset_check(db)
    row = db.rows("assets")[0]
    assert row["status"] == "needs_review"
    assert row["review_note"] == "Moving to ARB11841-USD failed: asset is already in the catalog"


def test_only_active_assets_not_checked_recently_are_due():
    recent = (datetime.now(timezone.utc) - timedelta(hours=2)).isoformat()
    old = (datetime.now(timezone.utc) - timedelta(hours=30)).isoformat()
    db = FakeDB(assets=[
        catalog_row("A", "A Corp", "stock", "Software", checked_at=recent),
        catalog_row("B", "B Corp", "stock", "Software", checked_at=old),
        catalog_row("C", "C Corp", "stock", "Software"),
        catalog_row("D", "D Corp", "stock", "Software", status="needs_review"),
        catalog_row("E", "E Corp", "stock", "Software", status="inactive"),
    ])
    checked = []
    with patch.object(svc, "check_asset", side_effect=lambda a, c: checked.append(a["symbol"]) or svc.Outcome(a["symbol"], "skipped")):
        run_asset_check(db)
    assert sorted(checked) == ["B", "C"]


def test_a_yahoo_outage_counts_no_missed_checks():
    assets = [catalog_row(f"S{i}", f"S{i} Corp", "stock", "Software") for i in range(10)]
    db = FakeDB(assets=assets)
    outcomes = {a["symbol"]: svc.Outcome(a["symbol"], "missed" if i < 6 else "confirmed", yahoo_name="x") for i, a in enumerate(assets)}
    with _outcomes(**outcomes):
        assert run_asset_check(db) == {"outage": 10}
    assert all(r["missed_checks"] == 0 and r["checked_at"] is None for r in db.rows("assets"))


def test_a_skipped_asset_is_left_as_it_was():
    db = FakeDB(assets=[ARB])
    with _outcomes(**{"ARB-USD": svc.Outcome("ARB-USD", "skipped")}):
        run_asset_check(db)
    assert db.rows("assets")[0] == {**ARB}
