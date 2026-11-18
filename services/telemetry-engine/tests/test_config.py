from app.config import Settings


def test_database_password_is_kept_out_of_the_url_and_encoded():
    s = Settings(
        encryption_key="k",
        database_url="postgresql+asyncpg://medvitals@postgres:5432/telemetry",
        database_password="p@ss/w:rd",
        _env_file=None,
    )
    assert s.database_dsn == "postgresql+asyncpg://medvitals:p%40ss%2Fw%3Ard@postgres:5432/telemetry"


def test_device_keys_accept_a_plain_key_a_list_or_json():
    def keys(value):
        return Settings(encryption_key="k", device_api_keys=value, _env_file=None).device_api_keys

    assert keys("one-key") == ["one-key"]
    assert keys("a, b") == ["a", "b"]
    assert keys('["a", "b"]') == ["a", "b"]
