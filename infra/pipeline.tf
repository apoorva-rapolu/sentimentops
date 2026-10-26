# Wiring for Manik's module (infra/modules/pipeline/): GitHub OIDC provider,
# the three GitHub Actions roles, and the Step Functions deploy state machine.
#
# The state bucket and lock table are created by bootstrap/bootstrap.sh (not by
# Terraform), with fixed names, so their ARNs are built here.

module "pipeline" {
  source = "./modules/pipeline"

  environment       = var.env
  github_repository = "apoorva-rapolu/sentimentops"

  lambda_function_name = module.serving.function_name
  lambda_function_arn  = module.serving.function_arn
  ecr_repository_arn   = module.registry.repository_arn
  frontend_bucket_arn  = module.storage.frontend_bucket_arn

  tf_state_bucket_arn = "arn:aws:s3:::sentimentops-tfstate-${local.account_id}"
  tf_lock_table_arn   = "arn:aws:dynamodb:${var.region}:${local.account_id}:table/sentimentops-tflock"
}

# ---- Contract section 7 (owned by the pipeline module) ----
output "state_machine_arn" {
  description = "deploy.yml starts executions on it (repo variable STATE_MACHINE_ARN)"
  value       = module.pipeline.state_machine_arn
}

output "github_actions_role_arn" {
  description = "deploy.yml role (repo variable AWS_DEPLOY_ROLE_ARN)"
  value       = module.pipeline.github_actions_role_arn
}

output "github_actions_infra_plan_role_arn" {
  description = "infra.yml plan role (repo variable AWS_INFRA_PLAN_ROLE_ARN)"
  value       = module.pipeline.github_actions_infra_plan_role_arn
}

output "github_actions_infra_apply_role_arn" {
  description = "infra.yml apply role (repo variable AWS_INFRA_APPLY_ROLE_ARN)"
  value       = module.pipeline.github_actions_infra_apply_role_arn
}
