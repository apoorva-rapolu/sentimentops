from conftest import parse_json


def test_health_returns_200_and_json(api):
    res = api.get("/health")
    assert res.status_code == 200, f"GET /health returned {res.status_code}: {res.text[:200]}"
    assert "application/json" in res.headers.get("Content-Type", ""), \
        f"Content-Type should be application/json, got {res.headers.get('Content-Type')!r}"


def test_health_body_shape(api):
    body = parse_json(api.get("/health"))
    assert body.get("status") == "ok", f'expected "status": "ok", got {body}'
    assert isinstance(body.get("model_version"), str) and body["model_version"], \
        f"model_version must be a non-empty string, got {body.get('model_version')!r}"


def test_cors_header_present(api):
    res = api.get("/health")
    assert "Access-Control-Allow-Origin" in res.headers, \
        "CORS header Access-Control-Allow-Origin missing (the frontend on S3 would be blocked)"
