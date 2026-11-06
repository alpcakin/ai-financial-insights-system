import json
from datetime import datetime, timezone
from unittest.mock import patch

import pytest
from fastapi import HTTPException

from app.core import key_vault
from app.core.config import settings
from app.models.manual import AddModelRequest, AddSourceRequest, UpdateManualSettingsRequest, UpdateSourceRequest
from app.services import manual_service
from app.services.news_service import read_feed_title
from tests.conftest import FakeProvider
from tests.fake_db import FakeDB

KEY = "sk-my-secret-key-9876"
USER = {"id": "u1", "manual_enabled": False}
GOOD_ANSWER = json.dumps({"level": "high", "summary": "S", "sentiment": "positive", "categories": [], "impacted_assets": []})


def _rss(*items):
    now = datetime.now(timezone.utc).strftime("%a, %d %b %Y %H:%M:%S GMT")
    entries = "".join(
        f"<item><title>{i}</title><link>https://x.test/{i}</link><pubDate>{now}</pubDate></item>" for i in items
    )
    return f'<rss version="2.0"><channel><title>My Feed</title>{entries}</channel></rss>'.encode()


@pytest.fixture
def db():
    return FakeDB(users=[{"id": "u1"}, {"id": "u2"}], user_sources=[], user_models=[])


def _add_source(db, url="https://x.test/rss", user=USER, **kwargs):
    with patch("app.services.manual_service.fetch_feed", return_value=_rss("a", "b")):
        return manual_service.add_source(db, user, AddSourceRequest(url=url, **kwargs))


def _status(call) -> int:
    with pytest.raises(HTTPException) as err:
        call()
    return err.value.status_code


# ── Sources ──────────────────────────────────────────────────────────────────

def test_adding_a_source_counts_what_the_feed_holds_as_seen(db):
    _add_source(db)
    row = db.rows("user_sources")[0]
    assert row["baseline_urls"] == ["https://x.test/a", "https://x.test/b"]
    assert row["needs_baseline"] is False
    assert row["last_fetched_at"]


def test_a_source_is_named_after_its_feed_unless_named(db):
    assert _add_source(db)["name"] == "My Feed"
    assert _add_source(db, url="https://x.test/other", name="Mine")["name"] == "Mine"


def test_the_response_does_not_carry_the_baseline(db):
    assert "baseline_urls" not in _add_source(db)


@pytest.mark.parametrize("url", ["file:///etc/passwd", "ftp://x.test/a", "http://user:pw@x.test/a", "http://"])
def test_a_bad_address_is_refused_before_any_fetch(db, url):
    with patch("app.services.manual_service.fetch_feed") as fetched:
        assert _status(lambda: manual_service.add_source(db, USER, AddSourceRequest(url=url))) == 400
    fetched.assert_not_called()
    assert db.rows("user_sources") == []


def test_every_failure_to_read_gives_the_same_message(db):
    messages = set()
    for effect in (OSError("10.0.0.1 refused"), ValueError("private"), None):
        kwargs = {"side_effect": effect} if effect else {"return_value": b"<html></html>"}
        with patch("app.services.manual_service.fetch_feed", **kwargs):
            with pytest.raises(HTTPException) as err:
                manual_service.add_source(db, USER, AddSourceRequest(url="https://x.test/rss"))
        messages.add(err.value.detail)
    assert messages == {manual_service._FEED_ERROR}


def test_a_page_that_is_not_a_feed_is_refused():
    with pytest.raises(Exception):
        read_feed_title(b"<html><body>hi</body></html>")
    with pytest.raises(Exception):
        read_feed_title(b"not xml")
    assert read_feed_title(_rss("a")) == "My Feed"


def test_a_feed_with_entity_tricks_is_refused():
    bomb = b'<?xml version="1.0"?><!DOCTYPE r [<!ENTITY a "aaaa">]><rss><channel><title>&a;</title></channel></rss>'
    with pytest.raises(Exception):
        read_feed_title(bomb)


def test_twenty_sources_is_the_limit(db):
    for n in range(manual_service.MAX_SOURCES):
        db.add("user_sources", {"user_id": "u1", "url": f"https://x.test/{n}"})
    assert _status(lambda: _add_source(db)) == 400


def test_other_users_sources_do_not_count_towards_the_limit(db):
    for n in range(manual_service.MAX_SOURCES):
        db.add("user_sources", {"user_id": "u2", "url": f"https://x.test/{n}"})
    assert _add_source(db)["url"] == "https://x.test/rss"


def test_the_same_source_cannot_be_added_twice(db):
    _add_source(db)
    assert _status(lambda: _add_source(db)) == 409


