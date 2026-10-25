# CI/CD and deployment guide (Manik)

## 1. Big picture

```
pull request ──► ci.yml (tests, lint, docker build, workflow/ASL/Terraform checks)
              └► infra.yml: terraform plan (read-only role)

merge to main ─► infra.yml: terraform apply  (only after a reviewer approves "infra-apply")
              └► deploy.yml:
                   tests ─► build image (linux/amd64) ─► push to ECR (tag = commit SHA, + latest)
                   ─► start Step Functions execution ─► wait for result
                   ─► pytest smoke tests on the live API ─► sync frontend to S3
```

Step Functions does: validate input → update Lambda image → wait until updated → smoke test → succeed, or roll back to the previous image and report failure.

## 2. Files

| File | Purpose |
| --- | --- |
| `.github/workflows/ci.yml` | Unit tests, lint, smoke tests against the local dev server, Docker build + container invoke, actionlint, ASL check, Terraform fmt/validate (skipped until `infra/` exists). No AWS access. |
| `.github/workflows/infra.yml` | PR: fmt, init, validate, plan. Main: plan + apply behind an approval. |
| `.github/workflows/deploy.yml` | Application deployment (above). Main branch only. |
| `orchestration/state_machine.asl.json` | The deployment state machine. |
| `orchestration/validate_asl.py` | Offline structural check of the state machine. |
| `infra/modules/pipeline/` | Terraform: OIDC provider, three IAM roles, state machine. Shaurya's root module calls it. |
| `tests/smoke/` | pytest tests for the deployed API. |

## 3. Authentication (GitHub OIDC, no AWS keys)

GitHub gives each job a short-lived token; AWS exchanges it for temporary credentials if the token matches a role's trust policy. Nothing secret is stored in GitHub.

| Role | Used by | Trusted token | Can do |
| --- | --- | --- | --- |
| `…-gha-deploy` | deploy.yml | `main` branch of this repo | push to the ECR repo, read the Lambda's current image, start/describe executions of the one state machine, write to the frontend bucket |
| `…-gha-infra-plan` | infra.yml (PR) | pull requests of this repo | ReadOnlyAccess + read Terraform state |
| `…-gha-infra-apply` | infra.yml (main) | GitHub Environment `infra-apply` | manage `sentimentops-*` resources + Terraform state. Cannot edit the pipeline roles themselves. |

Feature branches (including `manik/ci-cd-orchestration`) cannot deploy. That is intentional.

## 4. GitHub setup (manual)

**Repository variables** (Settings → Secrets and variables → Actions → Variables). None of these are secrets. Fill them from `terraform output` after the first apply:

| Variable | Source |
| --- | --- |
| `AWS_REGION` | `ap-south-1` (confirm in Terraform) |
| `AWS_DEPLOY_ROLE_ARN` | output `github_actions_role_arn` |
| `AWS_INFRA_PLAN_ROLE_ARN` | output `github_actions_infra_plan_role_arn` |
| `AWS_INFRA_APPLY_ROLE_ARN` | output `github_actions_infra_apply_role_arn` |
| `ECR_REPOSITORY_URL` | output `ecr_repository_url` |
| `LAMBDA_FUNCTION_NAME` | output `lambda_function_name` |
| `STATE_MACHINE_ARN` | output `state_machine_arn` |
| `FRONTEND_BUCKET_NAME` | output `frontend_bucket_name` |
| `API_BASE_URL` | output `api_base_url` (no trailing slash needed) |
| `TF_INIT_ARGS` (optional) | extra `terraform init` flags, only if Shaurya uses partial backend config |

**Environment:** create `infra-apply` (Settings → Environments), add a required reviewer (not the person who opened the change), and restrict "Deployment branches" to `main`.

**Branch protection on `main`:** require a pull request, 1 approval, and the CI jobs `App tests, lint, smoke tests`, `Docker image builds and answers`, `Workflows, state machine, Terraform` to pass (team rules 2–3).

## 5. Rollback

1. Before pushing, deploy.yml reads the image the Lambda currently runs (`aws lambda get-function`, digest form) and passes it as `previous_image_uri`.
2. If the update fails, times out (5 min), or any smoke check fails, the state machine updates the Lambda back to `previous_image_uri`, waits for it, and **fails** the execution with `DeploymentRolledBack`. The GitHub job goes red.
3. Special cases: no previous image (first deploy) → `DeploymentFailedNoRollback`, the Lambda stays on the new image; rollback itself fails → `RollbackFailed`, fix by hand: `aws lambda update-function-code --function-name <name> --image-uri <known-good>`.
4. Rollback restores a *digest*, so it works even if the old tag was re-pointed. The ECR lifecycle rule (keep 10 images) will not delete the image currently in use unless 10 newer ones exist.

Manual redeploy of an older commit: re-run the deploy workflow on that commit's run page (it is the same SHA tag).

## 6. When something fails

| Symptom | Where to look |
| --- | --- |
| Red "Check required repository variables" | add the named variable (section 4) |
| "Could not assume role" / `AccessDenied` on login | role ARN variable wrong, or the job is not on `main` / not in the `infra-apply` environment |
| Build fails | Docker step log; reproduce with `docker build --platform linux/amd64 app/` |
| Execution FAILED | the error line in the job summary; AWS Console → Step Functions → `sentimentops-<env>-deploy` → the execution → the red state |
| `DeploymentRolledBack` | read the red state's input/output (`smoke_health`, `smoke_predict`, `error`), and CloudWatch logs of the Lambda |
| Smoke tests fail but the execution succeeded | the API Gateway layer (route, stage, CORS) differs from direct Lambda invocation; check `API_BASE_URL` first |
| Terraform apply `AccessDenied` | add the missing action to `infra_apply` in `infra/modules/pipeline/main.tf`, applied by an admin |

## 7. Run things locally

```bash
# app tests
pip install -r app/requirements-dev.txt && python -m pytest -q app/tests
# smoke tests against a local server
python app/dev_server.py &
pip install -r tests/smoke/requirements.txt
API_BASE_URL=http://localhost:8000 python -m pytest -v tests/smoke
# smoke tests against AWS
API_BASE_URL="https://…/dev" python -m pytest -v tests/smoke
# state machine structure
python orchestration/validate_asl.py
```

## 8. Items that Shaurya must confirm (unresolved)

1. Terraform root: is it `infra/` (as in the contract)? Backend: hard-coded in `main.tf` or partial config? State bucket and lock table ARNs (needed by the pipeline module).
2. Output names exactly as in the contract, plus `lambda_function_arn`, `ecr_repository_arn`, `frontend_bucket_arn` available for the module inputs.
3. Lambda: `ignore_changes = [image_uri]`; API Gateway integration targets the function directly; type of API (REST or HTTP) and whether `api_base_url` already includes the stage.
4. ECR tag mutability `MUTABLE` (for `latest`).
5. Whether the frontend bucket is public website hosting or behind CloudFront (the workflow assumes direct S3 sync).
6. Whether the AWS account already has the GitHub OIDC provider (set `create_github_oidc_provider = false` if so).
7. Which resources besides `sentimentops-*` names exist (e.g. Budgets) so the apply role covers them.
8. The placeholder image is in the same ECR repo and region (Lambda requires this).
9. Terraform version to pin (`1.9.8` is a guess).

## 9. What is not verified

Nothing here has run on AWS or GitHub. Checked offline: unit tests (22 pass), smoke tests (13 pass against the local dev server), ASL structure, workflow YAML via actionlint, Terraform files parse as HCL. Not checked: `terraform validate/plan` (Terraform not available), the IAM policies' completeness, the state machine in real Step Functions, the Docker build in CI.
