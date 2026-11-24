from unittest.mock import patch

from app.services import notification_service


def test_push_carries_its_data(monkeypatch):
    monkeypatch.setattr(notification_service, "_init_firebase", lambda: None)
    monkeypatch.setattr(notification_service, "_firebase_available", True)
    with patch("firebase_admin.messaging.send") as send:
        assert notification_service.send_push("tok", "Title", "Body", {"article_id": "a1"})
    message = send.call_args.args[0]
    assert message.token == "tok"
    assert message.data == {"article_id": "a1"}
