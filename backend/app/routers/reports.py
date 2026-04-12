from fastapi import APIRouter, Depends, HTTPException, Query, status

from app.core.database import get_db
from app.dependencies import get_current_user
from app.models.report import ReportResponse, ReportsListResponse
from app.services.report_service import generate_weekly_report, get_report, get_reports

router = APIRouter(prefix="/reports", tags=["reports"])


@router.post("/generate", response_model=ReportResponse)
def generate_report(
    current_user: dict = Depends(get_current_user),
    db=Depends(get_db),
):
    return generate_weekly_report(db, current_user["id"])


@router.get("", response_model=ReportsListResponse)
def list_reports(
    limit: int = Query(10, ge=1, le=50),
    offset: int = Query(0, ge=0),
    current_user: dict = Depends(get_current_user),
    db=Depends(get_db),
):
    return get_reports(db, current_user["id"], limit, offset)


@router.get("/{report_id}", response_model=ReportResponse)
def fetch_report(
    report_id: str,
    current_user: dict = Depends(get_current_user),
    db=Depends(get_db),
):
    report = get_report(db, current_user["id"], report_id)
    if report is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Report not found")
    return report
