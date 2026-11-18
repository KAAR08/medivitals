from collections.abc import AsyncIterator
from typing import Annotated

from fastapi import Depends, Request
from sqlalchemy.ext.asyncio import AsyncSession

from .crypto import Cipher
from .hub import Hub


async def _session(request: Request) -> AsyncIterator[AsyncSession]:
    async with request.app.state.db.sessions() as session:
        yield session


def _cipher(request: Request) -> Cipher:
    return request.app.state.cipher


def _hub(request: Request) -> Hub:
    return request.app.state.hub


Session = Annotated[AsyncSession, Depends(_session)]
CipherDep = Annotated[Cipher, Depends(_cipher)]
HubDep = Annotated[Hub, Depends(_hub)]
