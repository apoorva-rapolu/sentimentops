import time

import pytest

from conftest import parse_json

LABELS = {"POSITIVE", "NEGATIVE", "NEUTRAL"}


def check_prediction_shape(body):
    assert isinstance(body.get("request_id"), str) and body["request_id"], f"bad request_id in {body}"
    assert body.get("label") in LABELS, f"label must be one of {sorted(LABELS)}, got {body.get('label')!r}"
    score = body.get("score")
    assert isinstance(score, (int, float)) and not isinstance(score, bool), f"score must be a number, got {score!r}"
    assert 0.0 <= score <= 1.0, f"score must be between 0 and 1, got {score}"
    assert isinstance(body.get("model_version"), str) and body["model_version"], f"bad model_version in {body}"
    latency = body.get("latency_ms")
    assert isinstance(latency, int) and not isinstance(latency, bool) and latency >= 0, \
        f"latency_ms must be a non-negative integer, got {latency!r}"


def test_valid_prediction(api):
    started = time.perf_counter()
    res = api.post("/predict", json={"text": "I really enjoyed this product."})
    elapsed = time.perf_counter() - started
    assert res.status_code == 200, f"POST /predict returned {res.status_code}: {res.text[:200]}"
    check_prediction_shape(parse_json(res))
    assert elapsed <= api.max_latency_s, \
        f"round trip took {elapsed:.1f}s, limit is {api.max_latency_s}s (set SMOKE_MAX_LATENCY_S to change)"


@pytest.mark.parametrize("text, expected", [
    ("I love this, it is wonderful and works great!", "POSITIVE"),
    ("This is terrible, I hate it and it is awful.", "NEGATIVE"),
])
def test_obvious_sentences_get_expected_label(api, text, expected):
    body = parse_json(api.post("/predict", json={"text": text}))
    check_prediction_shape(body)
    assert body["label"] == expected, f"{text!r} -> {body['label']} (expected {expected}); model_version={body['model_version']}"


def test_text_at_max_length_is_accepted(api):
    res = api.post("/predict", json={"text": "good " * 200})  # exactly 1000 characters
    assert res.status_code == 200, f"1000-char text should be accepted, got {res.status_code}: {res.text[:200]}"


@pytest.mark.parametrize("payload, why", [
    ({"text": ""}, "empty text"),
    ({"text": "   "}, "whitespace-only text"),
    ({"text": "a" * 1001}, "text longer than 1000 characters"),
    ({"text": 123}, "text is not a string"),
    ({"other": "x"}, "missing text field"),
])
def test_invalid_input_returns_400(api, payload, why):
    res = api.post("/predict", json=payload)
    assert res.status_code == 400, f"{why}: expected HTTP 400, got {res.status_code}: {res.text[:200]}"
    body = parse_json(res)
    assert isinstance(body.get("error"), str) and body["error"], f'{why}: expected {{"error": "..."}}, got {body}'


def test_malformed_json_returns_400(api):
    res = api.post("/predict", data="{not json")
    assert res.status_code == 400, f"malformed JSON: expected HTTP 400, got {res.status_code}: {res.text[:200]}"
    assert "error" in parse_json(res)
