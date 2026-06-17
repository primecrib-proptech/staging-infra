# Quick Start Guide - Traefik Production/Staging Split

## What Was Done

Your traefik router configuration has been split into **two separate environment-specific files**:

1. **`traefik_routers_staging.yml`** - All routes have `staging.` prefix
2. **`traefik_routers_production.yml`** - Routes have NO prefix

Both route to the same backend services but with different external hostnames.

## Files Created

```
staging-infra/
├── TRAEFIK_ENVIRONMENT_SPLIT.md          ← Start here for overview
├── TRAEFIK_SETUP.md                      ← Implementation approaches
├── TRAEFIK_COMPARISON.md                 ← Detailed comparison table
├── deploy.sh                             ← Deployment helper script
└── traefik/
    ├── DOCKER_STACK_UPDATE.md            ← How to update docker-stack.yml
    └── dynamic/
        ├── README.md                     ← Configuration details
        ├── traefik_routers_staging.yml   ← Staging config (NEW)
        ├── traefik_routers_production.yml ← Production config (NEW)
        ├── traefik_middlewares.yml       ← Shared middleware (existing)
        └── traefik_routers.yml           ← Current config (can delete after migration)
```

## Quick Start (3 Steps)

### Step 1: Update docker-stack.yml

Modify the `traefik` service volume mounts:

**Before:**
```yaml
traefik:
  volumes:
    - ./traefik/dynamic:/etc/traefik/dynamic:ro
```

**After:**
```yaml
traefik:
  volumes:
    - ./traefik/traefik.yml:/etc/traefik/traefik.yml:ro
    - ./traefik/dynamic/traefik_middlewares.yml:/etc/traefik/dynamic/traefik_middlewares.yml:ro
    - ./traefik/dynamic/traefik_routers_${ENVIRONMENT:-staging}.yml:/etc/traefik/dynamic/traefik_routers.yml:ro
    - traefik_letsencrypt:/letsencrypt
    - traefik_logs:/var/log/traefik
```

### Step 2: Deploy Using Environment Variable

```bash
# Deploy to Staging
export ENVIRONMENT=staging
docker stack deploy -c docker-stack.yml staging-infra

# Deploy to Production
export ENVIRONMENT=production
docker stack deploy -c docker-stack.yml prod-infra
```

### Step 3: Verify Deployment

```bash
# Check staging
curl -I https://staging.traefik.primecrib.app

# Check production
curl -I https://traefik.primecrib.app
```

---

## Key Differences

| Aspect | Staging | Production |
|--------|---------|------------|
| Traefik Dashboard | `staging.traefik.primecrib.app` | `traefik.primecrib.app` |
| API Gateway | `staging.staging.api.primecrib.app` | `api.primecrib.app` |
| Main App | `staging.primecrib.app` | `primecrib.app` |
| RabbitMQ TCP | `staging.rabbitmq.primecrib.app` | `rabbitmq.primecrib.app` |
| MinIO S3 | `staging.minio.s3.primecrib.app` | `minio.s3.primecrib.app` |

**All other services follow the same pattern:**
- Staging: `staging.<service>.primecrib.app`
- Production: `<service>.primecrib.app`

---

## Alternative Methods

### Method 1: Using the Deploy Script (Easiest)
```bash
chmod +x deploy.sh
./deploy.sh staging     # or production
```

### Method 2: Manual File Management
```bash
# For Staging (remove production config)
rm traefik/dynamic/traefik_routers_prod.yml
docker stack deploy -c docker-stack.yml staging-infra

# For Production (remove staging config)
rm traefik/dynamic/traefik_routers_staging.yml
docker stack deploy -c docker-stack.yml prod-infra
```

### Method 3: Symbolic Links
```bash
# For Staging
ln -sf traefik_routers_staging.yml traefik/dynamic/traefik_routers.yml

# For Production
ln -sf traefik_routers_prod.yml traefik/dynamic/traefik_routers.yml

# Then deploy normally
docker stack deploy -c docker-stack.yml prod-infra
```

---

## DNS Configuration

Ensure your DNS is configured:

**Staging:**
```
staging.*.primecrib.app  → Your Docker Swarm IP
```

