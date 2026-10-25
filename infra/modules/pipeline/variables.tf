# Inputs come from Shaurya's root module (infra/main.tf) -- see README.md for the exact wiring.

variable "environment" {
  description = "Environment name used in resource names: sentimentops-<environment>-<resource>."
  type        = string
  default     = "dev"
}

variable "github_repository" {
  description = "GitHub repository allowed to assume the roles, as owner/name."
  type        = string
  default     = "apoorva-rapolu/sentimentops"
}

variable "deploy_branch" {
  description = "Only this branch can assume the deploy role."
  type        = string
  default     = "main"
}

variable "infra_apply_environment" {
  description = "GitHub Environment (with required reviewers) that infra.yml's apply job runs in."
  type        = string
  default     = "infra-apply"
}

variable "create_github_oidc_provider" {
  description = "Set to false if this AWS account already has the token.actions.githubusercontent.com OIDC provider (only one is allowed per account)."
  type        = bool
  default     = true
}

variable "lambda_function_name" {
  description = "Name of the inference Lambda (Shaurya's module output lambda_function_name)."
  type        = string
}

variable "lambda_function_arn" {
  description = "ARN of the inference Lambda."
  type        = string
}

variable "ecr_repository_arn" {
  description = "ARN of the ECR repository holding the app image."
  type        = string
}

variable "frontend_bucket_arn" {
  description = "ARN of the S3 bucket hosting the frontend (output frontend_bucket_name -> arn)."
  type        = string
}

variable "tf_state_bucket_arn" {
  description = "ARN of the Terraform remote-state S3 bucket (from infra/bootstrap)."
  type        = string
}

variable "tf_lock_table_arn" {
  description = "ARN of the Terraform state-lock DynamoDB table (from infra/bootstrap)."
  type        = string
}

variable "tags" {
  description = "Extra tags. Project/Owner/ManagedBy are added automatically."
  type        = map(string)
  default     = {}
}
