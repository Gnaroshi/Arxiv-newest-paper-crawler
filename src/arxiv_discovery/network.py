from __future__ import annotations

import os
import tempfile
import time
from pathlib import Path
from urllib.parse import urlparse

import requests
from requests.adapters import HTTPAdapter


class BoundedAdapter(HTTPAdapter):
    """Supply connect/read limits missing from arxiv 2.x's requests calls."""

    def send(self, request, **kwargs):
        if kwargs.get("timeout") is None:
            kwargs["timeout"] = (5, 10)
        return super().send(request, **kwargs)


def configure_arxiv_client(client):
    session = getattr(client, "_session", None)
    if not isinstance(session, requests.Session):
        raise RuntimeError("Unsupported arXiv transport; bounded requests are required")
    session.mount("https://", BoundedAdapter(max_retries=0))
    session.mount("http://", BoundedAdapter(max_retries=0))
    client.num_retries = 0
    client.delay_seconds = 3
    return client


def gemini_http_options():
    from google.genai import types

    return types.HttpOptions(
        timeout=30_000,
        retry_options=types.HttpRetryOptions(attempts=1),
    )


def download_pdf(url: str, destination: Path) -> None:
    """Stream an explicit download; never overwrite an existing reading copy."""
    if destination.exists():
        return
    parsed = urlparse(url)
    if parsed.hostname not in {"arxiv.org", "export.arxiv.org"}:
        raise ValueError("Only arXiv PDF URLs are supported")
    url = parsed._replace(scheme="https").geturl()
    destination.parent.mkdir(parents=True, exist_ok=True)
    descriptor, name = tempfile.mkstemp(dir=destination.parent, suffix=".pdf.part")
    temporary = Path(name)
    started = time.monotonic()
    try:
        with os.fdopen(descriptor, "wb") as output:
            with requests.get(url, stream=True, timeout=(5, 10)) as response:
                response.raise_for_status()
                size = 0
                prefix = bytearray()
                for chunk in response.iter_content(chunk_size=64 * 1024):
                    if time.monotonic() - started > 45:
                        raise TimeoutError("PDF download exceeded its time limit")
                    size += len(chunk)
                    if size > 100 * 1024 * 1024:
                        raise ValueError("PDF download exceeded the size limit")
                    if len(prefix) < 5:
                        prefix.extend(chunk[: 5 - len(prefix)])
                    output.write(chunk)
                if bytes(prefix) != b"%PDF-":
                    raise ValueError("The server did not return a PDF")
        # An exclusive link avoids replacing a file created during the request.
        os.link(temporary, destination)
    finally:
        temporary.unlink(missing_ok=True)
