# orchestration/ — deployment state machine

**Owner:** Manik. `state_machine.asl.json` is Amazon States Language. It is created by `infra/modules/pipeline` (Terraform fills in `${lambda_function_name}`), and started by `.github/workflows/deploy.yml`.

Input: `{"image_uri": "<ecr_repository_url>:<sha>", "commit_sha": "<sha>", "previous_image_uri": "<uri or empty>"}`

Flow: ValidateInput -> UpdateFunction -> poll until `LastUpdateStatus` is `Successful` -> smoke test (health, predict, bad input, by invoking the Lambda directly) -> Succeed. Any failure -> restore `previous_image_uri` -> **Fail** (`DeploymentRolledBack`). No previous image -> Fail (`DeploymentFailedNoRollback`). A rollback is never reported as success.

Check it offline: `python orchestration/validate_asl.py`. This only checks structure; the real test is one execution in AWS.
