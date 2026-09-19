import pytest
from unittest.mock import MagicMock
from fastapi.testclient import TestClient

from app.main import app
from app.dependencies import get_current_user, get_db
from app.services.ai import AIProvider, ProviderRegistry, set_registry


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
    "ai_provider": "openai",
    "created_at": "2026-01-01T00:00:00",
}


class FakeProvider(AIProvider):
    """Provider whose responses are scripted, for pipeline tests."""

    def __init__(self, name="openai", responses=None, error=None, display_name=None, model="fake-model"):
        super().__init__(name, display_name or name.capitalize(), model)
        self.responses = list(responses or [])
        self.error = error
        self.calls = 0

    def complete(self, system_prompt, user_prompt):
        self.calls += 1
        if self.error is not None:
            raise self.error
        if not self.responses:
            raise RuntimeError("no scripted response left")
        response = self.responses.pop(0)
        if isinstance(response, Exception):
            raise response
        return response


@pytest.fixture
def registry():
    """Install a registry with three fake providers; restore afterwards."""
    providers = [FakeProvider("openai"), FakeProvider("gemini"), FakeProvider("grok")]
    reg = ProviderRegistry(providers, "openai")
    set_registry(reg)
    yield reg
    set_registry(None)


@pytest.fixture(autouse=True)
def _default_registry():
    """Tests that do not ask for a specific registry get a single OpenAI fake."""
    set_registry(ProviderRegistry([FakeProvider("openai")], "openai"))
    yield
    set_registry(None)


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
