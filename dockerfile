FROM nvidia/cuda:11.8.0-cudnn8-runtime-ubuntu22.04

ENV DEBIAN_FRONTEND=noninteractive

# Install system dependencies
RUN apt-get update && apt-get install -y \
    python3 python3-pip python3-dev git curl gnupg2 gnupg ca-certificates \
    apt-transport-https build-essential supervisor gettext lsb-release \
    software-properties-common default-mysql-server redis-server \
    openjdk-17-jre-headless unzip wget dirmngr \
    && rm -rf /var/lib/apt/lists/* \
    && ln -s /usr/bin/python3 /usr/bin/python \
    && pip install --upgrade pip

# Install Elasticsearch with proper GPG handling
RUN mkdir -p /etc/apt/keyrings && \
    curl -fsSL https://artifacts.elastic.co/GPG-KEY-elasticsearch \
    | gpg --dearmor -o /etc/apt/keyrings/elasticsearch.gpg && \
    echo "deb [signed-by=/etc/apt/keyrings/elasticsearch.gpg] https://artifacts.elastic.co/packages/8.x/apt stable main" \
    | tee /etc/apt/sources.list.d/elastic-8.x.list && \
    apt-get update && \
    apt-get install -y elasticsearch && \
    rm -rf /var/lib/apt/lists/*

# Install MinIO (server + client)
RUN curl -fsSL https://dl.min.io/server/minio/release/linux-amd64/minio -o /usr/local/bin/minio \
    && chmod +x /usr/local/bin/minio \
    && curl -fsSL https://dl.min.io/client/mc/release/linux-amd64/mc -o /usr/local/bin/mc \
    && chmod +x /usr/local/bin/mc

# Set workdir
WORKDIR /app

# Clone RAGFlow (or COPY your code here if local)
RUN git clone https://github.com/infiniflow/ragflow.git . && pip install -r requirements.txt

# Copy configs
COPY supervisord.conf /etc/supervisor/conf.d/ragflow.conf
COPY service_conf.yaml.template /app/docker/service_conf.yaml.template

# Render final service config from template (optional at build time)
RUN envsubst < /app/docker/service_conf.yaml.template > /app/service_conf.yaml || true

# Expose RAGFlow port
EXPOSE 9380

# Start all services
CMD ["/usr/bin/supervisord", "-n"]
