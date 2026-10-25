# SentimentOps — shared contracts

These are the only places where one person's work touches another's.
**Build to these exactly.** Any change to this folder needs agreement from all three
(Apoorva, Shaurya, Manik) and a message in the group chat the same day.

Adding a new field is fine. Renaming or removing an existing one is not, unless all three agree.

---

## 1. Repo layout and owners

```
sentimentops/
├── contracts/              # ALL THREE — this file, api-examples.json
├── app/                    # Apoorva — handler.py, model.py, Dockerfile, tests/
├── frontend/               # Apoorva — index.html, app.js, style.css, config.js
├── infra/                  # Shaurya — main.tf, variables.tf, outputs.tf, modules/
│   └── modules/pipeline/   # Manik   — GitHub OIDC role, Step Functions
├── orchestration/          # Manik   — state_machine.asl.json
├── tests/smoke/            # Manik   — post-deploy tests
└── .github/workflows/      # Manik   — ci.yml, deploy.yml, infra.yml
```

Only the owner commits to their folders. Need a change in someone else's folder? Ask them.

---

## 2. API contract

Implemented by **Apoorva** (`app/handler.py`), routed by **Shaurya** (API Gateway), tested by **Manik** (`tests/smoke/`).
Full request/response examples: [`api-examples.json`](api-examples.json).

### `POST /predict`

Request body:

```json
{ "text": "string, 1 to 1000 characters" }
```

`200` response:

```json
{
  "request_id": "uuid4 string",
  "label": "POSITIVE | NEGATIVE | NEUTRAL",
  "score": 0.0,
  "model_version": "string",
  "latency_ms": 0
}
```

- `label` is always UPPERCASE and one of the three values.
- `score` is a number from 0.0 to 1.0 (strength of the sentiment).
- `latency_ms` is an integer.

### `GET /health`

`200` response:

```json
{ "status": "ok", "model_version": "string" }
```

### Errors

| Status | When | Body |
| --- | --- | --- |
| 400 | Body not JSON, no `text`, `text` not a string, empty, or over 1000 chars | `{"error": "<message>"}` |
| 404 | Unknown path | `{"error": "Not found."}` |
| 405 | Wrong method on a known path | `{"error": "Method not allowed."}` |
| 500 | Unexpected failure | `{"error": "internal"}` |

### Headers on every response

```
Content-Type: application/json
Access-Control-Allow-Origin: *
Access-Control-Allow-Methods: GET,POST,OPTIONS
Access-Control-Allow-Headers: Content-Type
```

`OPTIONS` on either path returns `204` (CORS preflight). The handler accepts both
API Gateway REST (payload v1) and HTTP API (payload v2) events, and paths with a stage
prefix such as `/dev/predict`.

---

## 3. Naming, region, tags

- **Region:** `ap-south-1` (Mumbai) for every resource.
- **Name pattern:** `sentimentops-<env>-<resource>`, env = `dev`.

| Resource | Name |
| --- | --- |
| Lambda function | `sentimentops-dev-predict` |
| DynamoDB table | `sentimentops-dev-predictions` |
| ECR repository | `sentimentops-dev-app` |
| API Gateway | `sentimentops-dev-api` |
| Step Functions state machine | `sentimentops-dev-deploy` |
| S3 model/data bucket | `sentimentops-dev-artifacts-<suffix>` |
| S3 frontend bucket | `sentimentops-dev-frontend-<suffix>` |

S3 names must be globally unique, so Shaurya picks one `<suffix>` (e.g. a short random string) and uses it for both buckets.

- **Tags on every resource:** `Project = sentimentops`, `Owner = apoorva | shaurya | manik`, `ManagedBy = terraform`.

---

## 4. Lambda environment variables

Set by **Shaurya** (Terraform), read by **Apoorva** (handler). The handler reads nothing else.

| Variable | Example | Meaning |
| --- | --- | --- |
| `PREDICTIONS_TABLE` | `sentimentops-dev-predictions` | DynamoDB table for prediction logs. Unset = no logging. |
| `MODEL_VERSION` | `vader-1.0` | Returned in every response |
| `LOG_LEVEL` | `INFO` | Python logging level |

---

## 5. DynamoDB predictions table

Created by **Shaurya**, written by **Apoorva**. On-demand billing, TTL on `expires_at`.

| Attribute | Type | Notes |
| --- | --- | --- |
| `request_id` | String (S) | **Partition key** (uuid4) |
| `created_at` | String (S) | ISO 8601 UTC, e.g. `2026-10-25T11:30:00+00:00` |
| `text` | String (S) | First 500 characters of the input only |
| `label` | String (S) | Same as API |
| `score` | Number (N) | Same as API |
| `latency_ms` | Number (N) | Same as API |
| `model_version` | String (S) | Same as API |
| `expires_at` | Number (N) | Epoch seconds, created_at + 30 days (**TTL attribute**) |

Lambda IAM permission needed: `dynamodb:PutItem` on this table only.

---

## 6. Docker image

Built from `app/` (Apoorva's Dockerfile), pushed by **Manik**'s pipeline, deployed to **Shaurya**'s Lambda.

- Base image: `public.ecr.aws/lambda/python:3.12`
- Platform: `linux/amd64`
- Build command (from repo root): `docker build --platform linux/amd64 app/` — no build arguments
- Handler: `handler.lambda_handler` (already the image's `CMD`)
- Tags: the full git commit SHA on every build, plus `latest` on `main`
- Lambda settings: memory 1024 MB, timeout 30 s, package type `Image`
- Unit tests for CI: `pip install -r app/requirements-dev.txt && python -m pytest -q app/tests`

Until the real image exists in ECR, Shaurya's Lambda may point at any placeholder image.

---

## 7. Terraform outputs

Exposed from `infra/outputs.tf`. Consumed by the frontend, workflows and smoke tests.

| Output | Owner | Used by |
| --- | --- | --- |
| `api_base_url` | Shaurya | `frontend/config.js` (written by deploy workflow), smoke tests |
| `ecr_repository_url` | Shaurya | `deploy.yml` image push |
| `lambda_function_name` | Shaurya | Step Functions update step |
| `predictions_table_name` | Shaurya | Debugging, demo |
| `frontend_bucket_name` | Shaurya | `deploy.yml` S3 sync |
| `frontend_url` | Shaurya | Demo link |
| `state_machine_arn` | Manik (pipeline module) | `deploy.yml` start execution |
| `github_actions_role_arn` | Manik (pipeline module) | All workflows (OIDC login) |

`api_base_url` has **no trailing slash**; clients append `/predict` and `/health`.

---

## 8. Step Functions input

Sent by Manik's `deploy.yml`, read by Manik's state machine.

```json
{
  "image_uri": "<ecr_repository_url>:<commit_sha>",
  "commit_sha": "<full git sha>",
  "previous_image_uri": "<image the Lambda ran before this deploy>"
}
```

`previous_image_uri` is what the rollback step restores if the smoke test fails.

---

## Change log

| Date | Change | Agreed by |
| --- | --- | --- |
| 2026-10-25 | First version | — |
