from __future__ import annotations

from pathlib import Path

from fastapi import APIRouter, HTTPException

from app.sidecar.schemas import (
    OpenProjectRequest,
    OpenProjectResponse,
    ProjectPathResponse,
    SaveProjectRequest,
    load_project_document,
    save_project_document,
)


def create_projects_router() -> APIRouter:
    router = APIRouter()

    @router.post("/save-project", response_model=ProjectPathResponse)
    def save_project(request: SaveProjectRequest) -> ProjectPathResponse:
        try:
            project_path = save_project_document(request.project_path, request.data)
            return ProjectPathResponse(project_path=str(project_path))
        except Exception as exc:
            raise HTTPException(status_code=400, detail=str(exc)) from exc

    @router.post("/open-project", response_model=OpenProjectResponse)
    def open_project(request: OpenProjectRequest) -> OpenProjectResponse:
        try:
            payload = load_project_document(request.project_path)
            return OpenProjectResponse(
                project_path=str(Path(request.project_path).expanduser()),
                data=payload,
            )
        except Exception as exc:
            raise HTTPException(status_code=400, detail=str(exc)) from exc

    return router
