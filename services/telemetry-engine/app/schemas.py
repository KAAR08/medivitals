"""Request and response models (camelCase, as the app sends them).

Unknown fields and physiologically impossible values are rejected with 422
before anything is triaged or stored.
"""

import uuid
from datetime import UTC, datetime, timedelta
from enum import StrEnum

from pydantic import AwareDatetime, BaseModel, ConfigDict, Field, model_validator


class _In(BaseModel):
    model_config = ConfigDict(populate_by_name=True, extra="forbid", str_strip_whitespace=True)


class TelemetryIn(_In):
    """One reading from a wearable (here: the biometric simulator)."""

    patient_id: uuid.UUID = Field(alias="patientId")
    heart_rate: float = Field(alias="heartRate", ge=20, le=250)
    spo2: float = Field(ge=50, le=100)
    systolic_bp: float = Field(alias="systolicBP", ge=40, le=300)
    diastolic_bp: float = Field(alias="diastolicBP", ge=20, le=200)
    timestamp: AwareDatetime

    @model_validator(mode="after")
    def _plausible(self) -> "TelemetryIn":
        if self.diastolic_bp >= self.systolic_bp:
            raise ValueError("diastolicBP must be lower than systolicBP")
        if self.timestamp > datetime.now(UTC) + timedelta(minutes=1):
            raise ValueError("timestamp is in the future")
        return self


class EscalationSource(StrEnum):
    PATIENT = "patient"
    CAREGIVER = "caregiver"
    AUTO = "auto"


class EscalationStatus(StrEnum):
    PENDING = "pending"  # waiting for the triage nurse
    ACKNOWLEDGED = "acknowledged"  # a nurse (or doctor) has taken it and is calling
    REFERRED = "referred"  # handed to a doctor / specialist
    AMBULANCE = "ambulance"  # ambulance dispatched (simulated: nothing real is sent)
    RESOLVED = "resolved"


class EscalationCreate(_In):
    patient_id: uuid.UUID = Field(alias="patientId")
    # Clients can't claim "auto": only the engine raises automatic escalations.
    source: EscalationSource = EscalationSource.PATIENT
    note: str | None = Field(default=None, max_length=500)

    @model_validator(mode="after")
    def _not_auto(self) -> "EscalationCreate":
        if self.source == EscalationSource.AUTO:
            raise ValueError("source 'auto' is reserved for the engine")
        return self


class EscalationUpdate(_In):
    status: EscalationStatus
    # What the clinician decided and why, e.g. after a call. Stored encrypted.
    note: str | None = Field(default=None, max_length=500)

    @model_validator(mode="after")
    def _not_pending(self) -> "EscalationUpdate":
        if self.status == EscalationStatus.PENDING:
            raise ValueError("status can only move forward")
        return self


def iso(value: datetime | None) -> str | None:
    if value is None:
        return None
    return value.astimezone(UTC).isoformat().replace("+00:00", "Z")
