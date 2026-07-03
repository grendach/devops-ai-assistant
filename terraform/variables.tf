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
