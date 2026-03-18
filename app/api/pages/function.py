from pathlib import Path

from fastapi import APIRouter, HTTPException, Request
from fastapi.responses import FileResponse, RedirectResponse

from app.core.auth import has_function_page_access, is_function_enabled

router = APIRouter()
STATIC_DIR = Path(__file__).resolve().parents[3] / "_public" / "static"


def _function_page_response(relative_path: str) -> FileResponse:
    file_path = STATIC_DIR / relative_path
    if not file_path.exists():
        raise HTTPException(status_code=404, detail="Page not found")
    return FileResponse(file_path)


@router.get("/", include_in_schema=False)
async def root(request: Request):
    if is_function_enabled():
        if has_function_page_access(request):
            return RedirectResponse(url="/chat")
        return RedirectResponse(url="/login")
    return RedirectResponse(url="/admin/login")


@router.get("/login", include_in_schema=False)
async def function_login(request: Request):
    if not is_function_enabled():
        raise HTTPException(status_code=404, detail="Not Found")
    if has_function_page_access(request):
        return RedirectResponse(url="/chat")
    return _function_page_response("function/pages/login.html")


@router.get("/imagine", include_in_schema=False)
async def function_imagine(request: Request):
    if not is_function_enabled():
        raise HTTPException(status_code=404, detail="Not Found")
    if not has_function_page_access(request):
        return RedirectResponse(url="/login")
    return _function_page_response("function/pages/imagine.html")


@router.get("/voice", include_in_schema=False)
async def function_voice(request: Request):
    if not is_function_enabled():
        raise HTTPException(status_code=404, detail="Not Found")
    if not has_function_page_access(request):
        return RedirectResponse(url="/login")
    return _function_page_response("function/pages/voice.html")


@router.get("/video", include_in_schema=False)
async def function_video(request: Request):
    if not is_function_enabled():
        raise HTTPException(status_code=404, detail="Not Found")
    if not has_function_page_access(request):
        return RedirectResponse(url="/login")
    return _function_page_response("function/pages/video.html")


@router.get("/chat", include_in_schema=False)
async def function_chat(request: Request):
    if not is_function_enabled():
        raise HTTPException(status_code=404, detail="Not Found")
    if not has_function_page_access(request):
        return RedirectResponse(url="/login")
    return _function_page_response("function/pages/chat.html")
