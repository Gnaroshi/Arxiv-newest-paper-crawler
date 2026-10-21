import sys
from pathlib import Path

import pytest
import requests

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "src"
if str(SRC) not in sys.path:
    sys.path.insert(0, str(SRC))


@pytest.fixture(autouse=True)
def no_real_network(monkeypatch):
    def blocked(*_args, **_kwargs):
        pytest.fail("Tests must use a network fixture, not a live server")

    monkeypatch.setattr(requests.Session, "request", blocked)
