"""Legacy Flask entrypoint kept as a compatibility wrapper."""

from arxiv_discovery.config import load_settings
from arxiv_discovery.web.app import (
    create_app,
    group_papers_by_date,
    run_web_app,
    showcase_enabled,
)

app = create_app(load_settings(legacy=True))

__all__ = [
    "app",
    "create_app",
    "group_papers_by_date",
    "run_web_app",
    "showcase_enabled",
]
