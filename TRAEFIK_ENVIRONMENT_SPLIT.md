# Traefik Router Configuration - Environment Split Summary

## Overview

Your traefik router configuration has been split into **production** and **staging** environments. The key difference is the hostname prefix:

- **Staging**: Uses `staging.` prefix (e.g., `staging.traefik.primecrib.app`)
- **Production**: No prefix (e.g., `traefik.primecrib.app`)

## Files Created

### 1. Configuration Files
```
traefik/dynamic/
├── traefik_routers_staging.yml       (NEW) - Staging environment config
├── traefik_routers_production.yml    (NEW) - Production environment config
├── traefik_middlewares.yml           (EXISTING) - Shared middleware config
└── README.md                         (NEW) - Detailed configuration guide
```

### 2. Documentation Files
```
staging-infra/
├── TRAEFIK_SETUP.md                  (NEW) - Implementation approaches
└── traefik/
    └── DOCKER_STACK_UPDATE.md        (NEW) - Docker stack modification guide
```

## Configuration Comparison

### Staging Configuration (traefik_routers_staging.yml)

**HTTP Routes:**
- `staging.traefik.primecrib.app` (Dashboard)
- `staging.vault.primecrib.app`
- `staging.rabbit.primecrib.app`
- `staging.minio.primecrib.app`
- `staging.prometheus.primecrib.app`
- `staging.grafana.primecrib.app`
- `staging.portainer.primecrib.app`
- `staging.adminer.primecrib.app`
- `staging.redis-insight.primecrib.app`
- `staging.imgproxy.primecrib.app`
- `staging.haproxy.primecrib.app`
- `staging.proptech-api.primecrib.app`
- `staging.staging.api.primecrib.app`
- `staging.admin.primecrib.app`
- `staging.primecrib.app`
- `pitch.primecrib.app`

**TCP SNI Routes:**
- `staging.minio.s3.primecrib.app` (MinIO S3)
- `staging.rabbitmq.primecrib.app` (RabbitMQ AMQP)

### Production Configuration (traefik_routers_production.yml)

**HTTP Routes:**
- `traefik.primecrib.app` (Dashboard)
- `vault.primecrib.app`
- `rabbit.primecrib.app`
- `minio.primecrib.app`
- `prometheus.primecrib.app`
- `grafana.primecrib.app`
- `portainer.primecrib.app`
- `adminer.primecrib.app`
- `redis-insight.primecrib.app`
- `imgproxy.primecrib.app`
- `haproxy.primecrib.app`
- `proptech-api.primecrib.app`
- `api.primecrib.app`
- `admin.primecrib.app`
- `primecrib.app`

**TCP SNI Routes:**
- `minio.s3.primecrib.app` (MinIO S3)
- `rabbitmq.primecrib.app` (RabbitMQ AMQP)

## Implementation Steps

### Option 1: Environment Variable (RECOMMENDED for Docker Swarm)

1. Update `docker-stack.yml` traefik service volume mount:

```yaml
traefik:
  # ... other config ...
  volumes:
    - /var/run/docker.sock:/var/run/docker.sock:ro
    - ./traefik/traefik.yml:/etc/traefik/traefik.yml:ro
    - ./traefik/dynamic/traefik_middlewares.yml:/etc/traefik/dynamic/traefik_middlewares.yml:ro
    # Environment-specific router config
    - ./traefik/dynamic/traefik_routers_${ENVIRONMENT:-staging}.yml:/etc/traefik/dynamic/traefik_routers.yml:ro
    - traefik_letsencrypt:/letsencrypt
    - traefik_logs:/var/log/traefik
```

2. Deploy for staging:
```bash
export ENVIRONMENT=staging
docker stack deploy -c docker-stack.yml staging-infra
```

3. Deploy for production:
```bash
export ENVIRONMENT=production
docker stack deploy -c docker-stack.yml prod-infra
```

### Option 2: Manual File Management

1. For staging, keep only staging config:
```bash
rm traefik/dynamic/traefik_routers_prod.yml
docker stack deploy -c docker-stack.yml staging-infra
```

2. For production, keep only production config:
```bash
rm traefik/dynamic/traefik_routers_staging.yml
docker stack deploy -c docker-stack.yml prod-infra
```

### Option 3: Symbolic Links

1. Create symlink for active environment:
```bash
# For staging
ln -sf traefik_routers_staging.yml traefik/dynamic/traefik_routers.yml

# For production
ln -sf traefik_routers_prod.yml traefik/dynamic/traefik_routers.yml
```

2. Deploy normally:
```bash
docker stack deploy -c docker-stack.yml prod-infra
```

## Key Technical Details

### TCP/TLS SNI Routing

The critical difference for TCP connections is the `HostSNI` rule in the tcp.routers section:

```yaml
# Staging
tcp:
  routers:
    rabbit-tcp:
      rule: "HostSNI(`staging.rabbitmq.primecrib.app`)"

# Production
tcp:
  routers:
    rabbit-tcp:
      rule: "HostSNI(`rabbitmq.primecrib.app`)"
```

This ensures that TLS connections use the correct SNI hostname for certificate validation.

### Shared Services

All service definitions (backend URLs) are identical in both configs:
- `rabbit-service` → `http://rabbitmq:15672`
- `minio-service` → `http://minio:9001`
- `vault-service` → `https://vault:8200`
- etc.

The container names don't change; only the external hostnames do.

### Middleware

Middleware definitions are identical and shared across both environments. Consider moving them to a single `traefik_middlewares.yml` file if not already done.

## DNS Setup

Ensure your DNS records point to your Docker Swarm cluster:

**Staging:**
```
staging.*.primecrib.app     → Your Docker Swarm IP
```

**Production:**
```
*.primecrib.app             → Your Docker Swarm IP
```

## SSL/TLS Certificates

Both environments use the same certificate resolver (`letsencrypt`), so certificates will be requested for:
- Staging domains: `staging.*.primecrib.app`
- Production domains: `*.primecrib.app`

Make sure your DNS is properly configured before deploying to get valid certificates.

## Troubleshooting

1. **Traefik not loading config**: Verify the environment variable is set:
   ```bash
   echo $ENVIRONMENT
   ```

2. **Wrong hostname routing**: Check that only one router config file exists in `traefik/dynamic/` if using manual approach

3. **Certificate errors**: Ensure DNS resolves correctly and Traefik has internet access for ACME challenges

## Next Steps

1. Review `/Users/johnadeshola/Projects/Cyberstarsng/ops/staging-infra/traefik/dynamic/README.md` for detailed guide
2. Choose implementation approach from `/Users/johnadeshola/Projects/Cyberstarsng/ops/staging-infra/TRAEFIK_SETUP.md`
3. Update `docker-stack.yml` according to `traefik/DOCKER_STACK_UPDATE.md`
4. Test staging deployment first before production

