"""
API 认证模块
"""

from contextvars import ContextVar
from dataclasses import dataclass, field
import hmac
from typing import FrozenSet, Iterable, Optional
from fastapi import HTTPException, Request, Response, Security, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials

from app.core.config import get_config

DEFAULT_API_KEY = ""
DEFAULT_NSFW_API_KEY = ""
DEFAULT_APP_KEY = "grok2api"
DEFAULT_FUNCTION_KEY = ""
DEFAULT_FUNCTION_ENABLED = False
FUNCTION_AUTH_COOKIE = "grok2api_function_auth"
NSFW_TAG = "nsfw"


@dataclass(frozen=True)
class ApiKeyScope:
    name: str = "default"
    required_tags: FrozenSet[str] = field(default_factory=frozenset)
    exclude_tags: FrozenSet[str] = field(default_factory=frozenset)
    allow_nsfw: bool = True

    @property
    def allows_nsfw(self) -> bool:
        return self.allow_nsfw


_DEFAULT_API_KEY_SCOPE = ApiKeyScope()
_api_key_scope_ctx: ContextVar[ApiKeyScope] = ContextVar(
    "api_key_scope", default=_DEFAULT_API_KEY_SCOPE
)

# 定义 Bearer Scheme
security = HTTPBearer(
    auto_error=False,
    scheme_name="API Key",
    description="Enter your API Key in the format: Bearer <key>",
)


def get_admin_api_key() -> str:
    """
    获取后台 API Key。

    为空时表示不启用后台接口认证。
    """
    api_key = get_config("app.api_key", DEFAULT_API_KEY)
    return api_key or ""


def get_nsfw_api_key() -> str:
    """获取 NSFW 专用 API Key。"""
    api_key = get_config("app.api_key_nsfw", DEFAULT_NSFW_API_KEY)
    return api_key or ""


def _normalize_api_keys(value: Optional[object]) -> list[str]:
    if not value:
        return []
    if isinstance(value, str):
        raw = value.strip()
        if not raw:
            return []
        return [part.strip() for part in raw.split(",") if part.strip()]
    if isinstance(value, Iterable):
        keys: list[str] = []
        for item in value:
            if not item:
                continue
            if isinstance(item, str):
                stripped = item.strip()
                if stripped:
                    keys.append(stripped)
        return keys
    return []

def get_app_key() -> str:
    """
    获取 App Key（后台管理密码）。
    """
    app_key = get_config("app.app_key", DEFAULT_APP_KEY)
    return app_key or ""

def get_function_api_key() -> str:
    """
    获取功能玩法 API Key。

    为空时表示不启用功能玩法接口认证。
    """
    function_key = get_config("app.function_key", DEFAULT_FUNCTION_KEY)
    return function_key or ""


def get_api_key_scope() -> ApiKeyScope:
    """获取当前请求的 API Key 作用域。"""
    return _api_key_scope_ctx.get()


def current_api_key_allows_nsfw() -> bool:
    """当前请求是否允许使用 NSFW 号池。"""
    return get_api_key_scope().allows_nsfw


def clear_api_key_scope() -> None:
    _api_key_scope_ctx.set(_DEFAULT_API_KEY_SCOPE)


def _set_api_key_scope(scope: ApiKeyScope) -> None:
    _api_key_scope_ctx.set(scope)


def is_function_enabled() -> bool:
    """
    是否开启功能玩法入口。
    """
    return bool(get_config("app.function_enabled", DEFAULT_FUNCTION_ENABLED))


def _match_function_key(credentials: str, function_key: str) -> bool:
    """检查凭证是否匹配 function_key。"""
    if not function_key:
        return False
    normalized = function_key.strip()
    if not normalized:
        return False
    # 常量时间比较，避免基于时序的探测
    return hmac.compare_digest(credentials, normalized)


def set_function_auth_cookie(response: Response) -> None:
    """设置 function 页面访问 Cookie。"""
    function_key = get_function_api_key()
    if not function_key:
        clear_function_auth_cookie(response)
        return
    response.set_cookie(
        key=FUNCTION_AUTH_COOKIE,
        value=function_key,
        httponly=True,
        samesite="lax",
        path="/",
    )


def clear_function_auth_cookie(response: Response) -> None:
    """清理 function 页面访问 Cookie。"""
    response.delete_cookie(key=FUNCTION_AUTH_COOKIE, path="/")


def has_function_page_access(request: Request) -> bool:
    """检查当前请求是否可访问 function 页面。"""
    if not is_function_enabled():
        return False
    function_key = get_function_api_key()
    if not function_key:
        return True
    cookie_key = request.cookies.get(FUNCTION_AUTH_COOKIE, "")
    return _match_function_key(cookie_key, function_key)


async def verify_api_key(
    auth: Optional[HTTPAuthorizationCredentials] = Security(security),
) -> Optional[str]:
    """
    验证 Bearer Token

    如果 config.toml 中未配置 api_key，则不启用认证。
    """
    normal_keys = _normalize_api_keys(get_admin_api_key())
    nsfw_keys = _normalize_api_keys(get_nsfw_api_key())
    if not normal_keys and not nsfw_keys:
        clear_api_key_scope()
        return None

    if not auth:
        clear_api_key_scope()
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing authentication token",
            headers={"WWW-Authenticate": "Bearer"},
        )

    for key in normal_keys:
        if hmac.compare_digest(auth.credentials, key):
            _set_api_key_scope(
                ApiKeyScope(
                    name="standard",
                    allow_nsfw=False,
                )
            )
            return auth.credentials

    for key in nsfw_keys:
        if hmac.compare_digest(auth.credentials, key):
            _set_api_key_scope(
                ApiKeyScope(
                    name="nsfw",
                    allow_nsfw=True,
                )
            )
            return auth.credentials

    raise HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Invalid authentication token",
        headers={"WWW-Authenticate": "Bearer"},
    )


async def verify_app_key(
    auth: Optional[HTTPAuthorizationCredentials] = Security(security),
) -> Optional[str]:
    """
    验证后台登录密钥（app_key）。

    app_key 必须配置，否则拒绝登录。
    """
    clear_api_key_scope()
    app_key = get_app_key()

    if not app_key:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="App key is not configured",
            headers={"WWW-Authenticate": "Bearer"},
        )

    if not auth:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing authentication token",
            headers={"WWW-Authenticate": "Bearer"},
        )

    if not hmac.compare_digest(auth.credentials, app_key):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid authentication token",
            headers={"WWW-Authenticate": "Bearer"},
        )

    return auth.credentials


async def verify_function_key(
    auth: Optional[HTTPAuthorizationCredentials] = Security(security),
) -> Optional[str]:
    """
    验证功能玩法 Key（function 接口使用）。

    默认不公开，需配置 function_key 才能访问；
    若开启 function_enabled 且未配置 function_key，则放开访问。
    """
    clear_api_key_scope()
    function_key = get_function_api_key()
    function_enabled = is_function_enabled()

    if not function_key:
        if function_enabled:
            return None
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Function access is disabled",
            headers={"WWW-Authenticate": "Bearer"},
        )

    if not auth:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing authentication token",
            headers={"WWW-Authenticate": "Bearer"},
        )

    if _match_function_key(auth.credentials, function_key):
        return auth.credentials

    raise HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Invalid authentication token",
        headers={"WWW-Authenticate": "Bearer"},
    )
