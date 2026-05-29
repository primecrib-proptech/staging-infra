# Docker Stack Configuration Examples
# This file shows how to implement environment-specific traefik routing

# ============================================================================
# APPROACH 1: Using environment variable substitution (RECOMMENDED)
# ============================================================================
# This approach uses Docker Compose variable substitution to mount the correct
# router config based on an environment variable.
#
# Usage:
#   ENVIRONMENT=staging docker stack deploy -c docker-stack.yml staging-infra
#   ENVIRONMENT=production docker stack deploy -c docker-stack.yml prod-infra
#
# In your docker-stack.yml traefik service section:
#
# traefik:
#   image: traefik:v3.6.13
#   volumes:
#     - /var/run/docker.sock:/var/run/docker.sock:ro
#     - ./traefik/traefik.yml:/etc/traefik/traefik.yml:ro
#     - ./traefik/dynamic/traefik_middlewares.yml:/etc/traefik/dynamic/traefik_middlewares.yml:ro
#     - ./traefik/dynamic/traefik_routers_${ENVIRONMENT:-staging}.yml:/etc/traefik/dynamic/traefik_routers.yml:ro
#     - traefik_letsencrypt:/letsencrypt
#     - traefik_logs:/var/log/traefik


# ============================================================================
# APPROACH 2: Manual file management
# ============================================================================
# This approach requires you to manually delete the unwanted config file
# before deploying.
#
# For Staging Deployment:
#   rm -f traefik/dynamic/traefik_routers_production.yml
#   docker stack deploy -c docker-stack.yml staging-infra
#
# For Production Deployment:
#   rm -f traefik/dynamic/traefik_routers_staging.yml
#   docker stack deploy -c docker-stack.yml prod-infra
#
# The file provider will watch the directory and load available config files
# Keep traefik_routers_staging.yml and traefik_routers_production.yml
# but only have ONE of them in the dynamic folder at runtime


# ============================================================================
# APPROACH 3: Using symbolic links
# ============================================================================
# Create symbolic links to switch between environments
#
# Setup:
#   ln -s traefik_routers_staging.yml traefik/dynamic/traefik_routers.yml   # for staging
#   ln -s traefik_routers_production.yml traefik/dynamic/traefik_routers.yml # for production
#
# Usage:
#   rm traefik/dynamic/traefik_routers.yml
#   ln -s traefik_routers_staging.yml traefik/dynamic/traefik_routers.yml
#   docker stack deploy -c docker-stack.yml staging-infra
#
#   rm traefik/dynamic/traefik_routers.yml
#   ln -s traefik_routers_production.yml traefik/dynamic/traefik_routers.yml
#   docker stack deploy -c docker-stack.yml prod-infra


# ============================================================================
# QUICK REFERENCE: Key Differences
# ============================================================================
#
# STAGING Configuration (traefik_routers_staging.yml):
# - HTTP Hosts: staging.*.primecrib.app
# - TCP SNI: staging.*.primecrib.app
#
# PRODUCTION Configuration (traefik_routers_production.yml):
# - HTTP Hosts: *.primecrib.app (NO staging prefix)
# - TCP SNI: *.primecrib.app (NO staging prefix)
#
# Examples:
#   Staging Traefik Dashboard:   staging.traefik.primecrib.app
#   Production Traefik Dashboard: traefik.primecrib.app
#
#   Staging RabbitMQ TCP:   staging.rabbitmq.primecrib.app:5672
#   Production RabbitMQ TCP: rabbitmq.primecrib.app:5672

