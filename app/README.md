# app/ — sentiment model + Lambda handler

**Owner:** Apoorva. Implements the API contract in `contracts/README.md` (sections 2, 4, 5, 6).

## Files

| File | What it does |
| --- | --- |
| `model.py` | Wraps the model. Exposes `predict(text) -> (label, score)` and `MODEL_NAME`. Swap models here only. |
| `handler.py` | `lambda_handler`: routes `POST /predict`, `GET /health`, CORS preflight; validates input; logs to DynamoDB |
| `Dockerfile` | Lambda container image (`public.ecr.aws/lambda/python:3.12`, handler `handler.lambda_handler`) |
| `requirements.txt` | What goes in the image (just `vaderSentiment`; `boto3` is already in the Lambda runtime) |
| `requirements-dev.txt` | Adds `boto3`, `moto`, `pytest` for local tests |
| `tests/` | Unit tests — no AWS account needed (DynamoDB mocked with moto) |
| `events/` | Sample API Gateway events for invoking the container locally |
| `dev_server.py` | Local stand-in for API Gateway on port 8000 (dev only, not in the image) |

## Run it

```bash
cd app
make install          # once: pip install -r requirements-dev.txt
make test             # unit tests (22)

# Option A — no Docker: run the handler behind a local HTTP server
python dev_server.py  # http://localhost:8000/health , POST /predict

# Option B — the real Lambda container, with the built-in Runtime Interface Emulator
make run-local        # builds the image, runs it on port 9000
make invoke-health
make invoke-predict
make invoke-bad       # should return statusCode 400
make stop
```

## Behaviour

- **Labels:** VADER compound score ≥ 0.05 → `POSITIVE`, ≤ −0.05 → `NEGATIVE`, otherwise `NEUTRAL`.
- **Score (0–1):** strength of the sentiment, `|compound|` for POSITIVE/NEGATIVE, `1 − |compound|` for NEUTRAL.
- **Validation → 400:** body not JSON, not an object, no `text`, `text` not a string, empty/whitespace, over 1000 chars.
- **Other errors:** unknown path → 404, wrong method → 405, unexpected crash → 500 `{"error": "internal"}`.
- **DynamoDB:** one row per prediction, schema per contract section 5 (text cut to 500 chars, `expires_at` = +30 days).
  If `PREDICTIONS_TABLE` is unset (local runs) logging is skipped. A DynamoDB failure is logged but never fails the request.
- **CloudWatch:** one JSON log line per prediction (`"event": "prediction"` + the response fields), searchable in Logs Insights.
- Accepts both API Gateway **REST (v1)** and **HTTP API (v2)** events, and stage prefixes like `/dev/predict`.

## Environment variables (set by Terraform)

`PREDICTIONS_TABLE`, `MODEL_VERSION`, `LOG_LEVEL` — nothing else is read.

## What the others need from me

- **Manik:** build with `docker build --platform linux/amd64 app/`; CI runs `pip install -r app/requirements-dev.txt && python -m pytest -q app/tests`.
- **Shaurya:** Lambda needs only `dynamodb:PutItem` on the predictions table + CloudWatch Logs. 1024 MB / 30 s is plenty for VADER.

## Switching to DistilBERT later

Rewrite `predict()` in `model.py` to use a HuggingFace pipeline, add `transformers` + `torch` (CPU) to
`requirements.txt`, and download the model during `docker build` so it is baked into the image.
Keep the return value as `(UPPERCASE_LABEL, score_0_to_1)` and nothing else changes. Expect a bigger image
and a slower cold start; ask Shaurya to raise Lambda memory to ~2048 MB.
