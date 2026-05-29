# Traefik Environment Configuration - Detailed Comparison

## Quick Reference Table

| Service | Component | Staging | Production |
|---------|-----------|---------|------------|
| **Dashboard** | Host | `staging.traefik.primecrib.app` | `traefik.primecrib.app` |
| **Vault** | Host | `staging.vault.primecrib.app` | `vault.primecrib.app` |
| **RabbitMQ** | Management HTTP | `staging.rabbit.primecrib.app` | `rabbit.primecrib.app` |
| **RabbitMQ** | AMQP TCP SNI | `staging.rabbitmq.primecrib.app` | `rabbitmq.primecrib.app` |
| **MinIO** | Console | `staging.minio.primecrib.app` | `minio.primecrib.app` |
| **MinIO** | S3 API HTTP | `staging.minio.s3.primecrib.app` | `minio.s3.primecrib.app` |
| **MinIO** | S3 API TCP SNI | `staging.minio.s3.primecrib.app` | `minio.s3.primecrib.app` |
| **Prometheus** | Host | `staging.prometheus.primecrib.app` | `prometheus.primecrib.app` |
| **Grafana** | Host | `staging.grafana.primecrib.app` | `grafana.primecrib.app` |
| **Portainer** | Host | `staging.portainer.primecrib.app` | `portainer.primecrib.app` |
| **Adminer** | Host | `staging.adminer.primecrib.app` | `adminer.primecrib.app` |
| **Redis Insight** | Host | `staging.redis-insight.primecrib.app` | `redis-insight.primecrib.app` |
| **ImgProxy** | Host | `staging.imgproxy.primecrib.app` | `imgproxy.primecrib.app` |
| **HAProxy Stats** | Host | `staging.haproxy.primecrib.app` | `haproxy.primecrib.app` |
| **Proptech Core** | Host | `staging.proptech-api.primecrib.app` | `proptech-api.primecrib.app` |
| **Proptech Gateway** | Host | `staging.staging.api.primecrib.app` | `api.primecrib.app` |
| **Proptech Admin** | Host | `staging.admin.primecrib.app` | `admin.primecrib.app` |
| **Proptech App** | Host | `staging.primecrib.app` | `primecrib.app` |
| **Proptech Pitch** | Host | `pitch.primecrib.app` | N/A* |

*Note: `pitch.primecrib.app` is shared between staging and production in the current configuration

---

## Complete Router Configuration Comparison

### HTTP Routers - Staging (traefik_routers_staging.yml)

```yaml
http:
  routers:
    traefik-dashboard:
      rule: Host(`staging.traefik.primecrib.app`)
    vault-dashboard:
      rule: Host(`staging.vault.primecrib.app`)
    rabbit-dashboard:
      rule: Host(`staging.rabbit.primecrib.app`)
    minio-dashboard:
      rule: Host(`staging.minio.primecrib.app`)
    minio-s3:
      rule: Host(`staging.minio.s3.primecrib.app`)
    prometheus-dashboard:
      rule: Host(`staging.prometheus.primecrib.app`)
    grafana-dashboard:
      rule: Host(`staging.grafana.primecrib.app`)
    portainer-dashboard:
      rule: Host(`staging.portainer.primecrib.app`)
    adminer-dashboard:
      rule: Host(`staging.adminer.primecrib.app`)
    redis-insight-dashboard:
      rule: Host(`staging.redis-insight.primecrib.app`)
    imgproxy-dashboard:
      rule: Host(`staging.imgproxy.primecrib.app`)
    haproxy-stats-dashboard:
      rule: Host(`staging.haproxy.primecrib.app`)
    proptech-core-service:
      rule: Host(`staging.proptech-api.primecrib.app`)
    proptech-gateway-service:
      rule: Host(`staging.staging.api.primecrib.app`)
    proptech-admin:
      rule: Host(`staging.admin.primecrib.app`)
    proptech-app:
      rule: Host(`staging.primecrib.app`)
    proptech-pitch:
      rule: Host(`pitch.primecrib.app`)
```

### HTTP Routers - Production (traefik_routers_production.yml)

