import json
import pytest
from unittest.mock import MagicMock, patch

from app.services.ai_service import _validate_response, analyze_article

ASSET_POOL = ["AAPL", "MSFT"]
CATEGORY_LIST = ["Technology", "Software"]

VALID_RESPONSE = {
    "summary": "Test summary",
    "sentiment": "positive",
    "severity": 7,
    "related_assets": ["AAPL"],
    "related_categories": ["Technology"],
    "impacted_assets": [
        {"symbol": "AAPL", "impact": "positive", "severity": 7, "reason": "Good news"}
    ],
}


def _mock_openai(content):
    mock_client = MagicMock()
    mock_client.chat.completions.create.return_value.choices = [
        MagicMock(message=MagicMock(content=content))
    ]
    return mock_client


@patch("app.services.ai_service._get_client")
def test_analyze_success(mock_get_client):
    mock_get_client.return_value = _mock_openai(json.dumps(VALID_RESPONSE))
    result = analyze_article("Title", "Description", ASSET_POOL, CATEGORY_LIST)
    assert result is not None
    assert result["sentiment"] == "positive"
    assert result["severity"] == 7


@patch("app.services.ai_service._get_client")
def test_analyze_json_error_retries_3(mock_get_client):
    mock_client = MagicMock()
    mock_client.chat.completions.create.return_value.choices = [
        MagicMock(message=MagicMock(content="not valid json"))
    ]
    mock_get_client.return_value = mock_client
    result = analyze_article("Title", "Description", ASSET_POOL, CATEGORY_LIST)
    assert result is None
    assert mock_client.chat.completions.create.call_count == 3


@patch("app.services.ai_service._get_client")
def test_analyze_unexpected_exception(mock_get_client):
    mock_client = MagicMock()
    mock_client.chat.completions.create.side_effect = RuntimeError("unexpected")
    mock_get_client.return_value = mock_client
    result = analyze_article("Title", "Description", ASSET_POOL, CATEGORY_LIST)
    assert result is None
    assert mock_client.chat.completions.create.call_count == 1


def test_validate_clamps_severity_low():
    data = {**VALID_RESPONSE, "severity": 0, "impacted_assets": []}
    _validate_response(data, ASSET_POOL, CATEGORY_LIST)
    assert data["severity"] == 1


def test_validate_clamps_severity_high():
    data = {**VALID_RESPONSE, "severity": 11, "impacted_assets": []}
    _validate_response(data, ASSET_POOL, CATEGORY_LIST)
    assert data["severity"] == 10


def test_validate_invalid_sentiment():
    data = {**VALID_RESPONSE, "sentiment": "bullish", "impacted_assets": []}
    _validate_response(data, ASSET_POOL, CATEGORY_LIST)
    assert data["sentiment"] == "neutral"


def test_validate_drops_unknown_asset():
    data = {
        **VALID_RESPONSE,
        "impacted_assets": [
            {"symbol": "UNKNOWN", "impact": "positive", "severity": 5, "reason": "x"}
        ],
    }
    _validate_response(data, ASSET_POOL, CATEGORY_LIST)
    assert data["impacted_assets"] == []


def test_validate_normalizes_asset_impact():
    data = {
        **VALID_RESPONSE,
        "impacted_assets": [
            {"symbol": "AAPL", "impact": "bullish", "severity": 5, "reason": "x"}
        ],
    }
    _validate_response(data, ASSET_POOL, CATEGORY_LIST)
    assert data["impacted_assets"][0]["impact"] == "neutral"


def test_validate_clamps_asset_severity():
    data = {
        **VALID_RESPONSE,
        "impacted_assets": [
            {"symbol": "AAPL", "impact": "positive", "severity": 15, "reason": "x"}
        ],
    }
    _validate_response(data, ASSET_POOL, CATEGORY_LIST)
    assert data["impacted_assets"][0]["severity"] == 10


def test_validate_filters_categories():
    data = {**VALID_RESPONSE, "related_categories": ["Technology", "Healthcare"], "impacted_assets": []}
    _validate_response(data, ASSET_POOL, CATEGORY_LIST)
    assert "Technology" in data["related_categories"]
