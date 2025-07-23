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
    nginx \
    pkg-config libicu-dev \
    gcc g++ make cmake \
    libffi-dev libssl-dev \
    libxml2-dev libxslt1-dev \
    zlib1g-dev libbz2-dev \
    libreadline-dev libsqlite3-dev \
    libncurses5-dev libncursesw5-dev \
    xz-utils tk-dev \
    liblzma-dev \
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

# Install Elasticsearch 8.11.3 from .deb
RUN curl -L -o elasticsearch-8.11.3-amd64.deb https://artifacts.elastic.co/downloads/elasticsearch/elasticsearch-8.11.3-amd64.deb && \
    dpkg -i elasticsearch-8.11.3-amd64.deb && \
    rm elasticsearch-8.11.3-amd64.deb

# MinIO client + server
RUN curl -fsSL https://dl.min.io/server/minio/release/linux-amd64/minio -o /usr/local/bin/minio && \
    chmod +x /usr/local/bin/minio && \
    curl -fsSL https://dl.min.io/client/mc/release/linux-amd64/mc -o /usr/local/bin/mc && \
    chmod +x /usr/local/bin/mc

# Create data directories
RUN mkdir -p /data/minio /data/mysql /data/elasticsearch /data/redis /var/log/ragflow && \
    chown -R elasticsearch:elasticsearch /data/elasticsearch && \
    chown -R mysql:mysql /data/mysql

# Set vm.max_map_count for Elasticsearch (this won't work in container, needs to be set on host)
RUN echo 'vm.max_map_count=262144' >> /etc/sysctl.conf

# Clone RAGFlow and install Python deps
WORKDIR /app
RUN git clone https://github.com/infiniflow/ragflow.git . && \
    pipx run uv sync --python 3.10 --all-extras && \
    pipx run uv run download_deps.py && \
    pre-commit install

# Install and build frontend
WORKDIR /app/web
RUN npm install && npm run build

# Setup MySQL
WORKDIR /app
RUN service mysql start && \
    mysql -e "CREATE DATABASE IF NOT EXISTS rag_flow;" && \
    mysql -e "CREATE USER IF NOT EXISTS 'ragflow'@'localhost' IDENTIFIED BY 'infini_rag_flow';" && \
    mysql -e "GRANT ALL PRIVILEGES ON rag_flow.* TO 'ragflow'@'localhost';" && \
    mysql -e "FLUSH PRIVILEGES;" && \
    service mysql stop

# Configure Elasticsearch
RUN echo "xpack.security.enabled: false" >> /etc/elasticsearch/elasticsearch.yml && \
    echo "network.host: 0.0.0.0" >> /etc/elasticsearch/elasticsearch.yml && \
    echo "discovery.type: single-node" >> /etc/elasticsearch/elasticsearch.yml && \
    echo "path.data: /data/elasticsearch" >> /etc/elasticsearch/elasticsearch.yml && \
    echo "bootstrap.memory_lock: false" >> /etc/elasticsearch/elasticsearch.yml

# Configure Redis
RUN echo "bind 0.0.0.0" >> /etc/redis/redis.conf && \
    echo "requirepass infini_rag_flow" >> /etc/redis/redis.conf && \
    echo "dir /data/redis" >> /etc/redis/redis.conf

# Configure MySQL
RUN echo "[mysqld]" >> /etc/mysql/mysql.conf.d/ragflow.cnf && \
    echo "bind-address = 0.0.0.0" >> /etc/mysql/mysql.conf.d/ragflow.cnf && \
    echo "datadir = /data/mysql" >> /etc/mysql/mysql.conf.d/ragflow.cnf && \
    echo "max_connections = 1000" >> /etc/mysql/mysql.conf.d/ragflow.cnf

# Copy configuration files
COPY supervisord.conf /etc/supervisor/conf.d/ragflow.conf
COPY service_conf.yaml /app/conf/service_conf.yaml
COPY init.sh /app/init.sh
COPY nginx.conf /etc/nginx/sites-available/default

RUN chmod +x /app/init.sh

# Expose all required ports
EXPOSE 9380 9000 9001 9200 6379 3306 80

# Initialize and run
CMD ["/app/init.sh"]