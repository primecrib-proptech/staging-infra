# Traefik Environment Architecture Diagram

## System Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                        DOCKER SWARM CLUSTER                        │
├─────────────────────────────────────────────────────────────────────┤
│                                                                       │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │                    HAPROXY (Reverse Proxy)                 │   │
│  │              Ports 80/443 → Traefik Services              │   │
│  └─────────────────────────────────────────────────────────────┘   │
│                            ↓                                         │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │                    TRAEFIK (Ingress Controller)             │   │
│  │  Loads: traefik_routers_{staging|production}.yml           │   │
│  │                                                             │   │
│  │  HTTP Routes        │  TCP/TLS Routes                       │   │
│  │  Port 443           │  Port 5672 (RabbitMQ)                │   │
│  │  Port 80            │  Port 443 (MinIO)                    │   │
│  └─────────────────────────────────────────────────────────────┘   │
│         ↓                              ↓                             │
│  ┌─────────────────────┐         ┌────────────────────┐            │
│  │  INFRASTRUCTURE     │         │   APPLICATION      │            │
│  │  SERVICES           │         │   SERVICES         │            │
│  │                     │         │                    │            │
│  ├─────────────────────┤         ├────────────────────┤            │
│  │ • Vault             │         │ • Proptech API     │            │
│  │ • RabbitMQ          │         │ • Proptech Gateway │            │
│  │ • MinIO             │         │ • Proptech Admin   │            │
│  │ • Postgres          │         │ • Proptech App     │            │
│  │ • Redis             │         │ • Proptech Pitch   │            │
│  │ • Prometheus        │         │                    │            │
│  │ • Grafana           │         └────────────────────┘            │
│  │ • Portainer         │                                            │
│  │ • Adminer           │                                            │
│  │ • Redis Insight     │                                            │
│  │ • ImgProxy          │                                            │
│  └─────────────────────┘                                            │
│                                                                       │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Traffic Flow Comparison

### STAGING Environment

```
┌──────────────────────────────────────────────────────────┐
│                 External User / Client                   │
└──────────────────────────────────────────────────────────┘
                    ↓ HTTPS Request
        staging.traefik.primecrib.app
                    ↓
┌──────────────────────────────────────────────────────────┐
│                        HAPROXY                           │
│            Reverse Proxy (80:80, 443:443)               │
└──────────────────────────────────────────────────────────┘
                    ↓
┌──────────────────────────────────────────────────────────┐
│                       TRAEFIK                            │
│   Loads: traefik_routers_staging.yml                     │
│   Rule: Host(`staging.traefik.primecrib.app`)           │
└──────────────────────────────────────────────────────────┘
                    ↓
┌──────────────────────────────────────────────────────────┐
│                   api@internal                           │
│             (Traefik Dashboard Service)                  │
└──────────────────────────────────────────────────────────┘
                    ↓
                Response
```

### PRODUCTION Environment

```
┌──────────────────────────────────────────────────────────┐
│                 External User / Client                   │
└──────────────────────────────────────────────────────────┘
                    ↓ HTTPS Request
           traefik.primecrib.app (NO prefix)
                    ↓
┌──────────────────────────────────────────────────────────┐
│                        HAPROXY                           │
│            Reverse Proxy (80:80, 443:443)               │
└──────────────────────────────────────────────────────────┘
                    ↓
┌──────────────────────────────────────────────────────────┐
│                       TRAEFIK                            │
│   Loads: traefik_routers_production.yml                  │
│   Rule: Host(`traefik.primecrib.app`)                   │
└──────────────────────────────────────────────────────────┘
                    ↓
┌──────────────────────────────────────────────────────────┐
│                   api@internal                           │
│             (Traefik Dashboard Service)                  │
└──────────────────────────────────────────────────────────┘
                    ↓
                Response
```

---

## File Organization

