# Owner: Manik. GitHub OIDC roles + Step Functions deployment state machine.
#
# NOT validated with `terraform validate` yet -- run it once Terraform is available (see README.md).

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_partition" "current" {}

locals {
  prefix     = "sentimentops-${var.environment}"
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.name
  partition  = data.aws_partition.current.partition
  tags       = merge({ Project = "sentimentops", Owner = "manik", ManagedBy = "terraform" }, var.tags)

  oidc_host         = "token.actions.githubusercontent.com"
  oidc_provider_arn = var.create_github_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : data.aws_iam_openid_connect_provider.github[0].arn

  state_machine_name = "${local.prefix}-deploy"
  state_machine_arn  = "arn:${local.partition}:states:${local.region}:${local.account_id}:stateMachine:${local.state_machine_name}"
  execution_arn      = "arn:${local.partition}:states:${local.region}:${local.account_id}:execution:${local.state_machine_name}:*"
}

# ---------------------------------------------------------------------------
# GitHub OIDC provider (one per AWS account)
# ---------------------------------------------------------------------------
resource "aws_iam_openid_connect_provider" "github" {
  count          = var.create_github_oidc_provider ? 1 : 0
  url            = "https://${local.oidc_host}"
  client_id_list = ["sts.amazonaws.com"]
  # AWS no longer validates this for GitHub, but older provider versions require a value.
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1", "1c58a3a8518e8759bf075b76b750d4f2df264fcd"]
  tags            = local.tags
}

data "aws_iam_openid_connect_provider" "github" {
  count = var.create_github_oidc_provider ? 0 : 1
  url   = "https://${local.oidc_host}"
}

# ---------------------------------------------------------------------------
# Trust policies: who may assume each role (repo + exact workflow context)
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "trust_deploy" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:sub"
      values   = ["repo:${var.github_repository}:ref:refs/heads/${var.deploy_branch}"]
    }
  }
}

data "aws_iam_policy_document" "trust_infra_plan" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:sub"
      values   = ["repo:${var.github_repository}:pull_request"]
    }
  }
}

data "aws_iam_policy_document" "trust_infra_apply" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:aud"
      values   = ["sts.amazonaws.com"]
    }
    # Jobs that use a GitHub Environment get this "sub". Restrict the environment to
    # the main branch in GitHub (Settings > Environments > Deployment branches).
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:sub"
      values   = ["repo:${var.github_repository}:environment:${var.infra_apply_environment}"]
    }
  }
}

# ---------------------------------------------------------------------------
# Role 1: application deploy (deploy.yml) -- push image, run state machine, sync frontend
# ---------------------------------------------------------------------------
resource "aws_iam_role" "github_deploy" {
  name               = "${local.prefix}-gha-deploy"
  assume_role_policy = data.aws_iam_policy_document.trust_deploy.json
  tags               = local.tags
}

data "aws_iam_policy_document" "deploy" {
  statement {
    sid       = "EcrLogin"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }
  statement {
    sid = "EcrPush"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:PutImage",
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
      "ecr:DescribeImages",
    ]
    resources = [var.ecr_repository_arn]
  }
  statement {
    sid       = "ReadCurrentImage"
    actions   = ["lambda:GetFunction"]
    resources = [var.lambda_function_arn]
  }
  statement {
    sid       = "StartDeployment"
    actions   = ["states:StartExecution"]
    resources = [local.state_machine_arn]
  }
  statement {
    sid       = "WatchDeployment"
    actions   = ["states:DescribeExecution", "states:GetExecutionHistory"]
    resources = [local.execution_arn]
  }
  statement {
    sid       = "FrontendList"
    actions   = ["s3:ListBucket"]
    resources = [var.frontend_bucket_arn]
  }
  statement {
    sid       = "FrontendSync"
    actions   = ["s3:PutObject", "s3:DeleteObject"]
    resources = ["${var.frontend_bucket_arn}/*"]
  }
}

resource "aws_iam_role_policy" "github_deploy" {
  name   = "deploy"
  role   = aws_iam_role.github_deploy.id
  policy = data.aws_iam_policy_document.deploy.json
}

# ---------------------------------------------------------------------------
# Role 2: terraform plan on pull requests -- read-only
# ---------------------------------------------------------------------------
resource "aws_iam_role" "github_infra_plan" {
  name               = "${local.prefix}-gha-infra-plan"
  assume_role_policy = data.aws_iam_policy_document.trust_infra_plan.json
  tags               = local.tags
}

