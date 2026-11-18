import base64
import os

import pytest
from cryptography.exceptions import InvalidTag

from app.crypto import Cipher
from app.triage import Severity, evaluate


def sev(hr=75.0, spo2=97.0, sys=120.0) -> Severity:
    return evaluate(hr, spo2, sys).severity


# Same boundaries as test/triage_test.dart in the app: the two must agree.
@pytest.mark.parametrize(
    ("kwargs", "expected"),
    [
        ({}, Severity.STABLE),
        ({"hr": 110}, Severity.STABLE),
        ({"hr": 111}, Severity.WARNING),
        ({"hr": 130}, Severity.WARNING),
        ({"hr": 131}, Severity.CRITICAL),
        ({"hr": 50}, Severity.STABLE),
        ({"hr": 49}, Severity.WARNING),
        ({"hr": 39}, Severity.CRITICAL),
        ({"spo2": 94}, Severity.STABLE),
        ({"spo2": 93.5}, Severity.WARNING),
        ({"spo2": 90}, Severity.WARNING),
        ({"spo2": 89.9}, Severity.CRITICAL),
        ({"sys": 160}, Severity.STABLE),
        ({"sys": 161}, Severity.WARNING),
        ({"sys": 181}, Severity.CRITICAL),
        ({"sys": 99}, Severity.WARNING),
        ({"sys": 89}, Severity.CRITICAL),
    ],
)
def test_triage_boundaries(kwargs, expected):
    assert sev(**kwargs) == expected


def test_worst_signal_wins_and_critical_reasons_come_first():
    result = evaluate(115, 88, 120)
    assert result.severity == Severity.CRITICAL
    assert result.alerts[0].startswith("Oxygen saturation critical")
    assert result.alerts[-1] == "Heart rate elevated (115 bpm)"


def test_alert_numbers_round_like_the_app():
    assert evaluate(130.5, 97, 120).alerts == ["Heart rate very high (131 bpm)"]


@pytest.fixture
def cipher() -> Cipher:
    return Cipher(base64.b64encode(os.urandom(32)).decode())


def test_round_trip(cipher):
    blob = cipher.encrypt({"heartRate": 142}, "patient-a")
    assert cipher.decrypt(blob, "patient-a") == {"heartRate": 142}


def test_ciphertext_reveals_nothing(cipher):
    blob = cipher.encrypt({"heartRate": 142}, "patient-a")
    assert b"heartRate" not in blob and b"142" not in blob


def test_same_value_encrypts_differently_each_time(cipher):
    assert cipher.encrypt({"a": 1}, "p") != cipher.encrypt({"a": 1}, "p")


def test_blob_moved_to_another_patient_does_not_decrypt(cipher):
    blob = cipher.encrypt({"heartRate": 142}, "patient-a")
    with pytest.raises(InvalidTag):
        cipher.decrypt(blob, "patient-b")


def test_tampering_is_detected(cipher):
    blob = bytearray(cipher.encrypt({"heartRate": 142}, "p"))
    blob[-1] ^= 0x01
    with pytest.raises(InvalidTag):
        cipher.decrypt(bytes(blob), "p")


@pytest.mark.parametrize("bad", ["not base64!", base64.b64encode(b"short").decode()])
def test_rejects_keys_that_are_not_256_bit(bad):
    with pytest.raises(ValueError):
        Cipher(bad)
