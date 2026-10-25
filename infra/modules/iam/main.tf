variable "prefix" { type = string }
variable "table_arn" { type = string }
variable "log_group_arn" { type = string }

data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda" {
  name               = "${var.prefix}-lambda-exec"
  assume_role_policy = data.aws_iam_policy_document.assume.json
}

# Least privilege: write to its one table, write to its one log group.
data "aws_iam_policy_document" "lambda" {
  statement {
    sid       = "WritePredictions"
    actions   = ["dynamodb:PutItem"]
    resources = [var.table_arn]
  }
  statement {
    sid       = "WriteLogs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${var.log_group_arn}:*"]
  }
}

resource "aws_iam_role_policy" "lambda" {
  name   = "${var.prefix}-lambda-policy"
  role   = aws_iam_role.lambda.id
  policy = data.aws_iam_policy_document.lambda.json
}

output "lambda_role_arn" { value = aws_iam_role.lambda.arn }
output "lambda_role_name" { value = aws_iam_role.lambda.name }
