#!/bin/bash
# Symfizzy startup script
# Sets up Python environment and starts the OpenVINO Model Server

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_DIR="${SCRIPT_DIR}/venv"
OVMS_DIR="${SCRIPT_DIR}/ovms"
MODELS_DIR="${MODELS_DIR:-/app/models}"

# Configuration
OVMS_VERSION="${OVMS_VERSION:-2024.3}"
OVMS_PORT="${OVMS_PORT:-9000}"
OVMS_REST_PORT="${OVMS_REST_PORT:-8001}"
SYMFIZZY_PORT="${SYMFIZZY_PORT:-8080}"
MODEL_NAME="${MODEL_NAME:-openai-model}"

echo "=== Symfizzy Service Startup ==="
echo "OVMS Version: ${OVMS_VERSION}"
echo "OVMS gRPC Port: ${OVMS_PORT}"
echo "OVMS REST Port: ${OVMS_REST_PORT}"
echo "Symfizzy Port: ${SYMFIZZY_PORT}"
echo "Model Name: ${MODEL_NAME}"
echo ""

# Create directories
mkdir -p "${MODELS_DIR}"
mkdir -p "${OVMS_DIR}"

# Step 1: Create Python virtual environment
echo "[1/3] Setting up Python virtual environment..."
if [ ! -d "${VENV_DIR}" ]; then
    python3 -m venv "${VENV_DIR}"
    echo "Virtual environment created at ${VENV_DIR}"
else
    echo "Virtual environment already exists"
fi

# Activate virtual environment
source "${VENV_DIR}/bin/activate"

# Step 2: Install Python dependencies
echo ""
echo "[2/3] Installing Python dependencies..."
pip install --upgrade pip
pip install -r "${SCRIPT_DIR}/requirements.txt"
echo "Python dependencies installed"

# Step 3: Download OVMS server if not present
echo ""
echo "[3/3] Setting up OVMS server..."

if [ ! -f "${OVMS_DIR}/ovms" ]; then
    echo "Downloading OVMS server..."
    
    # Detect architecture
    ARCH=$(uname -m)
    if [ "$ARCH" = "x86_64" ]; then
        OVMS_ARCH="linux64"
    elif [ "$ARCH" = "aarch64" ]; then
        OVMS_ARCH="arm64"
    else
        echo "Unsupported architecture: $ARCH"
        exit 1
    fi
    
    # Download OVMS
    OVMS_URL="https://github.com/openvinotoolkit/model_server/releases/download/v${OVMS_VERSION}/ovms_${OVMS_ARCH}.tar.gz"
    
    cd "${OVMS_DIR}"
    curl -L -o ovms.tar.gz "${OVMS_URL}"
    tar -xzf ovms.tar.gz
    rm ovms.tar.gz
    cd "${SCRIPT_DIR}"
    
    echo "OVMS server downloaded"
else
    echo "OVMS server already exists"
fi

# Create OVMS config
cat > "${OVMS_DIR}/config.json" << EOF
{
    "model_config_list": [
        {
            "config": {
                "name": "${MODEL_NAME}",
                "base_path": "${MODELS_DIR}/${MODEL_NAME}",
                "shape": "auto",
                "target_device": "CPU"
            }
        }
    ]
}
EOF

echo ""
echo "=== Starting Services ==="
echo ""

# Start OVMS in background
echo "Starting OVMS server..."
"${OVMS_DIR}/ovms" \
    --config_path "${OVMS_DIR}/config.json" \
    --port ${OVMS_PORT} \
    --rest_port ${OVMS_REST_PORT} \
    --log_level INFO &

OVMS_PID=$!
echo "OVMS started with PID: ${OVMS_PID}"

# Wait for OVMS to be ready
echo "Waiting for OVMS to be ready..."
sleep 5

# Check if OVMS is responding
for i in {1..30}; do
    if curl -s "http://localhost:${OVMS_REST_PORT}/v1/models" > /dev/null 2>&1; then
        echo "OVMS is ready!"
        break
    fi
    if [ $i -eq 30 ]; then
        echo "Warning: OVMS did not start properly"
        kill ${OVMS_PID} 2>/dev/null || true
        exit 1
    fi
    echo -n "."
    sleep 1
done

echo ""
echo "Starting Symfizzy OpenAI API bridge..."

# Export environment variables for main.py
export OVMS_HOST="localhost"
export OVMS_PORT="${OVMS_PORT}"
export OVMS_REST_PORT="${OVMS_REST_PORT}"
export SYMFIZZY_PORT="${SYMFIZZY_PORT}"
export MODEL_NAME="${MODEL_NAME}"

# Start Symfizzy
exec python "${SCRIPT_DIR}/main.py"
