from types import SimpleNamespace
from unittest.mock import patch

import pytest
from fastapi import HTTPException
from pydantic import ValidationError

from app.models.asset import AddCatalogAssetRequest
from app.models.portfolio import AddAssetRequest
from app.services import asset_search_service as svc
from app.services.asset_catalog import analysis_pool
from app.services.asset_search_service import add_to_catalog, search_assets
from app.services.portfolio_service import add_asset
from tests.catalog import CATALOG, catalog_row
from tests.fake_db import FakeDB

ARBITRUM = catalog_row("ARB11841-USD", "Arbitrum", "crypto", "DeFi", previous_symbols=["ARB-USD"])
GONE = catalog_row("OLD", "Gone Corp", "stock", "Software", status="inactive")


def _q(symbol, quote_type, short, long=None, exchange="NYSE"):
    return {"symbol": symbol, "quoteType": quote_type, "shortname": short, "longname": long, "exchDisp": exchange}


def _info(quote_type, short, long=None, price=1.0):
    return {"quoteType": quote_type, "shortName": short, "longName": long, "regularMarketPrice": price}


class _Yahoo:
    """Scripted yfinance: search results per query and info per symbol."""

    def __init__(self, searches=None, infos=None):
        self.searches = searches or {}
        self.infos = infos or {}
        self.calls = []

    def Search(self, query, max_results):
        self.calls.append(("search", query))
        result = self.searches.get(query, [])
        if isinstance(result, Exception):
            raise result
        return SimpleNamespace(quotes=result)

    def Ticker(self, symbol):
        self.calls.append(("ticker", symbol))
        info = self.infos.get(symbol, {"trailingPegRatio": None})
        if isinstance(info, Exception):
            raise info
        return SimpleNamespace(info=info)


@pytest.fixture
def yahoo():
    fake = _Yahoo()
    with patch.object(svc, "yf", fake):
        yield fake


def _db(*extra):
    return FakeDB(assets=[*CATALOG, ARBITRUM, GONE, *extra])


# Search

def test_search_keeps_stocks_etfs_and_usd_crypto(yahoo):
    yahoo.searches["gold"] = [
        _q("GC=F", "FUTURE", "Gold Dec 26"),
        _q("GLD", "ETF", "SPDR Gold Shares", "SPDR Gold Shares", "NYSEArca"),
        _q("GOLD", "EQUITY", "Gold.com, Inc.", "Gold.com, Inc."),
        _q("PAXG-USD", "CRYPTOCURRENCY", "PAX Gold USD", "PAX Gold USD", "CCC"),
        _q("PAXG-EUR", "CRYPTOCURRENCY", "PAX Gold EUR", "PAX Gold EUR", "CCC"),
        _q("CH1.SG", "MUTUALFUND", "Gold Fund"),
        _q("GLD", "ETF", "SPDR Gold Shares", "SPDR Gold Shares", "NYSEArca"),
    ]
    results = search_assets(_db(), "u1","gold")
    assert [(r["symbol"], r["type"], r["name"]) for r in results] == [
        ("GLD", "etf", "SPDR Gold Shares"),
        ("GOLD", "stock", "Gold.com, Inc."),
        ("PAXG-USD", "crypto", "PAX Gold"),
    ]
    assert all(r["catalog_asset"] is None and r["blocked"] is None for r in results)
    assert results[0]["exchange"] == "NYSEArca"


def test_search_prefers_the_long_name_and_cleans_padding(yahoo):
    yahoo.searches["thy"] = [_q("TU5A.F", "EQUITY", "Turk Hava Yollari A.S.        R", None, "Frankfurt"),
                             _q("SPY", "ETF", "State Street SPDR S&P 500 ETF T", "State Street SPDR S&P 500 ETF Trust")]
    assert [r["name"] for r in search_assets(_db(), "u1","thy")] == [
        "Turk Hava Yollari A.S. R", "State Street SPDR S&P 500 ETF Trust",
    ]


def test_search_marks_assets_already_in_the_catalog(yahoo):
    yahoo.searches["apple"] = [
        _q("AAPL", "EQUITY", "Apple Inc.", "Apple Inc.", "NASDAQ"),
        _q("APC.DE", "EQUITY", "Apple Inc.                    R", "Apple Inc.", "XETRA"),
        _q("APLE", "EQUITY", "Apple Hospitality REIT, Inc.", "Apple Hospitality REIT, Inc."),
    ]
    by_symbol = {r["symbol"]: r for r in search_assets(_db(), "u1","apple")}
    aapl = {"symbol": "AAPL", "name": "Apple Inc.", "type": "stock", "category": "Consumer Electronics"}
    assert by_symbol["AAPL"]["catalog_asset"] == aapl
    assert by_symbol["APC.DE"]["catalog_asset"] == aapl
    assert by_symbol["APLE"]["catalog_asset"] is None


