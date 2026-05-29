# docker-stack.yml - Modified traefik service for environment-specific routing
#
# This is a REFERENCE file showing how to update the traefik service
# in your main docker-stack.yml to support environment-specific routing.
#
# To implement, copy the traefik service section below to replace the
# traefik service in your docker-stack.yml

traefik:
  image: traefik:v3.6.13
  command:
    - "--configFile=/etc/traefik/traefik.yml"
  volumes:
    - /var/run/docker.sock:/var/run/docker.sock:ro
    - ./traefik/traefik.yml:/etc/traefik/traefik.yml:ro
    - ./traefik/dynamic/traefik_middlewares.yml:/etc/traefik/dynamic/traefik_middlewares.yml:ro
    # Mount environment-specific router config
    - ./traefik/dynamic/traefik_routers_${ENVIRONMENT:-staging}.yml:/etc/traefik/dynamic/traefik_routers.yml:ro
    - traefik_letsencrypt:/letsencrypt
    - ./traefik/dynamic:/etc/traefik/dynamic:ro
    - traefik_logs:/var/log/traefik
  secrets:
    - traefik_basicauth
  networks:
    - traefik-public
    - shared-network
  environment:
    - TZ=UTC
  healthcheck:
    test: [ "CMD", "traefik", "healthcheck", "--ping" ]
    interval: 10s
    timeout: 5s
    retries: 3
    start_period: 10s
  deploy:
    replicas: 1
    endpoint_mode: dnsrr
    restart_policy:
      condition: on-failure
      delay: 5s
      max_attempts: 3
      window: 120s
    update_config:
      parallelism: 1
      delay: 10s
      failure_action: rollback
    labels:
      - "traefik.enable=true"

# ============================================================================
# DEPLOYMENT EXAMPLES
# ============================================================================
#
# For Staging:
#   export ENVIRONMENT=staging
#   docker stack deploy -c docker-stack.yml staging-infra
#
# For Production:
#   export ENVIRONMENT=production
#   docker stack deploy -c docker-stack.yml prod-infra
#
# The ${ENVIRONMENT:-staging} syntax means:
# - Use the value of ENVIRONMENT variable if set
# - Default to "staging" if ENVIRONMENT is not set
#
# This will dynamically load:
# - traefik_routers_staging.yml (if ENVIRONMENT=staging)
# - traefik_routers_production.yml (if ENVIRONMENT=production)