resource "aws_iam_role_policy_attachment" "infra_plan_readonly" {
  role       = aws_iam_role.github_infra_plan.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/ReadOnlyAccess"
}

data "aws_iam_policy_document" "infra_plan_state" {
  statement {
    sid       = "StateRead"
    actions   = ["s3:ListBucket", "s3:GetObject"]
    resources = [var.tf_state_bucket_arn, "${var.tf_state_bucket_arn}/*"]
  }
}

resource "aws_iam_role_policy" "github_infra_plan" {
  name   = "state-read"
  role   = aws_iam_role.github_infra_plan.id
  policy = data.aws_iam_policy_document.infra_plan_state.json
}

# ---------------------------------------------------------------------------
# Role 3: terraform apply on main (after environment approval)
# Scoped to resources named sentimentops-*. Expect to add a permission or two
# the first time apply runs (AccessDenied tells you which).
# ---------------------------------------------------------------------------
resource "aws_iam_role" "github_infra_apply" {
  name               = "${local.prefix}-gha-infra-apply"
  assume_role_policy = data.aws_iam_policy_document.trust_infra_apply.json
  tags               = local.tags
}

data "aws_iam_policy_document" "infra_apply" {
  statement {
    sid       = "StateBucket"
    actions   = ["s3:ListBucket", "s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = [var.tf_state_bucket_arn, "${var.tf_state_bucket_arn}/*"]
  }
  statement {
    sid       = "StateLock"
    actions   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:DeleteItem"]
    resources = [var.tf_lock_table_arn]
  }
  statement {
    sid       = "ProjectBuckets"
    actions   = ["s3:*"]
    resources = ["arn:${local.partition}:s3:::sentimentops-*", "arn:${local.partition}:s3:::sentimentops-*/*"]
  }
  statement {
    sid       = "ProjectEcr"
    actions   = ["ecr:*"]
    resources = ["arn:${local.partition}:ecr:${local.region}:${local.account_id}:repository/sentimentops-*"]
  }
  statement {
    sid       = "ProjectLambda"
    actions   = ["lambda:*"]
    resources = ["arn:${local.partition}:lambda:${local.region}:${local.account_id}:function:sentimentops-*"]
  }
  statement {
    sid       = "ProjectApiGateway"
    actions   = ["apigateway:*"]
    resources = ["arn:${local.partition}:apigateway:${local.region}::/restapis", "arn:${local.partition}:apigateway:${local.region}::/restapis/*", "arn:${local.partition}:apigateway:${local.region}::/apis", "arn:${local.partition}:apigateway:${local.region}::/apis/*", "arn:${local.partition}:apigateway:${local.region}::/tags/*"]
  }
  statement {
    sid       = "ProjectDynamoDb"
    actions   = ["dynamodb:*"]
    resources = ["arn:${local.partition}:dynamodb:${local.region}:${local.account_id}:table/sentimentops-*"]
  }
  statement {
    sid       = "ProjectLogs"
    actions   = ["logs:*"]
    resources = ["arn:${local.partition}:logs:${local.region}:${local.account_id}:log-group:/aws/*sentimentops-*", "arn:${local.partition}:logs:${local.region}:${local.account_id}:log-group:/aws/*sentimentops-*:*"]
  }
  statement {
    sid       = "LogsAccountLevel"
    actions   = ["logs:DescribeLogGroups", "logs:ListTagsForResource", "logs:CreateLogDelivery", "logs:GetLogDelivery", "logs:UpdateLogDelivery", "logs:DeleteLogDelivery", "logs:ListLogDeliveries", "logs:PutResourcePolicy", "logs:DescribeResourcePolicies"]
    resources = ["*"]
  }
  statement {
    sid       = "ProjectAlarms"
    actions   = ["cloudwatch:*"]
    resources = ["arn:${local.partition}:cloudwatch:${local.region}:${local.account_id}:alarm:sentimentops-*"]
  }
  statement {
    sid       = "AlarmsDescribe"
    actions   = ["cloudwatch:DescribeAlarms", "cloudwatch:ListTagsForResource"]
    resources = ["*"]
  }
  statement {
    sid       = "ProjectStateMachines"
    actions   = ["states:*"]
    resources = ["arn:${local.partition}:states:${local.region}:${local.account_id}:stateMachine:sentimentops-*"]
  }
  statement {
    sid       = "ProjectBudgets"
    actions   = ["budgets:*"]
    resources = ["arn:${local.partition}:budgets::${local.account_id}:budget/sentimentops-*"]
  }
  statement {
    sid = "ProjectIamRoles"
    actions = [
      "iam:CreateRole", "iam:DeleteRole", "iam:GetRole", "iam:UpdateRole", "iam:UpdateAssumeRolePolicy",
      "iam:TagRole", "iam:UntagRole", "iam:ListRoleTags", "iam:ListRolePolicies", "iam:ListAttachedRolePolicies",
      "iam:ListInstanceProfilesForRole", "iam:PutRolePolicy", "iam:GetRolePolicy", "iam:DeleteRolePolicy",
      "iam:AttachRolePolicy", "iam:DetachRolePolicy",
    ]
    resources = ["arn:${local.partition}:iam::${local.account_id}:role/sentimentops-*"]
  }
  statement {
    sid       = "PassRoleToProjectServices"
    actions   = ["iam:PassRole"]
    resources = ["arn:${local.partition}:iam::${local.account_id}:role/sentimentops-*"]
    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["lambda.amazonaws.com", "states.amazonaws.com", "apigateway.amazonaws.com"]
    }
  }
  # Safety net: the pipeline can never edit its own trust/permissions. Changes to this
  # module's roles are applied by an admin from a laptop (team rule 9: one apply at a time).
  statement {
    sid     = "ProtectPipelineRoles"
    effect  = "Deny"
    actions = ["iam:*"]
    resources = [
      aws_iam_role.github_deploy.arn,
      aws_iam_role.github_infra_plan.arn,
      aws_iam_role.github_infra_apply.arn,
      "arn:${local.partition}:iam::${local.account_id}:oidc-provider/${local.oidc_host}",
    ]
  }
}

