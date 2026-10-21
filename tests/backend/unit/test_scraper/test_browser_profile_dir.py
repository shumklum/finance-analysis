"""Tests for the opt-in persistent browser profile directory (server deployments)."""

import os

from scraper.base.browser_scraper import browser_profile_dir


def test_disabled_without_env(monkeypatch):
    """No FAD_SCRAPER_PROFILE_DIR means a fresh browser per run, as upstream."""
    monkeypatch.delenv("FAD_SCRAPER_PROFILE_DIR", raising=False)
    assert browser_profile_dir("hapoalim", {"userCode": "u1", "password": "p"}) is None


def test_one_private_dir_per_login(monkeypatch, tmp_path):
    """Each provider + login gets its own 0700 directory, stable across runs."""
    monkeypatch.setenv("FAD_SCRAPER_PROFILE_DIR", str(tmp_path))
    first = browser_profile_dir("hapoalim", {"userCode": "u1", "password": "p"})
    again = browser_profile_dir("hapoalim", {"userCode": "u1", "password": "changed"})
    other = browser_profile_dir("hapoalim", {"userCode": "u2", "password": "p"})

    assert first == again  # a password change keeps the trusted profile
    assert first != other
    assert os.path.dirname(first) == str(tmp_path)
    assert os.path.basename(first).startswith("hapoalim-")
    assert os.stat(first).st_mode & 0o777 == 0o700


def test_dir_name_never_contains_credentials(monkeypatch, tmp_path):
    """Usernames and secrets stay out of the path; only a hash identifies the login."""
    monkeypatch.setenv("FAD_SCRAPER_PROFILE_DIR", str(tmp_path))
    path = browser_profile_dir("max", {"username": "someone@example.com", "password": "hunter2"})
    assert "someone" not in path and "hunter2" not in path
