#!/bin/bash

# Initialize MySQL data directory if it doesn't exist
if [ ! -d "/data/mysql/mysql" ]; then
    echo "Initializing MySQL data directory..."
    mysqld --initialize-insecure --user=mysql --datadir=/data/mysql
    
    # Start MySQL temporarily to create database and user
    mysqld --user=mysql --datadir=/data/mysql --socket=/tmp/mysql.sock &
    MYSQL_PID=$!
    
    # Wait for MySQL to start
    sleep 10
    
    # Create database and user
    mysql --socket=/tmp/mysql.sock -e "CREATE DATABASE IF NOT EXISTS rag_flow;"
    mysql --socket=/tmp/mysql.sock -e "CREATE USER IF NOT EXISTS 'ragflow'@'%' IDENTIFIED BY 'infini_rag_flow';"
    mysql --socket=/tmp/mysql.sock -e "GRANT ALL PRIVILEGES ON rag_flow.* TO 'ragflow'@'%';"
    mysql --socket=/tmp/mysql.sock -e "FLUSH PRIVILEGES;"
    
    # Stop temporary MySQL
    kill $MYSQL_PID
    wait $MYSQL_PID
fi

# Initialize Elasticsearch data directory
if [ ! -d "/data/elasticsearch/nodes" ]; then
    echo "Initializing Elasticsearch data directory..."
    chown -R elasticsearch:elasticsearch /data/elasticsearch
fi

# Initialize Redis data directory
mkdir -p /data/redis
chown redis:redis /data/redis

# Initialize MinIO data directory
mkdir -p /data/minio
chown nobody:nogroup /data/minio

# Set vm.max_map_count for Elasticsearch (may not work in container)
echo "Setting vm.max_map_count..."
sysctl -w vm.max_map_count=262144 2>/dev/null || echo "Warning: Could not set vm.max_map_count. You may need to set this on the host system."

# Wait a moment for any initialization to complete
sleep 2

# Start supervisord
echo "Starting services with supervisord..."
exec /usr/bin/supervisord -c /etc/supervisor/conf.d/ragflow.conf