def test_two_users_can_follow_the_same_address(db):
    _add_source(db)
    _add_source(db, user={"id": "u2"})
    assert len(db.rows("user_sources", url="https://x.test/rss")) == 2


def test_source_additions_are_rate_limited(db):
    for n in range(20):
        db.tables["user_sources"].clear()
        _add_source(db, url=f"https://x.test/{n}")
    assert _status(lambda: _add_source(db, url="https://x.test/late")) == 429


def test_switching_a_source_back_on_counts_its_content_as_seen(db):
    source = _add_source(db)
    manual_service.update_source(db, USER, source["id"], UpdateSourceRequest(enabled=False))
    assert not db.rows("user_sources")[0].get("needs_baseline")
    updated = manual_service.update_source(db, USER, source["id"], UpdateSourceRequest(enabled=True))
    assert db.rows("user_sources")[0]["needs_baseline"] is True
    assert "needs_baseline" not in updated and updated["enabled"] is True


def test_someone_elses_source_cannot_be_changed_or_deleted(db):
    source = _add_source(db, user={"id": "u2"})
    assert _status(lambda: manual_service.update_source(db, USER, source["id"], UpdateSourceRequest(enabled=False))) == 404
    assert _status(lambda: manual_service.delete_source(db, USER, source["id"])) == 404
    assert db.rows("user_sources", id=source["id"])[0]["enabled"] is not False


# ── Models ───────────────────────────────────────────────────────────────────

def _request(**overrides):
    return AddModelRequest(**{"kind": "openai", "model": "gpt-x", "api_key": KEY, **overrides})


def _add_model(db, user=USER, answer=GOOD_ANSWER, error=None, **overrides):
    provider = FakeProvider("test", responses=[answer] * 3, error=error)
    with patch("app.services.manual_service.build_provider", return_value=provider) as build:
        result = manual_service.add_model(db, user, _request(**overrides))
    assert build.call_args.args[4] == KEY
    return result


def test_a_stored_key_is_encrypted_and_never_returned(db):
    result = _add_model(db)
    row = db.rows("user_models")[0]
    assert KEY not in json.dumps(row)
    assert key_vault.decrypt_key(row["encrypted_key"]) == KEY
    assert result["key_last4"] == "9876"
    assert "encrypted_key" not in result and KEY not in json.dumps(result)


def test_listing_models_does_not_return_the_stored_key(db):
    _add_model(db)
    listed = manual_service.list_models(db, "u1")
    assert "encrypted_key" not in listed[0] and listed[0]["key_last4"] == "9876"


def test_the_first_model_becomes_the_chosen_one(db):
    result = _add_model(db)
    assert db.rows("users", id="u1")[0]["manual_model_id"] == result["id"]


def test_a_later_model_does_not_replace_the_chosen_one(db):
    first = _add_model(db)
    with patch("app.services.manual_service.build_provider", return_value=FakeProvider("test", responses=[GOOD_ANSWER])):
        manual_service.add_model(db, {**USER, "manual_model_id": first["id"]}, _request(model="other"))
    assert db.rows("users", id="u1")[0]["manual_model_id"] == first["id"]


def test_a_model_that_fails_the_test_is_not_stored(db):
    for answer, error in ((None, type("E", (Exception,), {"status_code": 401})("x")), ("not json", None)):
        with pytest.raises(HTTPException) as err:
            _add_model(db, answer=answer, error=error)
        assert err.value.status_code == 400
    assert db.rows("user_models") == []


def test_the_error_message_never_repeats_what_the_vendor_said(db):
    error = type("E", (Exception,), {"status_code": 401})(f"bad key {KEY} at internal host")
    with pytest.raises(HTTPException) as err:
        _add_model(db, answer=None, error=error)
    assert err.value.detail == manual_service._MODEL_ERRORS["auth"]


def test_the_test_goes_through_the_shared_validation(db):
    with pytest.raises(HTTPException):
        _add_model(db, answer=json.dumps({"level": "impossible"}))


def test_the_same_model_cannot_be_added_twice(db):
    _add_model(db)
    assert _status(lambda: _add_model(db)) == 409


def test_a_custom_address_must_be_public_https(db):
    assert _status(lambda: _add_model(db, kind="compatible", base_url="http://x.test/v1")) == 400
    result = _add_model(db, kind="compatible", base_url="https://x.test/v1")
    assert result["base_url"] == "https://x.test/v1"


def test_a_custom_address_is_required_only_for_that_kind(db):
    assert _status(lambda: _add_model(db, kind="compatible")) == 400
    assert _add_model(db, base_url="https://ignored.test")["base_url"] is None


