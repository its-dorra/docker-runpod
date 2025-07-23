FROM nvidia/cuda:11.8.0-cudnn8-runtime-ubuntu22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=C.UTF-8
ENV PATH="/root/.local/bin:$PATH"

# Install system dependencies
RUN apt-get update && apt-get install -y \
    python3 python3-pip python3-dev python-is-python3 \
    python3.10-venv \
    git curl gnupg unzip build-essential \
    default-mysql-server redis-server openjdk-17-jre-headless \
    libjemalloc-dev wget ca-certificates supervisor gpg lsb-release \
 && rm -rf /var/lib/apt/lists/*

# ---------------------------------------------
# Install Node.js v20 (from NodeSource)
# ---------------------------------------------
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && \
    apt-get install -y nodejs && \
    node -v && npm -v

# Install pipx and global tools
RUN pip install pipx && pipx ensurepath && \
    pipx install uv && pipx install pre-commit

# Elasticsearch: add GPG key and install
# Install Elasticsearch 8.11.3 from .deb
RUN curl -L -o elasticsearch-8.11.3-amd64.deb https://artifacts.elastic.co/downloads/elasticsearch/elasticsearch-8.11.3-amd64.deb && \
    dpkg -i elasticsearch-8.11.3-amd64.deb && \
    rm elasticsearch-8.11.3-amd64.deb

# MinIO client + server
RUN curl -fsSL https://dl.min.io/server/minio/release/linux-amd64/minio -o /usr/local/bin/minio && \
    chmod +x /usr/local/bin/minio && \
    curl -fsSL https://dl.min.io/client/mc/release/linux-amd64/mc -o /usr/local/bin/mc && \
    chmod +x /usr/local/bin/mc

# Set vm.max_map_count for Elasticsearch
RUN echo 'vm.max_map_count=262144' >> /etc/sysctl.conf

# Clone RAGFlow and install Python deps
WORKDIR /app
RUN git clone https://github.com/infiniflow/ragflow.git . && \
    pipx run uv sync --python 3.10 --all-extras && \
    pipx run uv run download_deps.py && \
    pre-commit install

# Install frontend dependencies
WORKDIR /app/web
RUN npm install

# Copy configuration
WORKDIR /app
COPY supervisord.conf /etc/supervisor/conf.d/ragflow.conf
COPY service_conf.yaml.template /app/docker/service_conf.yaml.template

# Expose all required ports
EXPOSE 9380 9000 9001 9200 6379 3306 3000

# Run everything with supervisord
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/ragflow.conf"]
