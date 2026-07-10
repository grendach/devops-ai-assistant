variable "project_name" {
  description = "Project name used for AWS resources."
  type        = string
  default     = "devops-ai-assistant"
}

variable "aws_region" {
  description = "AWS region for Lambda/API/DynamoDB."
  type        = string
  default     = "eu-west-1"
}

variable "bedrock_region" {
  description = "AWS region where Bedrock model is invoked. Keep us-east-1 if unsure."
  type        = string
  default     = "eu-west-1"
}

variable "bedrock_model_id" {
  description = "Bedrock model or inference profile ID. The default uses the EU Nova Lite cross-Region inference profile."
  type        = string
  default     = "eu.amazon.nova-lite-v1:0"
}

variable "allowed_origins" {
  description = "Comma-separated CORS allowed origins. Use * for local learning only."
  type        = string
  default     = "*"
}

variable "allowed_github_repos" {
  description = "GitHub repositories the agent may review and comment on, in owner/repository format."
  type        = list(string)
  default     = ["grendach/expense-tracker"]

  validation {
    condition     = length(var.allowed_github_repos) > 0 && alltrue([for repo in var.allowed_github_repos : can(regex("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", repo))])
    error_message = "Each allowed GitHub repository must use owner/repository format."
  }
}

variable "github_token_secret_name" {
  description = "Secrets Manager secret name whose value is a fine-grained GitHub token."
  type        = string
  default     = "devops-ai-assistant/github-token"
}

variable "review_api_key_secret_name" {
  description = "Secrets Manager secret name containing the key required by the PR review endpoint."
  type        = string
  default     = "devops-ai-assistant/review-api-key"
}

variable "lambda_zip_path" {
  description = "Path to packaged Lambda zip. Run scripts/package_lambda.sh before terraform apply."
  type        = string
  default     = "../build/lambda.zip"
}

variable "log_retention_days" {
  description = "CloudWatch log retention for Lambda."
  type        = number
  default     = 14
}