def test_search_matches_the_confirmed_yahoo_name_too(yahoo):
    renamed = catalog_row("XYZ", "Old Name Corp", "stock", "Software", yahoo_name="New Name Holdings")
    yahoo.searches["new name"] = [_q("XYZ.DE", "EQUITY", "New Name Holdings")]
    [result] = search_assets(_db(renamed), "u1","new name")
    assert result["catalog_asset"]["symbol"] == "XYZ"


def test_search_does_not_match_another_type_or_a_longer_name(yahoo):
    yahoo.searches["bitcoin"] = [
        _q("WBTC-USD", "CRYPTOCURRENCY", "Wrapped Bitcoin USD", "Wrapped Bitcoin USD", "CCC"),
        _q("BITCOIN", "ETF", "Bitcoin", "Bitcoin"),
    ]
    assert [r["catalog_asset"] for r in search_assets(_db(), "u1","bitcoin")] == [None, None]


def test_search_blocks_a_previous_symbol_and_an_inactive_one(yahoo):
    yahoo.searches["arb"] = [
        _q("ARB-USD", "CRYPTOCURRENCY", "ARbit USD", "ARbit USD", "CCC"),
        _q("ARB11841-USD", "CRYPTOCURRENCY", "Arbitrum USD", "Arbitrum USD", "CCC"),
        _q("OLD", "EQUITY", "Gone Corp"),
    ]
    arbit, arbitrum, old = search_assets(_db(), "u1","arb")
    assert arbit["blocked"] == "ARB-USD was the symbol of Arbitrum, which is now ARB11841-USD."
    assert arbit["catalog_asset"] is None
    assert (arbitrum["blocked"], arbitrum["catalog_asset"]["symbol"]) == (None, "ARB11841-USD")
    assert old["blocked"] == "OLD is no longer tracked."


def test_blank_query_does_not_call_yahoo(yahoo):
    assert search_assets(_db(), "u1","   ") == []
    assert yahoo.calls == []


def test_searches_are_limited_per_user(yahoo):
    db = _db()
    for _ in range(30):
        search_assets(db, "u1", "x")
    search_assets(db, "u1", " ")
    with pytest.raises(HTTPException) as exc:
        search_assets(db, "u1", "x")
    assert exc.value.status_code == 429
    assert int(exc.value.headers["Retry-After"]) > 0
    assert len(yahoo.calls) == 30
    search_assets(db, "u2", "x")
    assert len(yahoo.calls) == 31


def test_search_reports_yahoo_failure(yahoo):
    yahoo.searches["x"] = ConnectionError("down")
    with pytest.raises(HTTPException) as exc:
        search_assets(_db(), "u1","x")
    assert exc.value.status_code == 502


# Adding

def test_adds_a_stock_without_a_category(yahoo):
    yahoo.infos["THYAO.IS"] = _info("EQUITY", "TURK HAVA YOLLARI", "Türk Hava Yollari Anonim Ortakligi")
    db = _db()
    assert add_to_catalog(db, "u1", "THYAO.IS") == {
        "symbol": "THYAO.IS", "name": "Türk Hava Yollari Anonim Ortakligi", "type": "stock", "category": None,
    }
    [row] = db.rows("assets", symbol="THYAO.IS")
    assert (row["status"], row["yahoo_name"], row["added_by"], row["missed_checks"]) == (
        "active", "TURK HAVA YOLLARI", "u1", 0,
    )
    assert row["checked_at"] is not None
    assert analysis_pool(db)["THYAO.IS"] == "Türk Hava Yollari Anonim Ortakligi"


def test_adds_a_crypto_without_the_currency_in_its_name(yahoo):
    yahoo.infos["PAXG-USD"] = _info("CRYPTOCURRENCY", "PAX Gold USD", "PAX Gold USD")
    assert add_to_catalog(_db(), "u1", "PAXG-USD")["name"] == "PAX Gold"


def test_a_symbol_in_the_catalog_is_returned_without_asking_yahoo(yahoo):
    db = _db()
    assert add_to_catalog(db, "u1", "AAPL")["category"] == "Consumer Electronics"
    assert add_to_catalog(db, "u1", "ARB11841-USD")["name"] == "Arbitrum"
    assert yahoo.calls == []


@pytest.mark.parametrize("symbol, message", [
    ("ARB-USD", "ARB-USD was the symbol of Arbitrum, which is now ARB11841-USD."),
    ("OLD", "OLD is no longer tracked."),
])
def test_previous_and_inactive_symbols_are_refused(yahoo, symbol, message):
    with pytest.raises(HTTPException) as exc:
        add_to_catalog(_db(), "u1", symbol)
    assert (exc.value.status_code, exc.value.detail) == (409, message)
    assert yahoo.calls == []


def test_another_listing_of_a_catalog_asset_is_refused(yahoo):
    yahoo.infos["APC.DE"] = _info("EQUITY", "Apple Inc.                    R", "Apple Inc.")
    db = _db()
    with pytest.raises(HTTPException) as exc:
        add_to_catalog(db, "u1", "APC.DE")
    assert exc.value.status_code == 409
    assert "as AAPL" in exc.value.detail
    assert db.rows("assets", symbol="APC.DE") == []


