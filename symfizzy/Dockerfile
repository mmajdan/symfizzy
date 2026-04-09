# Symfizzy - OpenVINO Model Server for OpenAI API
# Dockerfile for the symfizzy service

FROM python:3.11-slim-bookworm

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    wget \
    ca-certificates \
    libgomp1 \
    libglib2.0-0 \
    libsm6 \
    libxext6 \
    libxrender-dev \
    libgomp1 \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Create necessary directories
RUN mkdir -p /app/symfizzy /app/models /app/ovms

# Copy requirements first for better caching
COPY symfizzy/requirements.txt /app/symfizzy/

# Install Python dependencies
RUN pip install --no-cache-dir -r /app/symfizzy/requirements.txt

# Download and install OVMS
ARG OVMS_VERSION=2024.3
ARG TARGETARCH

RUN echo "Building for architecture: ${TARGETARCH}" && \
    if [ "${TARGETARCH}" = "amd64" ]; then \
        OVMS_ARCH="linux64"; \
    elif [ "${TARGETARCH}" = "arm64" ]; then \
        OVMS_ARCH="arm64"; \
    else \
        OVMS_ARCH="linux64"; \
    fi && \
    echo "Downloading OVMS for ${OVMS_ARCH}" && \
    curl -L -o /tmp/ovms.tar.gz \
        "https://github.com/openvinotoolkit/model_server/releases/download/v${OVMS_VERSION}/ovms_${OVMS_ARCH}.tar.gz" && \
    tar -xzf /tmp/ovms.tar.gz -C /app/ovms && \
    rm /tmp/ovms.tar.gz && \
    chmod +x /app/ovms/ovms

# Copy application code
COPY symfizzy/main.py /app/symfizzy/
COPY symfizzy/start.sh /app/symfizzy/

# Make start script executable
RUN chmod +x /app/symfizzy/start.sh

# Create non-root user
RUN useradd -m -u 1000 symfizzy && \
    chown -R symfizzy:symfizzy /app

# Environment variables
ENV OVMS_HOST=localhost
ENV OVMS_PORT=9000
ENV OVMS_REST_PORT=8001
ENV SYMFIZZY_PORT=8080
ENV MODEL_NAME=openai-model
ENV PYTHONUNBUFFERED=1
ENV PYTHONDONTWRITEBYTECODE=1

# Expose ports
# 8080 - Symfizzy OpenAI API
# 9000 - OVMS gRPC
# 8001 - OVMS REST
EXPOSE 8080 9000 8001

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:8080/health || exit 1

# Switch to non-root user
USER symfizzy

# Set working directory for the app
WORKDIR /app/symfizzy

# Start the service
CMD ["./start.sh"]