**Production:**
```
*.primecrib.app          → Your Docker Swarm IP
```

Example for one service:
```bash
# Staging
staging.traefik.primecrib.app   A    <swarm-ip>

# Production
traefik.primecrib.app           A    <swarm-ip>
```

---

## TCP/TLS SNI Services

The critical difference for TCP connections is the SNI hostname:

**Staging:**
```
staging.rabbitmq.primecrib.app:5672    (RabbitMQ AMQP)
staging.minio.s3.primecrib.app:443     (MinIO S3)
```

**Production:**
```
rabbitmq.primecrib.app:5672            (RabbitMQ AMQP)
minio.s3.primecrib.app:443             (MinIO S3)
```

---

## What's the Same

- **Backend services**: All container names are identical (`rabbitmq`, `minio`, `vault`, etc.)
- **Middleware**: Same middleware definitions used by both environments
- **Certificate resolver**: Both use Let's Encrypt (same storage)
- **Security headers**: Identical security configuration
- **Network configuration**: Both use the same overlay networks

---

## Troubleshooting

### Traefik not loading the correct config
```bash
# Check environment variable is set
echo $ENVIRONMENT

# Check traefik logs
docker service logs <stack-name>_traefik | tail -20

# Verify the config file exists
ls -la traefik/dynamic/traefik_routers_${ENVIRONMENT:-staging}.yml
```

### Wrong hostname showing
This means the wrong config file is being loaded. Make sure:
1. Only one router config file is mounted in docker-stack.yml
2. Or ensure only one config file exists in `traefik/dynamic/`

### DNS resolution errors
```bash
# Verify DNS
nslookup staging.traefik.primecrib.app
nslookup traefik.primecrib.app

# Test connectivity
curl -I https://staging.traefik.primecrib.app
curl -I https://traefik.primecrib.app
```

### Certificate errors
Wait a few minutes for Let's Encrypt to generate certificates:
```bash
# Check certificate generation
docker service logs <stack-name>_traefik | grep -i cert
```

---

## Documentation Reference

| Document | Purpose |
|----------|---------|
| `TRAEFIK_ENVIRONMENT_SPLIT.md` | Full overview and setup guide |
| `TRAEFIK_SETUP.md` | Detailed implementation approaches |
| `TRAEFIK_COMPARISON.md` | Complete hostname comparison table |
| `traefik/DOCKER_STACK_UPDATE.md` | How to modify docker-stack.yml |
| `traefik/dynamic/README.md` | Configuration details and notes |

---

## Next Steps

1. **Review** the comparison in `TRAEFIK_COMPARISON.md` to understand all hostname changes
2. **Update** your `docker-stack.yml` following `traefik/DOCKER_STACK_UPDATE.md`
3. **Configure** your DNS records for both environments
4. **Test** staging deployment first with `./deploy.sh staging`
5. **Verify** all services are accessible before deploying to production
6. **Deploy** production with `./deploy.sh production`

---

## Environment Variables Summary

```bash
# Set environment for staging
export ENVIRONMENT=staging

# Set environment for production
export ENVIRONMENT=production

# Default is staging if not set
docker stack deploy -c docker-stack.yml my-stack
# Uses traefik_routers_staging.yml by default
```

---

## Common Commands

```bash
# Deploy staging
ENVIRONMENT=staging docker stack deploy -c docker-stack.yml staging-infra

# Deploy production
ENVIRONMENT=production docker stack deploy -c docker-stack.yml prod-infra

# Check stack services
docker stack ps staging-infra
docker stack ps prod-infra

# View traefik logs
docker service logs staging-infra_traefik
docker service logs prod-infra_traefik

# Remove a stack
docker stack rm staging-infra
docker stack rm prod-infra

# View current routing rules
docker exec <traefik-container-id> traefik api
```

---

## Support

For detailed information about specific aspects:

- **Configuration Structure**: See `traefik/dynamic/README.md`
- **All Hostname Mappings**: See `TRAEFIK_COMPARISON.md`
- **Implementation Methods**: See `TRAEFIK_SETUP.md`
- **Docker Stack Changes**: See `traefik/DOCKER_STACK_UPDATE.md`

