"""SentimentOps Lambda handler.

Implements the API contract in contracts/README.md:
    POST /predict  {"text": "..."}  -> prediction JSON
    GET  /health                    -> {"status": "ok", "model_version": "..."}

Works with both API Gateway REST APIs (payload v1) and HTTP APIs (payload v2),
so it does not matter which one the Terraform module creates.

Environment variables (contract section 4 — read nothing else):
    PREDICTIONS_TABLE  DynamoDB table for prediction logs (unset = skip logging)
    MODEL_VERSION      returned in every response
    LOG_LEVEL          Python logging level
"""

import json
import logging
import os
import time
import uuid
from datetime import datetime, timedelta, timezone
from decimal import Decimal

import model

MAX_TEXT_CHARS = 1000      # contract: text is 1–1000 characters
STORED_TEXT_CHARS = 500    # contract: DynamoDB keeps the first 500 only
LOG_TTL_DAYS = 30          # contract: expires_at = now + 30 days

PREDICTIONS_TABLE = os.environ.get("PREDICTIONS_TABLE", "")
MODEL_VERSION = os.environ.get("MODEL_VERSION", f"{model.MODEL_NAME}-local")

logger = logging.getLogger()
logger.setLevel(os.environ.get("LOG_LEVEL", "INFO").upper())

CORS_HEADERS = {
    "Content-Type": "application/json",
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "GET,POST,OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type",
}

_table = None


def _get_table():
    """Create the DynamoDB table client lazily, once per container."""
    global _table
    if _table is None and PREDICTIONS_TABLE:
        import boto3  # boto3 ships with the Lambda Python runtime

        _table = boto3.resource("dynamodb").Table(PREDICTIONS_TABLE)
    return _table


# ---------- helpers ----------

def _response(status: int, body: dict | None = None) -> dict:
    return {
        "statusCode": status,
        "headers": CORS_HEADERS,
        "body": json.dumps(body) if body is not None else "",
    }


def _error(status: int, message: str) -> dict:
    return _response(status, {"error": message})


def _method_and_path(event: dict) -> tuple[str, str]:
    """Read method + path from either API Gateway payload format."""
    http = event.get("requestContext", {}).get("http")
    if http:  # HTTP API, payload v2
        return http.get("method", "").upper(), event.get("rawPath", "")
    return event.get("httpMethod", "").upper(), event.get("path", "")  # REST API, v1


def _log(record: dict) -> None:
    """One JSON line per request, easy to search in CloudWatch Logs Insights."""
    logger.info(json.dumps(record))


# ---------- routes ----------

def _health() -> dict:
    return _response(200, {"status": "ok", "model_version": MODEL_VERSION})


def _predict(event: dict) -> dict:
    started = time.perf_counter()

    raw = event.get("body") or ""
    if event.get("isBase64Encoded"):
        import base64

        raw = base64.b64decode(raw).decode("utf-8")

    try:
        payload = json.loads(raw)
    except (json.JSONDecodeError, TypeError):
        return _error(400, "Request body must be valid JSON.")

    if not isinstance(payload, dict) or "text" not in payload:
        return _error(400, 'Request body must be a JSON object with a "text" field.')

    text = payload["text"]
    if not isinstance(text, str):
        return _error(400, '"text" must be a string.')
    text = text.strip()
    if not text:
        return _error(400, '"text" must not be empty.')
    if len(text) > MAX_TEXT_CHARS:
        return _error(400, f'"text" must be at most {MAX_TEXT_CHARS} characters.')

    label, score = model.predict(text)
    latency_ms = int((time.perf_counter() - started) * 1000)
    request_id = str(uuid.uuid4())

    result = {
        "request_id": request_id,
        "label": label,
        "score": score,
        "model_version": MODEL_VERSION,
        "latency_ms": latency_ms,
    }

    _save_prediction(result, text)
    _log({"event": "prediction", **result, "text_chars": len(text)})
    return _response(200, result)


def _save_prediction(result: dict, text: str) -> None:
    """Write one row per the DynamoDB contract. Never fails the request."""
    table = _get_table()
    if table is None:
        return
    now = datetime.now(timezone.utc)
    try:
        table.put_item(
            Item={
                "request_id": result["request_id"],
                "created_at": now.isoformat(timespec="seconds"),
                "text": text[:STORED_TEXT_CHARS],
                "label": result["label"],
                "score": Decimal(str(result["score"])),
                "latency_ms": result["latency_ms"],
                "model_version": result["model_version"],
                "expires_at": int((now + timedelta(days=LOG_TTL_DAYS)).timestamp()),
            }
        )
    except Exception:  # a logging failure must not break predictions
        logger.exception("Failed to write prediction to DynamoDB")


# ---------- entry point ----------

def lambda_handler(event, context):
    try:
        method, path = _method_and_path(event or {})

        if method == "OPTIONS":  # CORS preflight from the browser
            return _response(204)
        if path.endswith("/health") and method == "GET":
            return _health()
        if path.endswith("/predict") and method == "POST":
            return _predict(event)
        if path.endswith("/health") or path.endswith("/predict"):
            return _error(405, "Method not allowed.")
        return _error(404, "Not found.")
    except Exception:
        logger.exception("Unhandled error")
        return _error(500, "internal")
