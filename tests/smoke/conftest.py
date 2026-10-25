"""Shared fixtures for the post-deploy smoke tests.

Needs only one setting:  API_BASE_URL  (the Terraform output `api_base_url`).
Optional:                SMOKE_MAX_LATENCY_S  (round-trip limit, default 10)

These tests talk to a running API over HTTP. They do not import app/ code.
"""
import os
import time

import pytest
import requests

TIMEOUT_S = 30  # Lambda cold start + model load can take a few seconds


class Api:
    def __init__(self, base_url: str):
        self.base_url = base_url.rstrip("/")
        self.max_latency_s = float(os.environ.get("SMOKE_MAX_LATENCY_S", "10"))

    def get(self, path: str):
        return requests.get(f"{self.base_url}{path}", timeout=TIMEOUT_S)

    def post(self, path: str, json=None, data=None):
        headers = {"Content-Type": "application/json"}
        return requests.post(f"{self.base_url}{path}", json=json, data=data,
                             headers=headers, timeout=TIMEOUT_S)


def parse_json(response):
    """Return the parsed JSON body or fail with a readable message."""
    try:
        return response.json()
    except ValueError:
        pytest.fail(
            f"Response from {response.request.method} {response.url} is not valid JSON "
            f"(HTTP {response.status_code}). Body starts with: {response.text[:200]!r}"
        )


@pytest.fixture(scope="session")
def api():
    base_url = os.environ.get("API_BASE_URL", "").strip()
    if not base_url:
        pytest.fail("API_BASE_URL is not set. Use the Terraform output `api_base_url`, "
                    "e.g.  API_BASE_URL=https://xxxx.execute-api.ap-south-1.amazonaws.com/dev")
    client = Api(base_url)

    # Warm-up: a freshly deployed Lambda may need a moment (cold start / API Gateway propagation).
    last = None
    for _ in range(6):
        try:
            if client.get("/health").status_code == 200:
                return client
            last = "HTTP non-200"
        except requests.RequestException as exc:
            last = repr(exc)
        time.sleep(5)
    pytest.fail(f"API at {client.base_url} did not answer GET /health with 200 after 6 tries "
                f"(last problem: {last}).")