```yaml
http:
  routers:
    traefik-dashboard:
      rule: Host(`traefik.primecrib.app`)
    vault-dashboard:
      rule: Host(`vault.primecrib.app`)
    rabbit-dashboard:
      rule: Host(`rabbit.primecrib.app`)
    minio-dashboard:
      rule: Host(`minio.primecrib.app`)
    minio-s3:
      rule: Host(`minio.s3.primecrib.app`)
    prometheus-dashboard:
      rule: Host(`prometheus.primecrib.app`)
    grafana-dashboard:
      rule: Host(`grafana.primecrib.app`)
    portainer-dashboard:
      rule: Host(`portainer.primecrib.app`)
    adminer-dashboard:
      rule: Host(`adminer.primecrib.app`)
    redis-insight-dashboard:
      rule: Host(`redis-insight.primecrib.app`)
    imgproxy-dashboard:
      rule: Host(`imgproxy.primecrib.app`)
    haproxy-stats-dashboard:
      rule: Host(`haproxy.primecrib.app`)
    proptech-core-service:
      rule: Host(`proptech-api.primecrib.app`)
    proptech-gateway-service:
      rule: Host(`api.primecrib.app`)
    proptech-admin:
      rule: Host(`admin.primecrib.app`)
    proptech-app:
      rule: Host(`primecrib.app`)
```

### TCP Routers - Staging (traefik_routers_staging.yml)

```yaml
tcp:
  routers:
    minio-tcp:
      rule: "HostSNI(`staging.minio.s3.primecrib.app`)"
      tls:
        passthrough: true
    rabbit-tcp:
      rule: "HostSNI(`staging.rabbitmq.primecrib.app`)"
      tls:
        certResolver: letsencrypt
```

### TCP Routers - Production (traefik_routers_production.yml)

```yaml
tcp:
  routers:
    minio-tcp:
      rule: "HostSNI(`minio.s3.primecrib.app`)"
      tls:
        passthrough: true
    rabbit-tcp:
      rule: "HostSNI(`rabbitmq.primecrib.app`)"
      tls:
        certResolver: letsencrypt
```

---

## Connection Examples

### Staging Environment

#### HTTPS Connections (HTTP/1.1)
```bash
# Dashboard
curl https://staging.traefik.primecrib.app

# API Gateway
curl https://staging.staging.api.primecrib.app/v1/health

# Admin Interface
curl https://staging.admin.primecrib.app

# MinIO S3 Console
curl https://staging.minio.primecrib.app/minio/login
```

#### Secure TCP Connections (TLS)
```bash
# RabbitMQ AMQP
openssl s_client -connect staging.rabbitmq.primecrib.app:5672 -showcerts

# MinIO S3 API (S3 commands via AWS CLI)
aws s3 ls --endpoint-url https://staging.minio.s3.primecrib.app
```

### Production Environment

#### HTTPS Connections (HTTP/1.1)
```bash
# Dashboard
curl https://traefik.primecrib.app

# API Gateway
curl https://api.primecrib.app/v1/health

# Admin Interface
curl https://admin.primecrib.app

# MinIO S3 Console
curl https://minio.primecrib.app/minio/login
```

#### Secure TCP Connections (TLS)
```bash
# RabbitMQ AMQP
openssl s_client -connect rabbitmq.primecrib.app:5672 -showcerts

# MinIO S3 API (S3 commands via AWS CLI)
aws s3 ls --endpoint-url https://minio.s3.primecrib.app
```

---

## DNS Requirements

### Staging
```
staging.traefik.primecrib.app      A/CNAME  <docker-swarm-ip>
staging.vault.primecrib.app        A/CNAME  <docker-swarm-ip>
staging.rabbit.primecrib.app       A/CNAME  <docker-swarm-ip>
staging.rabbitmq.primecrib.app     A/CNAME  <docker-swarm-ip>  (TCP)
staging.minio.primecrib.app        A/CNAME  <docker-swarm-ip>
staging.minio.s3.primecrib.app     A/CNAME  <docker-swarm-ip>
staging.prometheus.primecrib.app   A/CNAME  <docker-swarm-ip>
staging.grafana.primecrib.app      A/CNAME  <docker-swarm-ip>
staging.portainer.primecrib.app    A/CNAME  <docker-swarm-ip>
staging.adminer.primecrib.app      A/CNAME  <docker-swarm-ip>
staging.redis-insight.primecrib.app A/CNAME  <docker-swarm-ip>
staging.imgproxy.primecrib.app     A/CNAME  <docker-swarm-ip>
staging.haproxy.primecrib.app      A/CNAME  <docker-swarm-ip>
staging.proptech-api.primecrib.app A/CNAME  <docker-swarm-ip>
staging.staging.api.primecrib.app  A/CNAME  <docker-swarm-ip>
staging.admin.primecrib.app        A/CNAME  <docker-swarm-ip>
staging.primecrib.app              A/CNAME  <docker-swarm-ip>
```

