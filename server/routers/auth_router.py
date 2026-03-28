"""Authentication router — register, login, token validation."""

from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from auth import create_access_token, decode_token, hash_password, verify_password
from database import get_db
from models import Account
from schemas import LoginRequest, RegisterRequest, TokenResponse

router = APIRouter(prefix="/auth", tags=["auth"])
security = HTTPBearer()


async def get_current_account(
    credentials: HTTPAuthorizationCredentials = Depends(security),
    db: AsyncSession = Depends(get_db),
) -> Account:
    """Dependency: extract and validate the current user from the JWT."""
    payload = decode_token(credentials.credentials)
    if payload is None:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid token")
    account_id = payload.get("account_id")
    if account_id is None:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid token")
    result = await db.execute(select(Account).where(Account.id == account_id))
    account = result.scalar_one_or_none()
    if account is None or account.is_banned:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Account not found or banned")
    return account


@router.post("/register", response_model=TokenResponse, status_code=201)
async def register(req: RegisterRequest, db: AsyncSession = Depends(get_db)):
    # Check username uniqueness
    existing = await db.execute(select(Account).where(Account.username == req.username))
    if existing.scalar_one_or_none():
        raise HTTPException(status_code=409, detail="Username already taken")

    # Check email uniqueness
    existing_email = await db.execute(select(Account).where(Account.email == req.email))
    if existing_email.scalar_one_or_none():
        raise HTTPException(status_code=409, detail="Email already registered")

    account = Account(
        username=req.username,
        password_hash=hash_password(req.password),
        email=req.email,
    )
    db.add(account)
    await db.commit()
    await db.refresh(account)

    token = create_access_token({"account_id": account.id, "username": account.username})
    return TokenResponse(access_token=token, username=account.username, account_id=account.id)


@router.post("/login", response_model=TokenResponse)
async def login(req: LoginRequest, db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(Account).where(Account.username == req.username))
    account = result.scalar_one_or_none()
    if account is None or not verify_password(req.password, account.password_hash):
        raise HTTPException(status_code=401, detail="Invalid username or password")
    if account.is_banned:
        raise HTTPException(status_code=403, detail="Account is banned")

    account.last_login = datetime.now(timezone.utc)
    await db.commit()

    token = create_access_token({"account_id": account.id, "username": account.username})
    return TokenResponse(access_token=token, username=account.username, account_id=account.id)