def test_models_cannot_be_added_without_a_master_key(db):
    with patch.object(settings, "user_key_encryption_key", ""):
        assert _status(lambda: _add_model(db)) == 503


def test_model_tests_are_rate_limited(db):
    for n in range(10):
        _add_model(db, model=f"m{n}")
    assert _status(lambda: _add_model(db, model="late")) == 429


def test_the_first_working_model_after_none_counts_feed_content_as_seen(db):
    source = _add_source(db)
    _add_model(db)
    assert db.rows("user_sources", id=source["id"])[0]["needs_baseline"] is True


def test_someone_elses_model_cannot_be_used_or_touched(db):
    theirs = _add_model(db, user={"id": "u2"})
    assert _status(lambda: manual_service.delete_model(db, USER, theirs["id"])) == 404
    assert _status(lambda: manual_service.retry_model(db, USER, theirs["id"])) == 404
    request = UpdateManualSettingsRequest(selected_model_id="00000000-0000-0000-0000-000000000001")
    db.rows("user_models", id=theirs["id"])[0]["id"] = "00000000-0000-0000-0000-000000000001"
    assert _status(lambda: manual_service.update_settings(db, USER, request)) == 404


def test_deleting_the_chosen_model_moves_to_a_working_one(db):
    first = _add_model(db)
    with patch("app.services.manual_service.build_provider", return_value=FakeProvider("test", responses=[GOOD_ANSWER])):
        second = manual_service.add_model(db, {**USER, "manual_model_id": first["id"]}, _request(model="b"))
    manual_service.delete_model(db, {**USER, "manual_model_id": first["id"]}, first["id"])
    assert db.rows("users", id="u1")[0]["manual_model_id"] == second["id"]


def test_deleting_the_last_model_leaves_none_chosen(db):
    only = _add_model(db)
    manual_service.delete_model(db, {**USER, "manual_model_id": only["id"]}, only["id"])
    assert db.rows("users", id="u1")[0]["manual_model_id"] is None


def test_retrying_a_stopped_model_puts_it_back_when_the_test_passes(db):
    model = _add_model(db)
    db.rows("user_models")[0]["stopped_reason"] = "auth"
    source = _add_source(db)
    with patch("app.services.manual_service.build_provider", return_value=FakeProvider("test", responses=[GOOD_ANSWER])) as build:
        result = manual_service.retry_model(db, USER, model["id"])
    assert build.call_args.args[4] == KEY
    assert result["stopped_reason"] is None and "encrypted_key" not in result
    assert db.rows("user_models")[0]["stopped_reason"] is None
    assert db.rows("user_sources", id=source["id"])[0]["needs_baseline"] is True


def test_retrying_keeps_a_model_stopped_when_the_test_fails(db):
    model = _add_model(db)
    db.rows("user_models")[0]["stopped_reason"] = "quota"
    error = type("E", (Exception,), {"status_code": 402})("x")
    with patch("app.services.manual_service.build_provider", return_value=FakeProvider("test", error=error)):
        assert _status(lambda: manual_service.retry_model(db, USER, model["id"])) == 400
    assert db.rows("user_models")[0]["stopped_reason"] == "quota"


# ── Settings ─────────────────────────────────────────────────────────────────

def test_defaults_are_package_on_manual_off_grouping_off():
    assert manual_service.get_settings({"id": "u1"}) == {
        "package_enabled": True,
        "manual_enabled": False,
        "grouping_enabled": False,
        "selected_model_id": None,
        "can_store_keys": True,
    }


def test_switching_manual_mode_on_counts_feed_content_as_seen(db):
    source = _add_source(db)
    result = manual_service.update_settings(db, USER, UpdateManualSettingsRequest(manual_enabled=True))
    assert result["manual_enabled"] is True
    assert db.rows("user_sources", id=source["id"])[0]["needs_baseline"] is True


def test_changing_other_settings_does_not_touch_the_baseline(db):
    source = _add_source(db)
    user = {**USER, "manual_enabled": True}
    manual_service.update_settings(db, user, UpdateManualSettingsRequest(grouping_enabled=True, package_enabled=False))
    row = db.rows("users", id="u1")[0]
    assert row["manual_grouping"] is True and row["package_enabled"] is False
    assert not db.rows("user_sources", id=source["id"])[0].get("needs_baseline")


def test_another_users_baseline_is_left_alone(db):
    theirs = _add_source(db, user={"id": "u2"})
    manual_service.update_settings(db, USER, UpdateManualSettingsRequest(manual_enabled=True))
    assert not db.rows("user_sources", id=theirs["id"])[0].get("needs_baseline")
