#!/usr/bin/env python3
"""
Symfizzy - OpenVINO Model Server OpenAI API Bridge

This service provides an OpenAI-compatible API endpoint that proxies requests
to an OpenVINO Model Server (OVMS) instance.
"""

import os
import json
import asyncio
from typing import Optional, List, Dict, Any, AsyncGenerator
from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import StreamingResponse, JSONResponse
from pydantic import BaseModel, Field
import httpx
import uvicorn

# Configuration from environment variables
OVMS_HOST = os.getenv("OVMS_HOST", "localhost")
OVMS_PORT = int(os.getenv("OVMS_PORT", "9000"))
OVMS_REST_PORT = int(os.getenv("OVMS_REST_PORT", "8001"))
SYMFIZZY_PORT = int(os.getenv("SYMFIZZY_PORT", "8080"))
MODEL_NAME = os.getenv("MODEL_NAME", "openai-model")

# OpenAI API models
class Message(BaseModel):
    role: str
    content: str
    name: Optional[str] = None

class ChatCompletionRequest(BaseModel):
    model: str
    messages: List[Message]
    temperature: Optional[float] = 0.7
    max_tokens: Optional[int] = None
    stream: Optional[bool] = False
    top_p: Optional[float] = 1.0
    frequency_penalty: Optional[float] = 0.0
    presence_penalty: Optional[float] = 0.0
    stop: Optional[List[str]] = None

class ChatCompletionChoice(BaseModel):
    index: int
    message: Message
    finish_reason: str

class ChatCompletionResponse(BaseModel):
    id: str
    object: str = "chat.completion"
    created: int
    model: str
    choices: List[ChatCompletionChoice]
    usage: Dict[str, int]

class CompletionChoice(BaseModel):
    text: str
    index: int
    logprobs: Optional[Any] = None
    finish_reason: str

class CompletionResponse(BaseModel):
    id: str
    object: str = "text_completion"
    created: int
    model: str
    choices: List[CompletionChoice]
    usage: Dict[str, int]

class ModelInfo(BaseModel):
    id: str
    object: str = "model"
    created: int
    owned_by: str = "symfizzy"

class ModelsResponse(BaseModel):
    object: str = "list"
    data: List[ModelInfo]

# OVMS client
class OVMSClient:
    def __init__(self, host: str, http_port: int, grpc_port: int):
        self.host = host
        self.http_port = http_port
        self.grpc_port = grpc_port
        self.base_url = f"http://{host}:{http_port}"
        self.client = httpx.AsyncClient(timeout=300.0)
    
    async def get_model_status(self, model_name: str) -> Dict[str, Any]:
        """Check if model is loaded in OVMS"""
        try:
            response = await self.client.get(
                f"{self.base_url}/v1/models/{model_name}"
            )
            response.raise_for_status()
            return response.json()
        except httpx.HTTPError as e:
            raise HTTPException(status_code=503, detail=f"OVMS error: {e}")
    
    async def infer(self, model_name: str, inputs: Dict[str, Any]) -> Dict[str, Any]:
        """Send inference request to OVMS"""
        try:
            response = await self.client.post(
                f"{self.base_url}/v1/models/{model_name}:predict",
                json=inputs
            )
            response.raise_for_status()
            return response.json()
        except httpx.HTTPError as e:
            raise HTTPException(status_code=503, detail=f"Inference error: {e}")
    
    async def close(self):
        await self.client.aclose()

# Global OVMS client
ovms_client: Optional[OVMSClient] = None

@asynccontextmanager
async def lifespan(app: FastAPI):
    """Manage application lifespan"""
    global ovms_client
    ovms_client = OVMSClient(OVMS_HOST, OVMS_REST_PORT, OVMS_PORT)
    
    # Wait for OVMS to be ready
    max_retries = 30
    for i in range(max_retries):
        try:
            await ovms_client.get_model_status(MODEL_NAME)
            print(f"Connected to OVMS at {OVMS_HOST}:{OVMS_REST_PORT}")
            break
        except Exception as e:
            if i == max_retries - 1:
                print(f"Warning: Could not connect to OVMS: {e}")
            await asyncio.sleep(1)
    
    yield
    
    if ovms_client:
        await ovms_client.close()

