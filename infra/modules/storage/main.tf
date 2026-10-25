variable "prefix" { type = string }
variable "account_id" { type = string }

# Account id suffix keeps the globally-unique bucket names collision-free.

# ---------- model / data bucket (private) ----------
resource "aws_s3_bucket" "model" {
  bucket        = "${var.prefix}-models-${var.account_id}"
  force_destroy = true
}

resource "aws_s3_bucket_versioning" "model" {
  bucket = aws_s3_bucket.model.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "model" {
  bucket = aws_s3_bucket.model.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}

resource "aws_s3_bucket_public_access_block" "model" {
  bucket                  = aws_s3_bucket.model.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ---------- frontend website bucket (public read) ----------
resource "aws_s3_bucket" "frontend" {
  bucket        = "${var.prefix}-frontend-${var.account_id}"
  force_destroy = true
}

resource "aws_s3_bucket_versioning" "frontend" {
  bucket = aws_s3_bucket.frontend.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_website_configuration" "frontend" {
  bucket = aws_s3_bucket.frontend.id
  index_document { suffix = "index.html" }
  error_document { key = "index.html" }
}

resource "aws_s3_bucket_public_access_block" "frontend" {
  bucket                  = aws_s3_bucket.frontend.id
  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_policy" "frontend_public_read" {
  bucket = aws_s3_bucket.frontend.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "PublicReadGetObject"
      Effect    = "Allow"
      Principal = "*"
      Action    = "s3:GetObject"
      Resource  = "${aws_s3_bucket.frontend.arn}/*"
    }]
  })
  depends_on = [aws_s3_bucket_public_access_block.frontend]
}

output "model_bucket_name" { value = aws_s3_bucket.model.bucket }
output "model_bucket_arn" { value = aws_s3_bucket.model.arn }
output "frontend_bucket_name" { value = aws_s3_bucket.frontend.bucket }
output "frontend_bucket_arn" { value = aws_s3_bucket.frontend.arn }
output "frontend_website_endpoint" { value = aws_s3_bucket_website_configuration.frontend.website_endpoint }
