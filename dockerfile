# syntax=docker/dockerfile:1.4
FROM nvidia/cuda:11.8.0-cudnn8-runtime-ubuntu22.04

ENV DEBIAN_FRONTEND=noninteractive \
    TZ=Etc/UTC \
    VM_MAX_MAP_COUNT=262144 \
    STACK_VERSION=8.11.3 \
    MYSQL_ROOT_PASSWORD=secret \
    MYSQL_DATABASE=rag_flow \
    MYSQL_USER=ragflow \
    MYSQL_PASSWORD=ragpass \
    REDIS_PASSWORD="" \
    ELASTIC_PASSWORD=elasticpass \
    MINIO_USER=minio \
    MINIO_PASSWORD=minio123 \
    SVR_HTTP_PORT=9380 \
    TIMEZONE=UTC

RUN apt-get update && apt-get install -y \
    python3 python3-pip python3-dev git curl gnupg \
    apt-transport-https build-essential supervisor \
    default-mysql-server redis-server openjdk-17-jre-headless unzip ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && ln -s /usr/bin/python3 /usr/bin/python \
    && pip install --upgrade pip

# Install Elasticsearch
RUN curl -fsSL https://artifacts.elastic.co/GPG-KEY-elasticsearch | apt-key add - \
 && echo "deb https://artifacts.elastic.co/packages/${STACK_VERSION}/apt stable main" > /etc/apt/sources.list.d/elastic-${STACK_VERSION}.list \
 && apt-get update && apt-get install -y elasticsearch \
 && rm -rf /var/lib/apt/lists/*

# Install MinIO
RUN curl -fsSL https://dl.min.io/server/minio/release/linux-amd64/minio -o /usr/local/bin/minio \
 && chmod +x /usr/local/bin/minio \
 && curl -fsSL https://dl.min.io/client/mc/release/linux-amd64/mc -o /usr/local/bin/mc \
 && chmod +x /usr/local/bin/mc

# Clone and install RAGFlow
WORKDIR /app
RUN git clone https://github.com/infiniflow/ragflow.git . \
 && pip install -r requirements.txt \
 && python3 download_deps.py

# Copy supervisor config and service template
COPY supervisord.conf /etc/supervisor/conf.d/ragflow.conf
COPY service_conf.yaml.template /app/docker/service_conf.yaml.template

# Ensure ES maps
RUN echo "vm.max_map_count=${VM_MAX_MAP_COUNT}" >> /etc/sysctl.conf

EXPOSE 80 9380 3306 6379 9200 9000

CMD ["supervisord", "-n", "-c", "/etc/supervisor/conf.d/ragflow.conf"]