### Production
```
traefik.primecrib.app              A/CNAME  <docker-swarm-ip>
vault.primecrib.app                A/CNAME  <docker-swarm-ip>
rabbit.primecrib.app               A/CNAME  <docker-swarm-ip>
rabbitmq.primecrib.app             A/CNAME  <docker-swarm-ip>  (TCP)
minio.primecrib.app                A/CNAME  <docker-swarm-ip>
minio.s3.primecrib.app             A/CNAME  <docker-swarm-ip>
prometheus.primecrib.app           A/CNAME  <docker-swarm-ip>
grafana.primecrib.app              A/CNAME  <docker-swarm-ip>
portainer.primecrib.app            A/CNAME  <docker-swarm-ip>
adminer.primecrib.app              A/CNAME  <docker-swarm-ip>
redis-insight.primecrib.app        A/CNAME  <docker-swarm-ip>
imgproxy.primecrib.app             A/CNAME  <docker-swarm-ip>
haproxy.primecrib.app              A/CNAME  <docker-swarm-ip>
proptech-api.primecrib.app         A/CNAME  <docker-swarm-ip>
api.primecrib.app                  A/CNAME  <docker-swarm-ip>
admin.primecrib.app                A/CNAME  <docker-swarm-ip>
primecrib.app                      A/CNAME  <docker-swarm-ip>
pitch.primecrib.app                A/CNAME  <docker-swarm-ip>  (shared)
```

---

## SSL/TLS Certificates

Both environments use Let's Encrypt with the same resolver configuration. The ACME storage is shared:
- Storage location: `/letsencrypt/acme.json` (mounted as `traefik_letsencrypt` volume)

### Certificates to be generated

**Staging:**
- `staging.traefik.primecrib.app`
- `staging.vault.primecrib.app`
- `staging.rabbit.primecrib.app`
- `staging.minio.primecrib.app`
- `staging.minio.s3.primecrib.app`
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

**Production:**
- `traefik.primecrib.app`
- `vault.primecrib.app`
- `rabbit.primecrib.app`
- `minio.primecrib.app`
- `minio.s3.primecrib.app`
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
- `pitch.primecrib.app` (shared)

---

## Middleware Configuration

All middleware is shared between staging and production. The middleware definitions in `traefik_middlewares.yml` include:
- `dashboard-auth` - Basic authentication for dashboards
- `securityHeaders` - Security headers
- `frontendSecurityHeaders` - Frontend-specific security headers
- `compression` - gzip compression
- `rateLimit` - Rate limiting
- `retry` - Automatic retry on failure
- `circuitBreaker` - Circuit breaker pattern
- `buffering` - Request/response buffering
- `cacheNoStore` - No cache
- `cacheStaticLong` - Long-term cache for static content
- `rabbitmq-csp` - Content Security Policy for RabbitMQ

---

## Switching Between Environments

### Using the Deploy Script
```bash
chmod +x deploy.sh

# Deploy staging
./deploy.sh staging

# Deploy production
./deploy.sh production
```

### Manual Deployment with Environment Variable
```bash
# Staging
export ENVIRONMENT=staging
docker stack deploy -c docker-stack.yml staging-infra

# Production
export ENVIRONMENT=production
docker stack deploy -c docker-stack.yml prod-infra
```

### Manual File-Based Deployment
```bash
# For staging
rm -f traefik/dynamic/traefik_routers_production.yml
docker stack deploy -c docker-stack.yml staging-infra

# For production
rm -f traefik/dynamic/traefik_routers_staging.yml
docker stack deploy -c docker-stack.yml prod-infra
```

---

## Verification

After deployment, verify the configuration:

```bash
# List services
docker stack ps staging-infra
docker stack ps prod-infra

# Check traefik logs
docker service logs staging-infra_traefik
docker service logs prod-infra_traefik

# Verify config is loaded
docker service logs staging-infra_traefik | grep -i "routers"

# Test connectivity
curl -I https://staging.traefik.primecrib.app    # Staging
curl -I https://traefik.primecrib.app            # Production
```