resource "aws_iam_role_policy" "github_infra_apply" {
  name   = "apply"
  role   = aws_iam_role.github_infra_apply.id
  policy = data.aws_iam_policy_document.infra_apply.json
}

# ---------------------------------------------------------------------------
# Step Functions: deployment state machine
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "deploy_state_machine" {
  name              = "/aws/vendedlogs/states/${local.state_machine_name}"
  retention_in_days = 14
  tags              = local.tags
}

data "aws_iam_policy_document" "trust_state_machine" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["states.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "state_machine" {
  name               = "${local.prefix}-deploy-sfn"
  assume_role_policy = data.aws_iam_policy_document.trust_state_machine.json
  tags               = local.tags
}

data "aws_iam_policy_document" "state_machine" {
  statement {
    sid       = "UpdateAndInspectLambda"
    actions   = ["lambda:UpdateFunctionCode", "lambda:GetFunctionConfiguration", "lambda:InvokeFunction"]
    resources = [var.lambda_function_arn, "${var.lambda_function_arn}:*"]
  }
  statement {
    # Lambda checks that the caller may read the image it is switching to.
    sid       = "ReadImageForUpdate"
    actions   = ["ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer"]
    resources = [var.ecr_repository_arn]
  }
  statement {
    sid       = "ExecutionLogs"
    actions   = ["logs:CreateLogDelivery", "logs:GetLogDelivery", "logs:UpdateLogDelivery", "logs:DeleteLogDelivery", "logs:ListLogDeliveries", "logs:PutResourcePolicy", "logs:DescribeResourcePolicies", "logs:DescribeLogGroups"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "state_machine" {
  name   = "deploy"
  role   = aws_iam_role.state_machine.id
  policy = data.aws_iam_policy_document.state_machine.json
}

resource "aws_sfn_state_machine" "deploy" {
  name     = local.state_machine_name
  role_arn = aws_iam_role.state_machine.arn
  type     = "STANDARD" # deploy.yml needs describe-execution / execution history

  definition = templatefile("${path.module}/../../../orchestration/state_machine.asl.json", {
    lambda_function_name = var.lambda_function_name
  })

  logging_configuration {
    log_destination        = "${aws_cloudwatch_log_group.deploy_state_machine.arn}:*"
    include_execution_data = false # keep image URIs/payloads out of logs
    level                  = "ERROR"
  }

  tags = local.tags

  depends_on = [aws_iam_role_policy.state_machine]
}
