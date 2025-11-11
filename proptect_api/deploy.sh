#!/bin/bash
set -e

STACK_NAME=infra
COMPOSE_FILE=docker-stack-api.yml

echo ">>> Deploying $STACK_NAME to Swarm..."
docker stack deploy -c $COMPOSE_FILE $STACK_NAME

echo ">>> Waiting for services to stabilize..."
sleep 10

if ! docker service ls --filter name=${STACK_NAME}_proptech-core-service --format '{{.Replicas}}' | grep -q '1/1'; then
  echo "⚠️ Deployment failed, rolling back..."
  docker stack rm $STACK_NAME
  sleep 10
  docker stack deploy -c $COMPOSE_FILE $STACK_NAME
else
  echo "✅ Deployment successful!"
fi

