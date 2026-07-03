import json
import os
import time
import uuid
from decimal import Decimal
from typing import Optional, Literal

import boto3
from botocore.exceptions import ClientError
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from mangum import Mangum
from pydantic import BaseModel, Field

APP_NAME = os.getenv("APP_NAME", "devops-ai-assistant")
AWS_REGION = os.getenv("AWS_REGION", os.getenv("AWS_DEFAULT_REGION", "eu-west-1"))
BEDROCK_REGION = os.getenv("BEDROCK_REGION", AWS_REGION)
MODEL_ID = os.getenv("BEDROCK_MODEL_ID", "eu.amazon.nova-lite-v1:0")
HISTORY_TABLE = os.getenv("HISTORY_TABLE", "")
ALLOWED_ORIGINS = [o.strip() for o in os.getenv("ALLOWED_ORIGINS", "*").split(",") if o.strip()]

bedrock = boto3.client("bedrock-runtime", region_name=BEDROCK_REGION)
dynamodb = boto3.resource("dynamodb", region_name=AWS_REGION) if HISTORY_TABLE else None

app = FastAPI(title="DevOps AI Assistant", version="0.1.0")
app.add_middleware(
    CORSMiddleware,
    allow_origins=ALLOWED_ORIGINS,
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)

class ExplainRequest(BaseModel):
    task_type: Literal["kubernetes", "terraform", "aws", "logs", "ci_cd", "general"] = "general"
    input: str = Field(..., min_length=5, max_length=12000)
    max_tokens: int = Field(800, ge=100, le=2000)
    temperature: float = Field(0.2, ge=0.0, le=1.0)

class ExplainResponse(BaseModel):
    request_id: str
    model_id: str
    answer: str
    latency_ms: int

SYSTEM_PROMPT = """
You are a senior DevOps, AWS, Kubernetes, Terraform and incident-response assistant.
Your response must be practical, concise, and safe.
Use this structure:
1. Summary
2. Most likely root cause
3. How to verify
4. Suggested fix
5. Commands or config examples, if useful
Do not invent facts. If the input is insufficient, say what is missing.
Never ask the user to paste secrets, credentials, tokens, or private keys.
""".strip()

TASK_CONTEXT = {
    "kubernetes": "The user pasted Kubernetes output, errors, manifests, or logs. Focus on pods, services, ingress, probes, scheduling, events, DNS, networking, resources, and rollout issues.",
    "terraform": "The user pasted Terraform code, plan, apply output, or errors. Focus on provider config, state, dependencies, IAM, module design, security, and safe apply steps.",
    "aws": "The user pasted AWS architecture, CLI output, CloudWatch logs, or service errors. Focus on AWS root cause, IAM, networking, limits, observability, and cost-aware fixes.",
    "logs": "The user pasted application or infrastructure logs. Extract symptoms, timeline, likely cause, and next debugging steps.",
    "ci_cd": "The user pasted CI/CD pipeline output. Focus on failed step, environment, credentials, artifacts, dependency/cache, and reproducible fix.",
    "general": "The user pasted a general DevOps question or issue. Give a practical senior DevOps answer.",
}

def _store_history(item: dict) -> None:
    if not HISTORY_TABLE or not dynamodb:
        return
    table = dynamodb.Table(HISTORY_TABLE)
    item = {k: (Decimal(str(v)) if isinstance(v, float) else v) for k, v in item.items()}
    table.put_item(Item=item)

@app.get("/health")
def health():
    return {"status": "ok", "app": APP_NAME, "model_id": MODEL_ID, "bedrock_region": BEDROCK_REGION}

@app.post("/ai/explain", response_model=ExplainResponse)
def explain(req: ExplainRequest):
    request_id = str(uuid.uuid4())
    started = time.time()
    user_prompt = f"""
Task type: {req.task_type}
Context: {TASK_CONTEXT[req.task_type]}

Input:
{req.input}
""".strip()

    try:
        response = bedrock.converse(
            modelId=MODEL_ID,
            system=[{"text": SYSTEM_PROMPT}],
            messages=[{"role": "user", "content": [{"text": user_prompt}]}],
            inferenceConfig={
                "maxTokens": req.max_tokens,
                "temperature": req.temperature,
                "topP": 0.9,
            },
        )
        answer = response["output"]["message"]["content"][0]["text"]
        latency_ms = int((time.time() - started) * 1000)
        usage = response.get("usage", {})
        _store_history({
            "request_id": request_id,
            "created_at": int(time.time()),
            "task_type": req.task_type,
            "model_id": MODEL_ID,
            "bedrock_region": BEDROCK_REGION,
            "latency_ms": latency_ms,
            "input_chars": len(req.input),
            "input_tokens": usage.get("inputTokens", 0),
            "output_tokens": usage.get("outputTokens", 0),
        })
        return ExplainResponse(request_id=request_id, model_id=MODEL_ID, answer=answer, latency_ms=latency_ms)
    except ClientError as e:
        code = e.response.get("Error", {}).get("Code", "ClientError")
        msg = e.response.get("Error", {}).get("Message", str(e))
        raise HTTPException(status_code=502, detail=f"Bedrock error {code}: {msg}")
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

handler = Mangum(app)
