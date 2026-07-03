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

output "history_table" {
  value       = aws_dynamodb_table.history.name
  description = "DynamoDB table with request metadata."
}
