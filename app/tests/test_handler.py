"""Unit tests for the API contract. Run with:  make test   (no AWS needed)."""

import importlib
import json

import boto3
import pytest
from moto import mock_aws

TABLE = "sentimentops-dev-predictions"
LABELS = {"POSITIVE", "NEGATIVE", "NEUTRAL"}


def rest_event(method, path, body=None):
    """API Gateway REST API (payload v1) event."""
    return {"httpMethod": method, "path": path, "body": body, "isBase64Encoded": False}


def http_api_event(method, path, body=None):
    """API Gateway HTTP API (payload v2) event."""
    return {
        "rawPath": path,
        "requestContext": {"http": {"method": method}},
        "body": body,
        "isBase64Encoded": False,
    }


def predict(handler_mod, text, event_fn=rest_event):
    return handler_mod.lambda_handler(event_fn("POST", "/predict", json.dumps({"text": text})), None)


@pytest.fixture
def handler(monkeypatch):
    """Handler with no DynamoDB configured (like `make run-local`)."""
    monkeypatch.delenv("PREDICTIONS_TABLE", raising=False)
    monkeypatch.setenv("MODEL_VERSION", "vader-test")
    import handler as h

    return importlib.reload(h)


@pytest.fixture
def handler_with_table(monkeypatch):
    """Handler wired to a moto-mocked DynamoDB table matching the contract schema."""
    with mock_aws():
        ddb = boto3.resource("dynamodb", region_name="ap-south-1")
        table = ddb.create_table(
            TableName=TABLE,
            KeySchema=[{"AttributeName": "request_id", "KeyType": "HASH"}],
            AttributeDefinitions=[{"AttributeName": "request_id", "AttributeType": "S"}],
            BillingMode="PAY_PER_REQUEST",
        )
        monkeypatch.setenv("PREDICTIONS_TABLE", TABLE)
        monkeypatch.setenv("MODEL_VERSION", "vader-test")
        import handler as h

        yield importlib.reload(h), table


# ---------- /health ----------

def test_health(handler):
    res = handler.lambda_handler(rest_event("GET", "/health"), None)
    assert res["statusCode"] == 200
    assert json.loads(res["body"]) == {"status": "ok", "model_version": "vader-test"}


# ---------- /predict: response shape ----------

def test_predict_response_matches_contract(handler):
    res = predict(handler, "I love how fast this deploys!")
    assert res["statusCode"] == 200
    body = json.loads(res["body"])
    assert set(body) == {"request_id", "label", "score", "model_version", "latency_ms"}
    assert body["label"] in LABELS
    assert 0.0 <= body["score"] <= 1.0
    assert isinstance(body["latency_ms"], int)
    assert body["model_version"] == "vader-test"


@pytest.mark.parametrize(
    "text,label",
    [
        ("This is absolutely wonderful, great job!", "POSITIVE"),
        ("This is terrible and I hate it.", "NEGATIVE"),
        ("The meeting is at 3 pm in room 204.", "NEUTRAL"),
    ],
)
def test_predict_labels(handler, text, label):
    assert json.loads(predict(handler, text)["body"])["label"] == label


def test_headers_have_json_and_cors(handler):
    headers = predict(handler, "nice")["headers"]
    assert headers["Content-Type"] == "application/json"
    assert headers["Access-Control-Allow-Origin"] == "*"


def test_works_with_http_api_events_too(handler):
    res = predict(handler, "great", event_fn=http_api_event)
    assert res["statusCode"] == 200
    res = handler.lambda_handler(http_api_event("GET", "/health"), None)
    assert res["statusCode"] == 200


def test_stage_prefix_in_path(handler):
    res = handler.lambda_handler(rest_event("GET", "/dev/health"), None)
    assert res["statusCode"] == 200


# ---------- /predict: bad input -> 400 ----------

@pytest.mark.parametrize(
    "body",
    [
        None,
        "not json",
        json.dumps([1, 2]),
        json.dumps({"message": "wrong field"}),
        json.dumps({"text": 123}),
        json.dumps({"text": ""}),
        json.dumps({"text": "   "}),
        json.dumps({"text": "a" * 1001}),
    ],
)
def test_bad_input_returns_400(handler, body):
    res = handler.lambda_handler(rest_event("POST", "/predict", body), None)
    assert res["statusCode"] == 400
    assert "error" in json.loads(res["body"])


def test_max_length_text_is_accepted(handler):
    assert predict(handler, "a" * 1000)["statusCode"] == 200


# ---------- routing ----------

def test_unknown_path_404(handler):
    assert handler.lambda_handler(rest_event("GET", "/nope"), None)["statusCode"] == 404


def test_wrong_method_405(handler):
    assert handler.lambda_handler(rest_event("GET", "/predict"), None)["statusCode"] == 405


def test_cors_preflight(handler):
    assert handler.lambda_handler(rest_event("OPTIONS", "/predict"), None)["statusCode"] == 204


# ---------- DynamoDB logging ----------

def test_prediction_is_logged_to_dynamodb(handler_with_table):
    h, table = handler_with_table
    text = "Fantastic work! " * 50  # 800 chars, longer than the 500 stored
    body = json.loads(predict(h, text)["body"])

    item = table.get_item(Key={"request_id": body["request_id"]})["Item"]
    assert item["label"] == body["label"]
    assert float(item["score"]) == body["score"]
    assert item["model_version"] == "vader-test"
    assert len(item["text"]) == 500
    assert int(item["expires_at"]) > 0
    assert item["created_at"].endswith("+00:00")


def test_dynamodb_failure_does_not_break_prediction(handler, monkeypatch):
    class BrokenTable:
        def put_item(self, **_):
            raise RuntimeError("DynamoDB down")

    monkeypatch.setattr(handler, "_get_table", lambda: BrokenTable())
    assert predict(handler, "still works")["statusCode"] == 200
