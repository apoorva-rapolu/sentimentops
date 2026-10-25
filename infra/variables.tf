variable "region" {
  type    = string
  default = "ap-south-1"
}

variable "env" {
  type    = string
  default = "dev"
}

variable "image_uri" {
  description = "Lambda image. Empty = use the placeholder image (<ecr_url>:placeholder). The deploy pipeline updates the live function afterwards; Terraform ignores later changes."
  type        = string
  default     = ""
}

variable "model_version" {
  type    = string
  default = "vader-1.0"
}

variable "log_level" {
  type    = string
  default = "INFO"
}

variable "lambda_memory_mb" {
  type    = number
  default = 1024
}

variable "lambda_timeout_s" {
  type    = number
  default = 30
}

variable "extra_cors_origins" {
  description = "Extra origins allowed by the API (local frontend dev)."
  type        = list(string)
  default     = ["http://localhost:8000", "http://localhost:5500", "http://127.0.0.1:5500"]
}

variable "alarm_email" {
  description = "Optional. If set, alarms notify this email via SNS (confirm the subscription email)."
  type        = string
  default     = ""
}
