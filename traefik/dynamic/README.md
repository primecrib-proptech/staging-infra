# Traefik Router Configuration - Production vs Staging

This directory contains environment-specific traefik router configurations for Docker Swarm.

## Files

- **traefik_routers_staging.yml** - Staging environment configuration with `staging.` prefix on all hosts
- **traefik_routers_production.yml** - Production environment configuration without `staging.` prefix
- **traefik_middlewares.yml** - Shared middlewares (used by both environments)

## Environment Setup

### For Staging Environment

The traefik service watches the entire `/etc/traefik/dynamic` directory. With both files present, only load the staging config:

**Option 1: Using Docker Swarm Labels (Recommended)**
```yaml
traefik:
  image: traefik:v3.6.13
  volumes:
    - ./traefik/dynamic/traefik_routers_staging.yml:/etc/traefik/dynamic/traefik_routers.yml:ro
```

**Option 2: Keep only staging file**
```bash
rm traefik_routers_prod.yml
# Keep only traefik_routers_staging.yml
```

### For Production Environment

```yaml
traefik:
  image: traefik:v3.6.13
  volumes:
    - ./traefik/dynamic/traefik_routers_prod.yml:/etc/traefik/dynamic/traefik_routers.yml:ro
```

## Key Differences

### Staging (with `staging.` prefix)

Host Rules:
- `staging.traefik.primecrib.app`
- `staging.vault.primecrib.app`
- `staging.rabbit.primecrib.app`
- etc.

TCP SNI Rules:
- `staging.minio.s3.primecrib.app`
- `staging.rabbitmq.primecrib.app`

### Production (without prefix)

Host Rules:
- `traefik.primecrib.app` (no prefix)
- `vault.primecrib.app` (no prefix)
- `rabbit.primecrib.app` (no prefix)
- etc.

TCP SNI Rules:
- `minio.s3.primecrib.app` (no prefix)
- `rabbitmq.primecrib.app` (no prefix)

## Implementation in docker-stack.yml

Choose one of two approaches:

### Approach 1: Single Mount (Cleanest)
```yaml
traefik:
  volumes:
    - ./traefik/traefik.yml:/etc/traefik/traefik.yml:ro
    - ./traefik/dynamic/traefik_middlewares.yml:/etc/traefik/dynamic/traefik_middlewares.yml:ro
    - ./traefik/dynamic/traefik_routers_${ENVIRONMENT:-staging}.yml:/etc/traefik/dynamic/traefik_routers.yml:ro
```

Then set environment variable:
```bash
export ENVIRONMENT=staging  # or production
docker stack deploy -c docker-stack.yml proptech
```

### Approach 2: Both Files with File Provider
The file provider in traefik.yml watches the entire directory:
```yaml
providers:
  file:
    directory: /etc/traefik/dynamic
    watch: true
```

This means all `.yml` files are loaded. Use naming convention to load only one:
- Keep only `traefik_routers_staging.yml` or `traefik_routers_production.yml` in the dynamic folder
- Keep `traefik_middlewares.yml` (shared)

## Deployment Steps

1. **For Staging:**
   ```bash
   rm traefik/dynamic/traefik_routers_prod.yml
   docker stack deploy -c docker-stack.yml staging-infra
   ```

2. **For Production:**
   ```bash
   rm traefik/dynamic/traefik_routers_staging.yml
   docker stack deploy -c docker-stack.yml prod-infra
   ```

Or use environment variables with docker compose templating:

```bash
ENVIRONMENT=staging docker stack deploy -c docker-stack.yml staging-infra
ENVIRONMENT=production docker stack deploy -c docker-stack.yml prod-infra
```

## TCP/TLS SNI Routing

The key difference in TCP routing is the `HostSNI` rule:

- **Staging**: `HostSNI(\`staging.rabbitmq.primecrib.app\`)`
- **Production**: `HostSNI(\`rabbitmq.primecrib.app\`)`

This ensures SSL/TLS connections are routed to the correct environment based on the SNI hostname.

## Notes

- Both configurations share the same backend services (same container names)
- Middleware definitions are identical and can be shared
- The only difference is the host prefix pattern
- Both files use the same certificate resolver (letsencrypt)

