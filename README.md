# DevOps AI Assistant on Amazon Bedrock

A small learning project for building a real DevOps AI Assistant on AWS.

It provides a FastAPI backend deployed as AWS Lambda behind API Gateway. The backend calls Amazon Bedrock using the Converse API and stores request metadata in DynamoDB.

## Features

- `GET /health` health check
- `POST /ai/explain` DevOps issue explanation endpoint
- `POST /github/review` reviews an allowed GitHub PR and publishes a review comment
- Amazon Bedrock integration with Amazon Nova Lite by default
- DynamoDB history table for request metadata and token usage
- Terraform deployment
- Cheap serverless architecture

## Architecture

```text
Client / curl / frontend
  -> API Gateway HTTP API
  -> Lambda Python 3.12 + FastAPI + Mangum
  -> Amazon Bedrock Runtime
  -> DynamoDB history table
  -> CloudWatch Logs
```

## Prerequisites

Install locally:

- AWS CLI configured with your AWS account
- Terraform >= 1.6
- Python 3.11+ or 3.12
- zip

You also need Bedrock model access enabled. The defaults invoke the EU Nova Lite
cross-Region inference profile from `eu-west-1` using
`eu.amazon.nova-lite-v1:0`.

## Important Bedrock note

In some AWS accounts/regions, you must manually enable access to Bedrock models in the AWS Console:

`Amazon Bedrock -> Model access -> Enable model access`

Amazon-owned Nova models are usually easiest for a first private project.

## Terraform remote state

Terraform state is configured to use this S3 backend:

```hcl
bucket = "tf-state-devops-ai-assistant-432180781943-eu-west-1-an"
key    = "devops-ai-assistant/terraform.tfstate"
region = "eu-west-1"
```

The AWS provider is restricted with `allowed_account_ids = ["432180781943"]` so Terraform will fail if your credentials point to the wrong AWS account.

The S3 bucket must already exist before `terraform init`.

## Deploy

From the project root:

```bash
./scripts/package_lambda.sh
cd terraform
terraform init
terraform plan
terraform apply
```

After apply, Terraform prints:

```text
health_url
explain_url
github_review_url
```

## Configure GitHub PR reviews

The allowed repository defaults to `grendach/expense-tracker`. Create a
fine-grained GitHub personal access token limited to that repository with:

- **Contents: Read-only**
- **Pull requests: Read and write**

Terraform creates empty Secrets Manager containers, but never stores either
secret value in Terraform state. After the first `terraform apply`, populate
them from your terminal:

```bash
read -s GITHUB_TOKEN
aws secretsmanager put-secret-value \
  --secret-id "$(terraform output -raw github_token_secret_arn)" \
  --secret-string "$GITHUB_TOKEN"
unset GITHUB_TOKEN

REVIEW_API_KEY="$(openssl rand -hex 32)"
aws secretsmanager put-secret-value \
  --secret-id "$(terraform output -raw review_api_key_secret_arn)" \
  --secret-string "$REVIEW_API_KEY"
```

Keep `REVIEW_API_KEY` available for the test below. It protects the public API
endpoint from unauthorized review submissions.

### Review and comment on a pull request

Replace `123` with an open pull request number:

```bash
curl -X POST "$(terraform output -raw github_review_url)" \
  -H "Content-Type: application/json" \
  -H "X-Review-Key: $REVIEW_API_KEY" \
  -d '{
    "repository": "grendach/expense-tracker",
    "pull_number": 123,
    "max_tokens": 1200
  }'
```

The agent fetches the PR and its changed-file patches, asks Bedrock for a code
review, and publishes the result as a GitHub PR review with event `COMMENT`.
It cannot access repositories outside `allowed_github_repos`.

## Test health

```bash
curl "$(terraform output -raw health_url)"
```

Expected response:

```json
{
  "status": "ok",
  "app": "devops-ai-assistant",
  "model_id": "eu.amazon.nova-lite-v1:0",
  "bedrock_region": "eu-west-1"
}
```

## Test AI endpoint

```bash
curl -X POST "$(terraform output -raw explain_url)" \
  -H "Content-Type: application/json" \
  -d '{
    "task_type": "kubernetes",
    "input": "Pod is in CrashLoopBackOff. kubectl logs shows: connection refused to postgres:5432. Readiness probe fails.",
    "max_tokens": 800,
    "temperature": 0.2
  }'
```

## Request body

```json
{
  "task_type": "kubernetes",
  "input": "Paste error, logs, manifest, terraform output, or pipeline failure here",
  "max_tokens": 800,
  "temperature": 0.2
}
```

Supported `task_type` values:

- `kubernetes`
- `terraform`
- `aws`
- `logs`
- `ci_cd`
- `general`

## Terraform variables

You can override variables in `terraform/terraform.tfvars`:

```hcl
project_name      = "devops-ai-assistant"
aws_region        = "eu-west-1"
bedrock_region    = "eu-west-1"
bedrock_model_id  = "eu.amazon.nova-lite-v1:0"
allowed_origins   = "*"
allowed_github_repos = ["grendach/expense-tracker"]
```

For production, replace `allowed_origins = "*"` with your real frontend domain.

## Cost control

This project is designed to be cheap:

- Lambda: pay per request
- API Gateway HTTP API: pay per request
- DynamoDB: on-demand billing
- Bedrock: pay per input/output token

Avoid adding OpenSearch Serverless for RAG until you are ready, because it can add a higher baseline cost.

## Destroy

```bash
cd terraform
terraform destroy
```

## Next improvements

Good next features:

1. Add a simple React/Vite frontend.
2. Add authentication with Cognito or your own JWT.
3. Add request history viewer from DynamoDB.
4. Add Bedrock Guardrails.
5. Add RAG with Bedrock Knowledge Bases and S3 documents.
6. Add GitHub Actions deployment.
7. Add Slack or email integration for incident summaries.

## Security notes

Do not paste secrets, private keys, AWS credentials, access tokens, or production customer data into the assistant.

For real production usage:

- restrict CORS
- add authentication
- add WAF/rate limiting
- use IAM least privilege by model ARN where possible
- add CloudWatch alarms
- consider Bedrock Guardrails