```
staging-infra/
│
├── docker-stack.yml
│   └── traefik service volume mount:
│       traefik/dynamic/traefik_routers_${ENVIRONMENT:-staging}.yml
│
├── traefik/
│   ├── traefik.yml (Static config - same for both)
│   ├── DOCKER_STACK_UPDATE.md
│   └── dynamic/
│       ├── traefik_middlewares.yml (Shared)
│       ├── traefik_routers.yml (DEPRECATED - replace with versioned files)
│       ├── traefik_routers_staging.yml ← NEW ← Use for staging
│       ├── traefik_routers_production.yml ← NEW ← Use for production
│       └── README.md
│
├── QUICKSTART.md ← START HERE
├── TRAEFIK_ENVIRONMENT_SPLIT.md
├── TRAEFIK_SETUP.md
├── TRAEFIK_COMPARISON.md
└── deploy.sh
```

---

## Configuration Loading Process

```
┌─────────────────────────────────────────────────────┐
│  Export Environment Variable                        │
│  export ENVIRONMENT=staging (or production)         │
└────────────┬────────────────────────────────────────┘
             ↓
┌─────────────────────────────────────────────────────┐
│  Docker Compose Substitution                        │
│  ${ENVIRONMENT:-staging} resolves to:              │
│  - "staging" (if set)                              │
│  - "production" (if set)                           │
│  - "staging" (default if not set)                  │
└────────────┬────────────────────────────────────────┘
             ↓
┌─────────────────────────────────────────────────────┐
│  Volume Mount in Docker Stack                       │
│  ./traefik/dynamic/traefik_routers_${ENVIRONMENT}   │
│  ↓                                                  │
│  ./traefik/dynamic/traefik_routers_staging.yml      │
│  OR                                                 │
│  ./traefik/dynamic/traefik_routers_production.yml   │
└────────────┬────────────────────────────────────────┘
             ↓
┌─────────────────────────────────────────────────────┐
│  Mounted as /etc/traefik/dynamic/traefik_routers.yml│
└────────────┬────────────────────────────────────────┘
             ↓
┌─────────────────────────────────────────────────────┐
│  Traefik File Provider                              │
│  Watches: /etc/traefik/dynamic/                    │
│  Loads: traefik_routers.yml                         │
│  + traefik_middlewares.yml                          │
└────────────┬────────────────────────────────────────┘
             ↓
┌─────────────────────────────────────────────────────┐
│  Traefik Routes Active                              │
│  - HTTP routes with appropriate hostnames           │
│  - TCP routes with appropriate SNI                  │
└─────────────────────────────────────────────────────┘
```

---

## Hostname Mapping Examples

### Dashboard Access

```
STAGING:
  curl https://staging.traefik.primecrib.app
                  └─────────┬─────────┘
                      Added prefix

PRODUCTION:
  curl https://traefik.primecrib.app
           └──────┬──────┘
           No prefix
```

### API Gateway Access

```
STAGING:
  curl https://staging.staging.api.primecrib.app
                  └─────────┬─────────┘
                      Added prefix

PRODUCTION:
  curl https://api.primecrib.app
           └────┬───┘
           No prefix
```

### TCP/SNI Routing (RabbitMQ)

```
STAGING:
  amqp://admin:password@staging.rabbitmq.primecrib.app:5672
                           └──────────┬──────────┘
                              With prefix

PRODUCTION:
  amqp://admin:password@rabbitmq.primecrib.app:5672
                        └────┬────┘
                        No prefix
```

---

## Service Routing Matrix

