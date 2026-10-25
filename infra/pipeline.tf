# Wiring for Manik's module (infra/modules/pipeline/). Kept commented out until
# his module is merged to main; then uncomment, and adjust variable names to match
# his module's variables.tf.
#
# module "pipeline" {
#   source               = "./modules/pipeline"
#   prefix               = local.prefix
#   github_repo          = "apoorva-rapolu/sentimentops"
#   ecr_repository_arn   = module.registry.repository_arn
#   lambda_function_name = module.serving.function_name
#   lambda_function_arn  = module.serving.function_arn
#   frontend_bucket_arn  = module.storage.frontend_bucket_arn
#   api_base_url         = module.serving.api_base_url
# }
#
# output "state_machine_arn" {
#   value = module.pipeline.state_machine_arn
# }
#
# output "github_actions_role_arn" {
#   value = module.pipeline.github_actions_role_arn
# }
