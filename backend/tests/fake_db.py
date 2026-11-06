"""An in-memory stand-in for the Supabase client that really filters rows.

The pipeline's promise that one user's data never reaches another is about which
rows a query touches, so these tests need the filters to work, not to be mocked.
"""

import uuid
from types import SimpleNamespace


#: What the database fills in when an insert leaves a column out.
_DEFAULTS = {
    "user_sources": {
        "fetch_interval_minutes": 15, "enabled": True, "needs_baseline": False, "baseline_urls": [],
        "last_fetched_at": None, "last_error": None,
    },
    "user_models": {"base_url": None, "stopped_reason": None},
}


class _Query:
    def __init__(self, db: "FakeDB", table: str) -> None:
        self._db = db
        self._table = table
        self._filters = []
        self._columns: list[str] | None = None
        self._action = "select"
        self._payload = None
        self._order: tuple[str, bool] | None = None
        self._on_conflict: list[str] = []

    def select(self, columns="*", **_):
        self._columns = None if columns == "*" else [c.strip() for c in columns.split(",")]
        return self

    def eq(self, column, value):
        self._filters.append(lambda r: r.get(column) == value)
        return self

    def in_(self, column, values):
        values = set(values)
        self._filters.append(lambda r: r.get(column) in values)
        return self

    def is_(self, column, value):
        assert value == "null"
        self._filters.append(lambda r: r.get(column) is None)
        return self

    def order(self, column, desc=False):
        self._order = (column, desc)
        return self

    def limit(self, _):
        return self

    def insert(self, rows):
        self._action, self._payload = "insert", rows if isinstance(rows, list) else [rows]
        return self

    def upsert(self, rows, on_conflict=""):
        self._action, self._payload = "upsert", rows if isinstance(rows, list) else [rows]
        self._on_conflict = on_conflict.split(",")
        return self

    def update(self, values):
        self._action, self._payload = "update", values
        return self

    def delete(self):
        self._action = "delete"
        return self

    def execute(self):
        rows = self._db.tables.setdefault(self._table, [])
        matches = [r for r in rows if all(f(r) for f in self._filters)]
        if self._action == "insert":
            data = [self._db.add(self._table, row) for row in self._payload]
        elif self._action == "upsert":
            data = []
            for row in self._payload:
                same = [r for r in rows if all(r.get(c) == row.get(c) for c in self._on_conflict)]
                if same:
                    same[0].update(row)
                    data.append(same[0])
                else:
                    data.append(self._db.add(self._table, row))
        elif self._action == "update":
            for row in matches:
                row.update(self._payload)
            data = matches
        elif self._action == "delete":
            self._db.tables[self._table] = [r for r in rows if r not in matches]
            data = matches
        else:
            data = matches
            if self._order:
                data = sorted(data, key=lambda r: r.get(self._order[0]) or "", reverse=self._order[1])
            if self._columns is not None:
                data = [{c: r.get(c) for c in self._columns} for r in data]
            else:
                data = [dict(r) for r in data]
        return SimpleNamespace(data=data, count=len(data))


class FakeDB:
    def __init__(self, **tables) -> None:
        self.tables = {name: [dict(row) for row in rows] for name, rows in tables.items()}
        self.rpc_calls: list[tuple[str, dict]] = []
        self.rpc_data: list[dict] = []

    def add(self, table: str, row: dict) -> dict:
        stored = {
            "id": str(uuid.uuid4()),
            "created_at": "2026-11-05T00:00:00+00:00",
            **_DEFAULTS.get(table, {}),
            **row,
        }
        self.tables.setdefault(table, []).append(stored)
        return stored

    def table(self, name: str) -> _Query:
        return _Query(self, name)

    def rpc(self, name: str, params: dict):
        self.rpc_calls.append((name, params))
        return SimpleNamespace(execute=lambda: SimpleNamespace(data=list(self.rpc_data)))

    def rows(self, table: str, **match) -> list[dict]:
        return [r for r in self.tables.get(table, []) if all(r.get(k) == v for k, v in match.items())]
