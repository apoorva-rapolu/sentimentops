variable "prefix" { type = string }
variable "account_id" { type = string }
variable "region" { type = string }

resource "aws_ecr_repository" "app" {
  name                 = "${var.prefix}-app"
  image_tag_mutability = "MUTABLE" # `latest` and `placeholder` move
  force_delete         = true      # lets terraform destroy work with images present

  image_scanning_configuration { scan_on_push = true }
}

resource "aws_ecr_lifecycle_policy" "keep_last_10" {
  repository = aws_ecr_repository.app.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep the last 10 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = { type = "expire" }
    }]
  })
}

# Lets the Lambda service pull images from this repo
resource "aws_ecr_repository_policy" "lambda_pull" {
  repository = aws_ecr_repository.app.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "LambdaECRImageRetrievalPolicy"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = ["ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer"]
      Condition = {
        StringLike = { "aws:sourceArn" = "arn:aws:lambda:${var.region}:${var.account_id}:function:*" }
      }
    }]
  })
}

output "repository_url" { value = aws_ecr_repository.app.repository_url }
output "repository_arn" { value = aws_ecr_repository.app.arn }
output "repository_name" { value = aws_ecr_repository.app.name }
