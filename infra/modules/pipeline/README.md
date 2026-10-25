# infra/modules/pipeline — GitHub OIDC roles + deployment state machine

**Owner:** Manik (per the team split). **Called from:** Shaurya's root `infra/main.tf`.
Not yet run through `terraform validate`/`plan` -- do that before relying on it.

## What it creates
| Resource | Used by |
| --- | --- |
| OIDC provider `token.actions.githubusercontent.com` (optional) | all roles |
| `sentimentops-<env>-gha-deploy` (trust: `main` branch only) | `deploy.yml` |
| `sentimentops-<env>-gha-infra-plan` (trust: pull requests, read-only) | `infra.yml` plan |
| `sentimentops-<env>-gha-infra-apply` (trust: GitHub Environment `infra-apply`) | `infra.yml` apply |
| `sentimentops-<env>-deploy` Step Functions state machine (+ role, log group) | `deploy.yml` |

## Wiring in the root module (Shaurya)
```hcl
module "pipeline" {
  source = "./modules/pipeline"

  environment          = var.environment
  lambda_function_name = module.serving.lambda_function_name
  lambda_function_arn  = module.serving.lambda_function_arn
  ecr_repository_arn   = module.registry.repository_arn
  frontend_bucket_arn  = module.storage.frontend_bucket_arn
  tf_state_bucket_arn  = "<bucket from infra/bootstrap>"
  tf_lock_table_arn    = "<lock table from infra/bootstrap>"
}

output "state_machine_arn"                    { value = module.pipeline.state_machine_arn }
output "github_actions_role_arn"              { value = module.pipeline.github_actions_role_arn }
output "github_actions_infra_plan_role_arn"   { value = module.pipeline.github_actions_infra_plan_role_arn }
output "github_actions_infra_apply_role_arn"  { value = module.pipeline.github_actions_infra_apply_role_arn }
```
(The `module.serving...` names are placeholders -- use whatever Shaurya's modules actually expose.)

## Requirements on Shaurya's other modules
1. Lambda uses `package_type = "Image"` and must have `lifecycle { ignore_changes = [image_uri] }`, otherwise every `terraform apply` resets the function to the placeholder image and undoes the last deployment.
2. The API Gateway integration must point at the function itself (not a pinned version), because the pipeline updates the function code in place.
3. ECR tag mutability must be `MUTABLE` if `latest` is pushed (SHA tags stay unique anyway).
4. The state machine definition is read from `orchestration/state_machine.asl.json` (`${lambda_function_name}` is substituted by `templatefile`).

## First apply
Run once by an admin from a laptop (the roles cannot create themselves): `terraform apply`, then copy the outputs into GitHub repository variables (see `docs/ci-cd-deployment.md`).
