variable "prefix" { type = string }
variable "function_name" { type = string }
variable "role_arn" { type = string }
variable "image_uri" { type = string }
variable "memory_mb" { type = number }
variable "timeout_s" { type = number }
variable "log_group_name" { type = string }
variable "cors_origins" { type = list(string) }
variable "predictions_table" { type = string }
variable "model_version" { type = string }
variable "log_level" { type = string }

resource "aws_lambda_function" "predict" {
  function_name = var.function_name
  role          = var.role_arn
  package_type  = "Image"
  image_uri     = var.image_uri
  architectures = ["x86_64"] # linux/amd64 per contract
  memory_size   = var.memory_mb
  timeout       = var.timeout_s

  environment {
    variables = {
      PREDICTIONS_TABLE = var.predictions_table
      MODEL_VERSION     = var.model_version
      LOG_LEVEL         = var.log_level
    }
  }

  logging_config {
    log_format = "Text" # the app writes its own one-line JSON
    log_group  = var.log_group_name
  }

  # The deploy pipeline (Step Functions) owns the image after first creation.
  lifecycle {
    ignore_changes = [image_uri]
  }
}

resource "aws_apigatewayv2_api" "http" {
  name          = "${var.prefix}-api"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = var.cors_origins
    allow_methods = ["GET", "POST", "OPTIONS"]
    allow_headers = ["content-type"]
    max_age       = 3600
  }
}

resource "aws_apigatewayv2_integration" "lambda" {
  api_id                 = aws_apigatewayv2_api.http.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.predict.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "predict" {
  api_id    = aws_apigatewayv2_api.http.id
  route_key = "POST /predict"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

resource "aws_apigatewayv2_route" "health" {
  api_id    = aws_apigatewayv2_api.http.id
  route_key = "GET /health"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.http.id
  name        = "$default"
  auto_deploy = true

  default_route_settings {
    throttling_burst_limit = 20
    throttling_rate_limit  = 10
  }
}

resource "aws_lambda_permission" "apigw" {
  statement_id  = "AllowInvokeFromApiGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.predict.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http.execution_arn}/*/*"
}

output "api_id" { value = aws_apigatewayv2_api.http.id }
output "api_base_url" { value = aws_apigatewayv2_api.http.api_endpoint }
output "function_name" { value = aws_lambda_function.predict.function_name }
output "function_arn" { value = aws_lambda_function.predict.arn }
