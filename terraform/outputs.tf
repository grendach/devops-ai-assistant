output "api_url" {
  value       = aws_apigatewayv2_api.http.api_endpoint
  description = "Base URL of the HTTP API."
}

output "health_url" {
  value       = "${aws_apigatewayv2_api.http.api_endpoint}/health"
  description = "Health endpoint."
}

output "explain_url" {
  value       = "${aws_apigatewayv2_api.http.api_endpoint}/ai/explain"
  description = "AI explain endpoint."
}

output "github_review_url" {
  value       = "${aws_apigatewayv2_api.http.api_endpoint}/github/review"
  description = "GitHub pull request review endpoint."
}

output "github_token_secret_arn" {
  value       = aws_secretsmanager_secret.github_token.arn
  description = "Secret ARN where the GitHub token must be stored."
}

output "review_api_key_secret_arn" {
  value       = aws_secretsmanager_secret.review_api_key.arn
  description = "Secret ARN where the PR review endpoint API key must be stored."
}

output "history_table" {
  value       = aws_dynamodb_table.history.name
  description = "DynamoDB table with request metadata."
}
