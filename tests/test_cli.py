from types import SimpleNamespace

from arxiv_paper_crawler import cli


def test_open_native_app_uses_fixed_bundle_identifier(monkeypatch):
    calls: list[list[str]] = []
    monkeypatch.setattr(cli.sys, "platform", "darwin")
    monkeypatch.setattr(
        cli.subprocess,
        "run",
        lambda args, **kwargs: calls.append(args)
        or SimpleNamespace(returncode=0),
    )

    assert cli.open_native_app() is True
    assert calls == [["open", "-b", "dev.gnaroshi.ArxivDiscovery"]]


def test_open_native_app_does_not_spawn_on_other_platforms(monkeypatch):
    monkeypatch.setattr(cli.sys, "platform", "linux")

    assert cli.open_native_app() is False
