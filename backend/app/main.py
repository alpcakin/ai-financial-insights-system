"""
FastAPI application entry point.

This is the file that uvicorn loads to start the server:
    uvicorn app.main:app --reload

CORS middleware is configured to accept requests from any origin
because the mobile app makes requests from the Android emulator,
whose origin varies.  In production this would be restricted to
the deployed frontend domain.

Routers are registered here — each router groups related endpoints
(e.g. /auth/register, /auth/login).
"""

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.routers import auth, portfolio, watchlist

app = FastAPI(title="AI Financial Insights API", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(auth.router)
app.include_router(portfolio.router)
app.include_router(watchlist.router)


@app.get("/health")
def health():
    """Simple endpoint to verify the server is running."""
    return {"status": "ok"}
