"""Placeholder Lambda: follows the API contract with a canned response so the
pipeline and frontend can be built before the real model image exists."""
import json
import os
import time
import uuid

HEADERS = {"Content-Type": "application/json", "Access-Control-Allow-Origin": "*"}
VERSION = os.environ.get("MODEL_VERSION", "placeholder-0.0")


def _resp(code, body):
    return {"statusCode": code, "headers": HEADERS, "body": json.dumps(body)}


def lambda_handler(event, context):
    http = event.get("requestContext", {}).get("http", {})
    method, path = http.get("method"), event.get("rawPath")

    if method == "GET" and path == "/health":
        return _resp(200, {"status": "ok", "model_version": VERSION})

    if method == "POST" and path == "/predict":
        start = time.time()
        try:
            text = json.loads(event.get("body") or "{}").get("text", "")
        except json.JSONDecodeError:
            return _resp(400, {"error": "invalid JSON"})
        if not isinstance(text, str) or not 1 <= len(text) <= 1000:
            return _resp(400, {"error": "text must be 1-1000 characters"})
        return _resp(200, {
            "request_id": str(uuid.uuid4()),
            "label": "NEUTRAL",
            "score": 0.5,
            "model_version": VERSION,
            "latency_ms": int((time.time() - start) * 1000),
        })

    return _resp(404, {"error": "not found"})