```
┌──────────────────────┬────────────────────────────────┬──────────────────────────┐
│ Service              │ Staging Host                   │ Production Host          │
├──────────────────────┼────────────────────────────────┼──────────────────────────┤
│ Traefik Dashboard    │ staging.traefik...             │ traefik.primecrib.app    │
│ Vault                │ staging.vault...               │ vault.primecrib.app      │
│ RabbitMQ Console     │ staging.rabbit...              │ rabbit.primecrib.app     │
│ RabbitMQ AMQP (TCP)  │ staging.rabbitmq...            │ rabbitmq.primecrib.app   │
│ MinIO Console        │ staging.minio...               │ minio.primecrib.app      │
│ MinIO S3 (HTTP)      │ staging.minio.s3...            │ minio.s3.primecrib.app   │
│ MinIO S3 (TCP/SNI)   │ staging.minio.s3...            │ minio.s3.primecrib.app   │
│ Prometheus           │ staging.prometheus...          │ prometheus.primecrib.app │
│ Grafana              │ staging.grafana...             │ grafana.primecrib.app    │
│ Portainer            │ staging.portainer...           │ portainer.primecrib.app  │
│ Adminer              │ staging.adminer...             │ adminer.primecrib.app    │
│ Redis Insight        │ staging.redis-insight...       │ redis-insight.primecrib… │
│ ImgProxy             │ staging.imgproxy...            │ imgproxy.primecrib.app   │
│ HAProxy Stats        │ staging.haproxy...             │ haproxy.primecrib.app    │
│ Proptech Core API    │ staging.proptech-api...        │ proptech-api.primecrib… │
│ Proptech Gateway     │ staging.staging.api...         │ api.primecrib.app        │
│ Proptech Admin       │ staging.admin...               │ admin.primecrib.app      │
│ Proptech App         │ staging.primecrib.app          │ primecrib.app            │
│ Proptech Pitch       │ pitch.primecrib.app (shared)   │ pitch.primecrib.app      │
└──────────────────────┴────────────────────────────────┴──────────────────────────┘
```

---

## Environment Variable Resolution

```
Deployment Command:
    export ENVIRONMENT=staging
    docker stack deploy -c docker-stack.yml staging-infra

Environment Variable Substitution:
    ${ENVIRONMENT:-staging}
         ↓
    "staging"

Volume Mount Path:
    ./traefik/dynamic/traefik_routers_${ENVIRONMENT:-staging}.yml
         ↓
    ./traefik/dynamic/traefik_routers_staging.yml

Container Mount:
    ./traefik/dynamic/traefik_routers_staging.yml
         ↓
    /etc/traefik/dynamic/traefik_routers.yml

Traefik Loads:
    /etc/traefik/dynamic/traefik_routers.yml
    (Contains staging-specific routes)
```

---

## SSL Certificate Chain

```
┌─────────────────────────────────────────┐
│  Let's Encrypt ACME Challenge           │
└────────────┬────────────────────────────┘
             ↓
┌─────────────────────────────────────────┐
│  DNS Resolution Required                │
│  staging.traefik.primecrib.app          │
│  traefik.primecrib.app                  │
└────────────┬────────────────────────────┘
             ↓
┌─────────────────────────────────────────┐
│  Certificate Generation                 │
│  Stored in: /letsencrypt/acme.json     │
└────────────┬────────────────────────────┘
             ↓
┌─────────────────────────────────────────┐
│  TLS Termination                        │
│  Traefik presents cert to clients       │
└────────────┬────────────────────────────┘
             ↓
┌─────────────────────────────────────────┐
│  Service Response                       │
│  Client receives response over HTTPS    │
└─────────────────────────────────────────┘
```

---

## Deployment Decision Tree

```
                    Start Deployment
                           ↓
                  Which Environment?
                    /            \
                   /              \
              STAGING          PRODUCTION
                ↓                   ↓
        export ENVIRONMENT=staging  export ENVIRONMENT=production
                ↓                   ↓
    docker stack deploy            docker stack deploy
    -c docker-stack.yml            -c docker-stack.yml
    staging-infra                  prod-infra
                ↓                   ↓
    Loads: traefik_routers_   Loads: traefik_routers_
    staging.yml               production.yml
                ↓                   ↓
        Route: staging.*        Route: [no prefix]
                ↓                   ↓
    Services with              Services with
    staging prefix             production names
                ↓                   ↓
            Ready!                 Ready!
```

This architecture ensures complete isolation between staging and production
environments while sharing the same infrastructure and backend services.

