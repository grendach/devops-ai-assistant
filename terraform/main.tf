provider "aws" {
  region              = var.aws_region
  allowed_account_ids = ["432180781943"]
}

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

locals {
  name          = var.project_name
  lambda_name   = "${local.name}-api"
  history_table = "${local.name}-history"
  common_tags = {
    Project   = local.name
    ManagedBy = "Terraform"
  }
}

resource "aws_dynamodb_table" "history" {
  name         = local.history_table
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "request_id"

  attribute {
    name = "request_id"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }

  tags = local.common_tags
}

# Terraform creates only the secret container. Add the token separately so it
# never appears in Terraform configuration or state.
resource "aws_secretsmanager_secret" "github_token" {
  name        = var.github_token_secret_name
  description = "Fine-grained GitHub token used by the DevOps AI PR reviewer."
  tags        = local.common_tags
}

resource "aws_secretsmanager_secret" "review_api_key" {
  name        = var.review_api_key_secret_name
  description = "Shared API key protecting the GitHub PR review endpoint."
  tags        = local.common_tags
}

resource "aws_iam_role" "lambda" {
  name = "${local.lambda_name}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "basic" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_policy" "app" {
  name        = "${local.lambda_name}-policy"
  description = "Permissions for DevOps AI Assistant Lambda."

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel",
          "bedrock:InvokeModelWithResponseStream"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:Query"
        ]
        Resource = aws_dynamodb_table.history.arn
      },
      {
        Effect = "Allow"
        Action = "secretsmanager:GetSecretValue"
        Resource = [
          aws_secretsmanager_secret.github_token.arn,
          aws_secretsmanager_secret.review_api_key.arn
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "app" {
  role       = aws_iam_role.lambda.name
  policy_arn = aws_iam_policy.app.arn
}

resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${local.lambda_name}"
  retention_in_days = var.log_retention_days
  tags              = local.common_tags
}

resource "aws_lambda_function" "api" {
  function_name    = local.lambda_name
  role             = aws_iam_role.lambda.arn
  runtime          = "python3.12"
  handler          = "main.handler"
  filename         = var.lambda_zip_path
  source_code_hash = filebase64sha256(var.lambda_zip_path)
  timeout          = 60
  memory_size      = 512

  environment {
    variables = {
      APP_NAME                  = local.name
      HISTORY_TABLE             = aws_dynamodb_table.history.name
      BEDROCK_REGION            = var.bedrock_region
      BEDROCK_MODEL_ID          = var.bedrock_model_id
      ALLOWED_ORIGINS           = var.allowed_origins
      ALLOWED_GITHUB_REPOS      = join(",", var.allowed_github_repos)
      GITHUB_TOKEN_SECRET_ARN   = aws_secretsmanager_secret.github_token.arn
      REVIEW_API_KEY_SECRET_ARN = aws_secretsmanager_secret.review_api_key.arn
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.basic,
    aws_iam_role_policy_attachment.app,
    aws_cloudwatch_log_group.lambda
  ]

  tags = local.common_tags
}

resource "aws_apigatewayv2_api" "http" {
  name          = "${local.name}-http-api"
  protocol_type = "HTTP"

  cors_configuration {
    allow_headers = ["*"]
    allow_methods = ["GET", "POST", "OPTIONS"]
    allow_origins = split(",", var.allowed_origins)
    max_age       = 300
  }

  tags = local.common_tags
}

resource "aws_apigatewayv2_integration" "lambda" {
  api_id                 = aws_apigatewayv2_api.http.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.api.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "proxy" {
  api_id    = aws_apigatewayv2_api.http.id
  route_key = "ANY /{proxy+}"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

resource "aws_apigatewayv2_route" "root" {
  api_id    = aws_apigatewayv2_api.http.id
  route_key = "ANY /"
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

  tags = local.common_tags
}

resource "aws_lambda_permission" "api_gateway" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http.execution_arn}/*/*"
}
