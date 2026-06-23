#!/bin/bash
# deployment.sh
# This script helps deploy the correct traefik configuration for each environment
# Usage: ./deployment.sh staging   # or ./deployment.sh production

set -e

if [ $# -eq 0 ]; then
    echo "Usage: $0 <environment>"
    echo "  environment: staging or production"
    exit 1
fi

ENVIRONMENT=$1
STACK_NAME="${ENVIRONMENT}-infra"
DOCKER_COMPOSE_FILE="docker-stack.yml"

# Validate environment
if [ "$ENVIRONMENT" != "staging" ] && [ "$ENVIRONMENT" != "prod" ]; then
    echo "Error: Invalid environment '$ENVIRONMENT'"
    echo "Must be 'staging' or 'production'"
    exit 1
fi

if [ "$ENVIRONMENT" == "staging" ]; then
  DOCKER_COMPOSE_FILE="docker-stack.yml"
else
  DOCKER_COMPOSE_FILE="docker-stack-prod.yml"
fi


echo "=========================================="
echo "Deploying $ENVIRONMENT infrastructure"
echo "=========================================="

# Verify we're in the right directory
if [ ! -f "$DOCKER_COMPOSE_FILE" ]; then
    echo "Error: $DOCKER_COMPOSE_FILE not found in current directory"
    exit 1
fi

# Verify traefik config files exist
if [ ! -f "traefik/dynamic/traefik_routers_${ENVIRONMENT}.yml" ]; then
    echo "Error: traefik/dynamic/traefik_routers_${ENVIRONMENT}.yml not found"
    exit 1
fi

if [ ! -f "traefik/dynamic/traefik_middlewares.yml" ]; then
    echo "Error: traefik/dynamic/traefik_middlewares.yml not found"
    exit 1
fi

if [ ! -f "traefik/traefik.yml" ]; then
    echo "Error: traefik/traefik.yml not found"
    exit 1
fi

echo ""
echo "Configuration Files:"
echo "  - traefik/traefik.yml"
echo "  - traefik/dynamic/traefik_middlewares.yml"
echo "  - traefik/dynamic/traefik_routers_${ENVIRONMENT}.yml"
echo ""

# Set environment variable and deploy
export ENVIRONMENT=$ENVIRONMENT

echo "Deploying stack: $STACK_NAME"
echo "Environment: $ENVIRONMENT"
echo ""

docker stack deploy -c "$DOCKER_COMPOSE_FILE" "$STACK_NAME" --with-registry-auth

echo ""
echo "=========================================="
echo "Deployment Complete!"
echo "=========================================="
echo ""
echo "Stack Name: $STACK_NAME"
echo "Environment: $ENVIRONMENT"
echo ""
echo "To verify deployment:"
echo "  docker stack ls"
echo "  docker stack ps $STACK_NAME"
echo ""

# Print environment-specific URLs for reference
if [ "$ENVIRONMENT" = "staging" ]; then
    echo "Staging URLs (with 'staging.' prefix):"
    echo "  Dashboard:  https://staging.traefik.primecrib.app"
    echo "  RabbitMQ:   https://staging.rabbit.primecrib.app"
    echo "  MinIO:      https://staging.minio.primecrib.app"
    echo "  Grafana:    https://staging.grafana.primecrib.app"
    echo "  Vault:      https://staging.vault.primecrib.app"
    echo "  API:        https://staging.staging.api.primecrib.app"
    echo ""
    echo "TCP Services:"
    echo "  RabbitMQ AMQP: staging.rabbitmq.primecrib.app:5672"
    echo "  MinIO S3:      staging.minio.s3.primecrib.app:443"
else
    echo "Production URLs (no 'staging.' prefix):"
    echo "  Dashboard:  https://traefik.primecrib.app"
    echo "  RabbitMQ:   https://rabbit.primecrib.app"
    echo "  MinIO:      https://minio.primecrib.app"
    echo "  Grafana:    https://grafana.primecrib.app"
    echo "  Vault:      https://vault.primecrib.app"
    echo "  API:        https://api.primecrib.app"
    echo ""
    echo "TCP Services:"
    echo "  RabbitMQ AMQP: rabbitmq.primecrib.app:5672"
    echo "  MinIO S3:      minio.s3.primecrib.app:443"
fi

echo ""

