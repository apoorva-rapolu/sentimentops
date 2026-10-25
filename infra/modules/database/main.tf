variable "prefix" { type = string }

# Schema (contract section 5): only keys are declared; other attributes are
# schemaless in DynamoDB: created_at, text, label, score, latency_ms,
# model_version, expires_at.
resource "aws_dynamodb_table" "predictions" {
  name         = "${var.prefix}-predictions"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "request_id"

  attribute {
    name = "request_id"
    type = "S"
  }

  ttl {
    attribute_name = "expires_at"
    enabled        = true
  }
}

output "table_name" { value = aws_dynamodb_table.predictions.name }
output "table_arn" { value = aws_dynamodb_table.predictions.arn }
