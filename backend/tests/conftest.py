import pytest
from unittest.mock import MagicMock
from fastapi.testclient import TestClient

from app.main import app
from app.dependencies import get_current_user, get_db


def chain_mock(data, count=None):
    result = MagicMock()
    result.data = data
    result.count = count if count is not None else len(data)
    m = MagicMock()
    m.execute.return_value = result
    for method in [
        "select", "eq", "in_", "order", "range", "upsert",
        "insert", "update", "delete", "not_", "gte", "lte", "neq",
    ]:
        getattr(m, method).return_value = m
    return m


def make_db(tables: dict):
    db = MagicMock()
    db.table.side_effect = lambda name: chain_mock(tables.get(name, []))
    return db


FAKE_USER = {
    "id": "user-123",
    "email": "test@example.com",
    "notification_preferences": {},
    "created_at": "2026-01-01T00:00:00",
}


@pytest.fixture
def mock_db():
    return make_db({})


@pytest.fixture
def client(mock_db):
    app.dependency_overrides[get_db] = lambda: mock_db
    app.dependency_overrides[get_current_user] = lambda: FAKE_USER
    yield TestClient(app)
    app.dependency_overrides.clear()


@pytest.fixture
def auth_client(mock_db):
    app.dependency_overrides[get_db] = lambda: mock_db
    yield TestClient(app)
    app.dependency_overrides.clear()
