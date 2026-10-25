data "aws_caller_identity" "current" {}

locals {
  prefix        = "sentimentops-${var.env}"
  function_name = "${local.prefix}-predict"
  account_id    = data.aws_caller_identity.current.account_id
}

module "storage" {
  source     = "./modules/storage"
  prefix     = local.prefix
  account_id = local.account_id
}

module "registry" {
  source     = "./modules/registry"
  prefix     = local.prefix
  account_id = local.account_id
  region     = var.region
}

module "database" {
  source = "./modules/database"
  prefix = local.prefix
}

module "monitoring" {
  source        = "./modules/monitoring"
  prefix        = local.prefix
  function_name = local.function_name
  api_id        = module.serving.api_id
  alarm_email   = var.alarm_email
}

module "iam" {
  source        = "./modules/iam"
  prefix        = local.prefix
  table_arn     = module.database.table_arn
  log_group_arn = module.monitoring.log_group_arn
}

module "serving" {
  source         = "./modules/serving"
  prefix         = local.prefix
  function_name  = local.function_name
  role_arn       = module.iam.lambda_role_arn
  image_uri      = var.image_uri != "" ? var.image_uri : "${module.registry.repository_url}:placeholder"
  memory_mb      = var.lambda_memory_mb
  timeout_s      = var.lambda_timeout_s
  log_group_name = module.monitoring.log_group_name
  cors_origins   = concat(["http://${module.storage.frontend_website_endpoint}"], var.extra_cors_origins)

  # Lambda environment variables (contract section 4)
  predictions_table = module.database.table_name
  model_version     = var.model_version
  log_level         = var.log_level
}
