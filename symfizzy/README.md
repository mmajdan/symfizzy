# Symfizzy

OpenVINO Model Server (OVMS) service with OpenAI API compatibility for Fizzy.

## Overview

Symfizzy provides an OpenAI-compatible API endpoint that proxies requests to an OpenVINO Model Server instance. This allows you to serve AI models using OpenVINO while maintaining compatibility with the OpenAI API specification.

## Architecture

- **OVMS (OpenVINO Model Server)**: Serves optimized AI models via gRPC and REST APIs
- **Symfizzy Bridge**: FastAPI-based proxy that translates OpenAI API requests to OVMS format
- **Models**: Stored in `/app/models/` directory

## Endpoints

- `GET /health` - Health check
- `GET /v1/models` - List available models
- `GET /v1/models/{model_id}` - Get model information
- `POST /v1/chat/completions` - Chat completions (OpenAI-compatible)
- `POST /v1/completions` - Legacy completions (OpenAI-compatible)

## Environment Variables

- `OVMS_HOST` - OVMS host (default: localhost)
- `OVMS_PORT` - OVMS gRPC port (default: 9000)
- `OVMS_REST_PORT` - OVMS REST port (default: 8001)
- `SYMFIZZY_PORT` - Symfizzy API port (default: 8080)
- `MODEL_NAME` - Default model name (default: openai-model)

## Usage

### Local Development

```bash
cd symfizzy
./start.sh
```

### Docker

```bash
docker build -f symfizzy/Dockerfile -t symfizzy .
docker run -p 8080:8080 -p 9000:9000 -p 8001:8001 symfizzy
```

### Deploy with Kamal

The service is configured in `config/deploy.yml` as the `symfizzy` role.

## Model Setup

Place your OpenVINO IR format models in the models directory:

```
models/
└── openai-model/
    ├── model.xml
    ├── model.bin
    └── mapping_config.json
```

## Development

### Setup Virtual Environment

```bash
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

### Run Locally

```bash
export OVMS_HOST=localhost
export OVMS_PORT=9000
export MODEL_NAME=your-model
python main.py
```

## License

Same as Fizzy project
