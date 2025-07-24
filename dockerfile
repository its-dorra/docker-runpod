# -------- Base CUDA Image --------
FROM nvidia/cuda:11.8.0-cudnn8-runtime-ubuntu22.04 AS base

ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=C.UTF-8
ENV PATH="/root/.local/bin:$PATH"

RUN apt-get update && apt-get install -y \
  python3 python3-pip python3-dev python-is-python3 \
  python3.10-venv git curl gnupg unzip build-essential \
  libjemalloc-dev wget ca-certificates gpg lsb-release \
  pkg-config libicu-dev gcc g++ make cmake \
  libffi-dev libssl-dev libxml2-dev libxslt1-dev \
  zlib1g-dev libbz2-dev libreadline-dev libsqlite3-dev \
  libncurses5-dev libncursesw5-dev xz-utils tk-dev \
  liblzma-dev nginx supervisor \
  default-mysql-server redis-server openjdk-17-jre-headless \
  && apt-get clean && rm -rf /var/lib/apt/lists/*

# -------- Node.js Builder Stage --------
FROM node:20 AS frontend

WORKDIR /frontend
COPY web/ .
RUN npm install && npm run build

# -------- Final App Layer --------
FROM base AS final

WORKDIR /app

# Install pipx, uv, and pre-commit
RUN pip install --no-cache-dir pipx && pipx ensurepath && \
    pipx install uv && pipx install pre-commit

# Install Elasticsearch
RUN curl -L -o elasticsearch-8.11.3-amd64.deb https://artifacts.elastic.co/downloads/elasticsearch/elasticsearch-8.11.3-amd64.deb && \
    dpkg -i elasticsearch-8.11.3-amd64.deb && \
    rm elasticsearch-8.11.3-amd64.deb

# Install MinIO
RUN curl -fsSL https://dl.min.io/server/minio/release/linux-amd64/minio -o /usr/local/bin/minio && \
    chmod +x /usr/local/bin/minio && \
    curl -fsSL https://dl.min.io/client/mc/release/linux-amd64/mc -o /usr/local/bin/mc && \
    chmod +x /usr/local/bin/mc

# Copy app source
COPY --from=frontend /frontend/dist /app/web/dist
COPY . /app

# Install Python dependencies
RUN pipx run uv sync --python 3.10 --all-extras --no-cache && \
    pipx run uv run download_deps.py && \
    pre-commit install && \
    rm -rf /root/.cache/uv /tmp/* && \
    find /root/.local -name "*.pyc" -delete && \
    find /root/.local -name "__pycache__" -type d -exec rm -rf {} + || true

# Create required directories and permissions
RUN mkdir -p /data/minio /data/mysql /data/elasticsearch /data/redis /var/log/ragflow && \
    chown -R elasticsearch:elasticsearch /data/elasticsearch && \
    chown -R mysql:mysql /data/mysql

# Configure services
RUN echo 'vm.max_map_count=262144' >> /etc/sysctl.conf && \
    echo "xpack.security.enabled: false" >> /etc/elasticsearch/elasticsearch.yml && \
    echo "network.host: 0.0.0.0" >> /etc/elasticsearch/elasticsearch.yml && \
    echo "discovery.type: single-node" >> /etc/elasticsearch/elasticsearch.yml && \
    echo "path.data: /data/elasticsearch" >> /etc/elasticsearch/elasticsearch.yml && \
    echo "bootstrap.memory_lock: false" >> /etc/elasticsearch/elasticsearch.yml && \
    echo "bind 0.0.0.0" >> /etc/redis/redis.conf && \
    echo "requirepass infini_rag_flow" >> /etc/redis/redis.conf && \
    echo "dir /data/redis" >> /etc/redis/redis.conf && \
    echo "[mysqld]" >> /etc/mysql/mysql.conf.d/ragflow.cnf && \
    echo "bind-address = 0.0.0.0" >> /etc/mysql/mysql.conf.d/ragflow.cnf && \
    echo "datadir = /data/mysql" >> /etc/mysql/mysql.conf.d/ragflow.cnf && \
    echo "max_connections = 1000" >> /etc/mysql/mysql.conf.d/ragflow.cnf

# Copy configuration and init files
COPY supervisord.conf /etc/supervisor/conf.d/ragflow.conf
COPY service_conf.yaml /app/conf/service_conf.yaml
COPY init.sh /app/init.sh
COPY nginx.conf /etc/nginx/sites-available/default

RUN chmod +x /app/init.sh

# Clean everything up
RUN apt-get autoremove -y && apt-get autoclean && \
    rm -rf /root/.cache /var/lib/apt/lists/* /tmp/* /var/tmp/* && \
    find / -name "*.pyc" -delete 2>/dev/null || true && \
    find / -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true

EXPOSE 9380 9000 9001 9200 6379 3306 80

CMD ["/app/init.sh"]
