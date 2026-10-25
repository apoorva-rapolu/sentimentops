output "state_machine_arn" {
  description = "Deployment state machine; deploy.yml starts executions on it (contract: state_machine_arn)."
  value       = aws_sfn_state_machine.deploy.arn
}

output "github_actions_role_arn" {
  description = "Role for deploy.yml (contract: github_actions_role_arn)."
  value       = aws_iam_role.github_deploy.arn
}

output "github_actions_infra_plan_role_arn" {
  description = "Read-only role for terraform plan on pull requests (infra.yml)."
  value       = aws_iam_role.github_infra_plan.arn
}

output "github_actions_infra_apply_role_arn" {
  description = "Role for terraform apply on main behind an environment approval (infra.yml)."
  value       = aws_iam_role.github_infra_apply.arn
}
