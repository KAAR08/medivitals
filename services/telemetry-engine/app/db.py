"""PostgreSQL storage (SQLite in development and tests).

Only what queries need is stored in the clear: the pseudonymized patient UUID,
timestamps, severity and status. Clinical values, alert texts and notes live in
`payload`, sealed with AES-256-GCM (see crypto.py). No names are ever stored
here: identity lives in the Identity Service.
"""

import uuid
from collections.abc import AsyncIterator
from datetime import UTC, datetime

from sqlalchemy import BigInteger, DateTime, Index, Integer, LargeBinary, String, Uuid, text
from sqlalchemy.ext.asyncio import AsyncEngine, AsyncSession, async_sessionmaker, create_async_engine
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column


class Base(DeclarativeBase):
    pass


class VitalsRecord(Base):
    __tablename__ = "vitals"

    id: Mapped[int] = mapped_column(
        BigInteger().with_variant(Integer, "sqlite"), primary_key=True, autoincrement=True
    )
    patient_id: Mapped[uuid.UUID] = mapped_column(Uuid)
    recorded_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    received_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    severity: Mapped[str] = mapped_column(String(16))
    payload: Mapped[bytes] = mapped_column(LargeBinary)

    __table_args__ = (Index("ix_vitals_patient_recorded", "patient_id", "recorded_at"),)


class EscalationRecord(Base):
    __tablename__ = "escalations"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    patient_id: Mapped[uuid.UUID] = mapped_column(Uuid, index=True)
    source: Mapped[str] = mapped_column(String(16))
    status: Mapped[str] = mapped_column(String(16), index=True)
    severity: Mapped[str] = mapped_column(String(16))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    requested_by: Mapped[uuid.UUID | None] = mapped_column(Uuid, nullable=True)
    acknowledged_by: Mapped[uuid.UUID | None] = mapped_column(Uuid, nullable=True)
    acknowledged_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    resolved_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    payload: Mapped[bytes] = mapped_column(LargeBinary)  # alerts + note, encrypted

    # At most one open (pending/acknowledged) request per patient.
    __table_args__ = (
        Index(
            "uq_escalations_one_open_per_patient",
            "patient_id",
            unique=True,
            postgresql_where=text("status <> 'resolved'"),
            sqlite_where=text("status <> 'resolved'"),
        ),
    )


class CallRecord(Base):
    """One voice/video call between a patient and the care team.

    Only who, when and how long: the audio and video travel directly between
    the two devices (WebRTC, encrypted end to end) and never reach the server.
    """

    __tablename__ = "calls"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True)
    patient_id: Mapped[uuid.UUID] = mapped_column(Uuid, index=True)
    escalation_id: Mapped[uuid.UUID | None] = mapped_column(Uuid, nullable=True)
    caller_id: Mapped[uuid.UUID] = mapped_column(Uuid)
    caller_role: Mapped[str] = mapped_column(String(16))
    callee_id: Mapped[uuid.UUID | None] = mapped_column(Uuid, nullable=True)  # the patient
    callee_role: Mapped[str] = mapped_column(String(16))
    # ringing | active | ended | missed | declined | cancelled
    status: Mapped[str] = mapped_column(String(16), index=True)
    video: Mapped[bool] = mapped_column(default=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    answered_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    ended_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)


class Database:
    def __init__(self, url: str) -> None:
        self.engine: AsyncEngine = create_async_engine(url, pool_pre_ping=True)
        self.sessions = async_sessionmaker(self.engine, expire_on_commit=False)

    async def create_schema(self) -> None:
        # Schema is small and additive so far; switch to Alembic migrations
        # before the first breaking change.
        async with self.engine.begin() as conn:
            await conn.run_sync(Base.metadata.create_all)

    async def session(self) -> AsyncIterator[AsyncSession]:
        async with self.sessions() as session:
            yield session

    async def dispose(self) -> None:
        await self.engine.dispose()


def utc(value: datetime) -> datetime:
    """SQLite drops timezone info; everything here is UTC."""
    return value if value.tzinfo else value.replace(tzinfo=UTC)
