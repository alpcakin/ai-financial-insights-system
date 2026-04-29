import pytest
from pydantic import ValidationError

from app.models.portfolio import AddAssetRequest, UpdateAssetRequest
from app.models.user import (
    ChangePasswordRequest,
    ForgotPasswordRequest,
    LoginRequest,
    RegisterRequest,
    UpdatePreferencesRequest,
)


def test_register_valid():
    r = RegisterRequest(email="user@example.com", password="Password1!")
    assert r.email == "user@example.com"


def test_register_invalid_email():
    with pytest.raises(ValidationError):
        RegisterRequest(email="not-an-email", password="Password1!")


def test_register_short_password():
    with pytest.raises(ValidationError):
        RegisterRequest(email="user@example.com", password="Pw1!")


def test_register_no_uppercase():
    with pytest.raises(ValidationError):
        RegisterRequest(email="user@example.com", password="password1!")


def test_register_no_lowercase():
    with pytest.raises(ValidationError):
        RegisterRequest(email="user@example.com", password="PASSWORD1!")


def test_register_no_digit():
    with pytest.raises(ValidationError):
        RegisterRequest(email="user@example.com", password="Password!")


def test_register_no_special_char():
    with pytest.raises(ValidationError):
        RegisterRequest(email="user@example.com", password="Password1")


def test_login_valid():
    r = LoginRequest(email="user@example.com", password="anything")
    assert r.email == "user@example.com"


def test_login_invalid_email():
    with pytest.raises(ValidationError):
        LoginRequest(email="not-an-email", password="anything")


def test_add_asset_valid():
    r = AddAssetRequest(asset_symbol="AAPL", asset_type="stock", quantity=10, purchase_price=150.0)
    assert r.asset_symbol == "AAPL"


def test_add_asset_invalid_type():
    with pytest.raises(ValidationError):
        AddAssetRequest(asset_symbol="AAPL", asset_type="futures", quantity=10, purchase_price=150.0)


def test_add_asset_zero_quantity():
    with pytest.raises(ValidationError):
        AddAssetRequest(asset_symbol="AAPL", asset_type="stock", quantity=0, purchase_price=150.0)


def test_add_asset_negative_price():
    with pytest.raises(ValidationError):
        AddAssetRequest(asset_symbol="AAPL", asset_type="stock", quantity=10, purchase_price=-1.0)


def test_update_asset_valid():
    r = UpdateAssetRequest(quantity=5, purchase_price=200.0)
    assert r.quantity == 5


def test_update_asset_zero_quantity():
    with pytest.raises(ValidationError):
        UpdateAssetRequest(quantity=0, purchase_price=200.0)


def test_change_password_valid():
    r = ChangePasswordRequest(current_password="anything", new_password="Password1!")
    assert r.new_password == "Password1!"


def test_change_password_weak_new():
    with pytest.raises(ValidationError):
        ChangePasswordRequest(current_password="anything", new_password="weak")


def test_update_preferences_all_none():
    r = UpdatePreferencesRequest()
    assert r.impact_alerts is None
    assert r.volatility_alerts is None


def test_update_preferences_with_values():
    r = UpdatePreferencesRequest(impact_alerts=False, volatility_alerts=True)
    assert r.impact_alerts is False
    assert r.volatility_alerts is True


def test_forgot_password_valid():
    r = ForgotPasswordRequest(email="user@example.com")
    assert r.email == "user@example.com"


def test_forgot_password_invalid_email():
    with pytest.raises(ValidationError):
        ForgotPasswordRequest(email="not-an-email")