app = FastAPI(
    title="Symfizzy - OpenVINO Model Server OpenAI API",
    description="OpenAI-compatible API for OpenVINO Model Server",
    version="1.0.0",
    lifespan=lifespan
)

@app.get("/health")
async def health_check():
    """Health check endpoint"""
    return {"status": "healthy", "service": "symfizzy"}

@app.get("/v1/models", response_model=ModelsResponse)
async def list_models():
    """List available models (OpenAI-compatible)"""
    import time
    return ModelsResponse(
        data=[
            ModelInfo(
                id=MODEL_NAME,
                created=int(time.time()),
            )
        ]
    )

@app.get("/v1/models/{model_id}")
async def get_model(model_id: str):
    """Get model information"""
    import time
    if model_id != MODEL_NAME:
        raise HTTPException(status_code=404, detail="Model not found")
    
    return ModelInfo(
        id=model_id,
        created=int(time.time()),
    )

@app.post("/v1/chat/completions")
async def chat_completions(request: ChatCompletionRequest):
    """Chat completions endpoint (OpenAI-compatible)"""
    import time
    import uuid
    
    if not ovms_client:
        raise HTTPException(status_code=503, detail="OVMS client not initialized")
    
    # Convert OpenAI format to OVMS format
    # This is a simplified implementation - in production you'd need
    # proper tokenization and model-specific input formatting
    last_message = request.messages[-1].content if request.messages else ""
    
    # Prepare input for OVMS - adjust based on your specific model
    ovms_input = {
        "inputs": [
            {
                "name": "input",
                "shape": [1],
                "datatype": "BYTES",
                "data": [last_message]
            }
        ]
    }
    
    try:
        # Call OVMS for inference
        result = await ovms_client.infer(MODEL_NAME, ovms_input)
        
        # Extract response from OVMS output
        # Adjust based on your model's output format
        if "outputs" in result and len(result["outputs"]) > 0:
            output_data = result["outputs"][0].get("data", [""])
            if isinstance(output_data, list) and len(output_data) > 0:
                response_content = output_data[0] if isinstance(output_data[0], str) else str(output_data[0])
            else:
                response_content = str(output_data)
        else:
            response_content = json.dumps(result)
        
        # Format as OpenAI response
        response = ChatCompletionResponse(
            id=f"chatcmpl-{uuid.uuid4().hex[:8]}",
            created=int(time.time()),
            model=request.model,
            choices=[
                ChatCompletionChoice(
                    index=0,
                    message=Message(role="assistant", content=response_content),
                    finish_reason="stop"
                )
            ],
            usage={
                "prompt_tokens": len(last_message.split()),
                "completion_tokens": len(response_content.split()),
                "total_tokens": len(last_message.split()) + len(response_content.split())
            }
        )
        
        return response
        
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Inference failed: {str(e)}")

@app.post("/v1/completions")
async def completions(request: Request):
    """Legacy completions endpoint"""
    import time
    import uuid

    body = await request.json()
    prompt = body.get("prompt", "")
    model = body.get("model", MODEL_NAME)
    
    # Convert to chat format
    chat_request = ChatCompletionRequest(
        model=model,
        messages=[Message(role="user", content=prompt)],
        temperature=body.get("temperature", 0.7),
        max_tokens=body.get("max_tokens"),
        stream=body.get("stream", False)
    )
    
    chat_response = await chat_completions(chat_request)

    completion_text = ""
    if chat_response.choices:
        completion_text = chat_response.choices[0].message.content

    return CompletionResponse(
        id=f"cmpl-{uuid.uuid4().hex[:8]}",
        created=int(time.time()),
        model=model,
        choices=[
            CompletionChoice(
                text=completion_text,
                index=0,
                finish_reason="stop"
            )
        ],
        usage=chat_response.usage
    )

if __name__ == "__main__":
    uvicorn.run(
        "main:app",
        host="0.0.0.0",
        port=SYMFIZZY_PORT,
        log_level="info",
        reload=False
    )