@pytest.mark.parametrize("symbol, info, message", [
    ("ZZZZQQ", {"trailingPegRatio": None}, "Yahoo has no data for ZZZZQQ"),
    ("ES=F", _info("FUTURE", "E-Mini S&P 500 Dec 26"), "Only stocks, ETFs and crypto in USD can be added"),
    ("BTC-EUR", _info("CRYPTOCURRENCY", "Bitcoin EUR", "Bitcoin EUR"), "Only stocks, ETFs and crypto in USD can be added"),
    ("^GSPC", _info("INDEX", "S&P 500"), "Only stocks, ETFs and crypto in USD can be added"),
    ("NOPRICE", _info("EQUITY", "No Price Inc.", price=None), "Yahoo has no price for NOPRICE"),
])
def test_listings_yahoo_cannot_back_are_refused(yahoo, symbol, info, message):
    yahoo.infos[symbol] = info
    db = _db()
    with pytest.raises(HTTPException) as exc:
        add_to_catalog(db, "u1", symbol)
    assert (exc.value.status_code, exc.value.detail) == (400, message)
    assert db.rows("assets", symbol=symbol) == []


def test_adding_reports_yahoo_failure(yahoo):
    yahoo.infos["NEW"] = ConnectionError("down")
    with pytest.raises(HTTPException) as exc:
        add_to_catalog(_db(), "u1", "NEW")
    assert exc.value.status_code == 502


def test_a_symbol_added_a_moment_earlier_is_kept(yahoo):
    yahoo.infos["NEW"] = _info("EQUITY", "New Co", "New Co")
    db = _db(catalog_row("NEW", "New Co (first)", "stock", None, added_by="u0"))
    with patch.object(svc, "load_catalog", return_value=CATALOG):
        assert add_to_catalog(db, "u1", "NEW")["name"] == "New Co (first)"
    [row] = db.rows("assets", symbol="NEW")
    assert row["added_by"] == "u0"


def test_an_added_asset_can_be_held_without_a_category(yahoo):
    yahoo.infos["THYAO.IS"] = _info("EQUITY", "TURK HAVA YOLLARI", "Türk Hava Yollari Anonim Ortakligi")
    db = _db()
    add_to_catalog(db, "u1", "THYAO.IS")
    with patch("app.services.portfolio_service._get_current_price", return_value=None):
        add_asset(db, "u1", AddAssetRequest(asset_symbol="thyao.is", quantity=1, purchase_price=1.0))
    [row] = db.rows("portfolio")
    assert (row["asset_symbol"], row["asset_type"], row["category"]) == ("THYAO.IS", "stock", None)
    assert db.rows("followed_topics") == []


@pytest.mark.parametrize("raw, symbol", [(" thyao.is ", "THYAO.IS"), ("brk-b", "BRK-B"), ("ARB11841-USD", "ARB11841-USD")])
def test_request_takes_yahoo_symbols(raw, symbol):
    assert AddCatalogAssetRequest(symbol=raw).symbol == symbol


@pytest.mark.parametrize("raw", ["", "AAPL/../X", "A B", "ABCDEFGHIJKLMNOPQRSTU"])
def test_request_rejects_anything_else(raw):
    with pytest.raises(ValidationError):
        AddCatalogAssetRequest(symbol=raw)


# Endpoints

@pytest.fixture
def mock_db():
    return _db()


def test_search_endpoint(client, yahoo):
    yahoo.searches["apple"] = [_q("AAPL", "EQUITY", "Apple Inc.", "Apple Inc.", "NASDAQ")]
    r = client.get("/assets/search", params={"q": "apple"})
    assert r.status_code == 200
    assert r.json()["results"][0]["catalog_asset"]["symbol"] == "AAPL"
    assert client.get("/assets/search").status_code == 422
    assert client.get("/assets/search", params={"q": "x" * 51}).status_code == 422
    for _ in range(29):
        client.get("/assets/search", params={"q": "apple"})
    r = client.get("/assets/search", params={"q": "apple"})
    assert r.status_code == 429
    assert "Retry-After" in r.headers


def test_add_endpoint(client, yahoo, mock_db):
    yahoo.infos["THYAO.IS"] = _info("EQUITY", "TURK HAVA YOLLARI", "Türk Hava Yollari Anonim Ortakligi")
    r = client.post("/assets", json={"symbol": "thyao.is"})
    assert r.status_code == 200
    assert r.json()["category"] is None
    assert mock_db.rows("assets", symbol="THYAO.IS")[0]["added_by"] == "user-123"
    assert client.post("/assets", json={"symbol": "ARB-USD"}).status_code == 409
    assert client.post("/assets", json={"symbol": "a/b"}).status_code == 422


def test_search_and_add_require_auth(auth_client):
    assert auth_client.get("/assets/search", params={"q": "apple"}).status_code in (401, 403)
    assert auth_client.post("/assets", json={"symbol": "AAPL"}).status_code in (401, 403)
