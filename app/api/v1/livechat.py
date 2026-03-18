from fastapi import APIRouter
from pydantic import BaseModel

from app.core.exceptions import AppException
from app.services.grok.services.voice import VoiceService
from app.services.grok.utils.retry import pick_token
from app.services.token.manager import get_token_manager

router = APIRouter(tags=["LiveChat"])


class LiveChatTokenResponse(BaseModel):
    token: str
    url: str
    participant_name: str = ""
    room_name: str = ""


@router.get("/livechat/token", response_model=LiveChatTokenResponse)
async def create_livechat_token(
    voice: str = "ara",
    personality: str = "assistant",
    speed: float = 1.0,
):
    """使用 API Key 换取 LiveChat 所需的 LiveKit token。"""
    token_mgr = await get_token_manager()
    await token_mgr.reload_if_stale()

    sso_token = await pick_token(token_mgr, "grok-3", set())
    if not sso_token:
        raise AppException(
            "No available tokens for livechat",
            code="no_token",
            status_code=503,
        )

    service = VoiceService()
    try:
        data = await service.get_token(
            token=sso_token,
            voice=voice,
            personality=personality,
            speed=speed,
        )
        token = data.get("token")
        if not token:
            raise AppException(
                "Upstream returned no livechat token",
                code="upstream_error",
                status_code=502,
            )

        return LiveChatTokenResponse(
            token=token,
            url="wss://livekit.grok.com",
            participant_name=str(data.get("participantName") or ""),
            room_name=str(data.get("roomName") or ""),
        )
    except Exception as e:
        if isinstance(e, AppException):
            raise
        raise AppException(
            f"Livechat token error: {str(e)}",
            code="livechat_error",
            status_code=500,
        )


__all__ = ["router"]
