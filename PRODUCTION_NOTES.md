# Production-Grade Docker Swarm Infrastructure

## CRITICAL CHANGES & ANTI-PATTERNS FIXED

### 1. HAProxy → Traefik Load Balancing
**PROBLEM**: HAProxy was templating only 1 server, but Traefik was deploying 3 replicas
- Broken HA setup - all traffic went to one replica
**SOLUTION**:
- Updated HAProxy to template 10 Traefik servers with dynamic DNS resolution
- Added compression, HTTP/HTTPS redirect, session stickiness
- Enhanced stats page with authentication

### 2. Redis Architecture
**PROBLEM**: Confusing dual-replica setup with wrong master references (`redis` instead of `redis-master`)
- redis-replica-1 & redis-replica-2 were both trying to replicate from non-existent `redis` service
- Sentinel pointing to wrong master
**SOLUTION**:
- Cleaned up: 1 master (`redis-master`) + optional replicas (redis-replica-1, redis-replica-2)
- 3-node Sentinel cluster for HA failover
- Proper `redis-master:6379` references in all configs
- Both master and Sentinel on backend network only

### 3. Vault HA Cluster
**PROBLEM**: 
- Wrapper script referenced wrong config file (vault.hcl vs vault-prod-{1,2,3}.hcl)
- All three vault instances were trying to load same config
**SOLUTION**:
- Vault services now load: `vault-prod-{1,2,3}.hcl` → renamed to `vault.hcl` at runtime
- Proper node IDs: vault-1, vault-2, vault-3 (not localhost)
- Correct cluster_addr and api_addr per node
- Raft clustering enabled with retry_join directives
- Traefik routers now load-balance across all 3 Vault instances

### 4. PostgreSQL Network Isolation
**PROBLEM**: PostgreSQL exposed on traefik-public network (security risk)
**SOLUTION**: Postgres now backend-only, not exposed via Traefik

### 5. Missing Production Hardening
**MISSING**:
- No `init: true` on most services (zombie process handling)
- No read-only config mounts
- Missing restart policies on observability stack
- Minimal health checks
- No Prometheus scrape labels for automated discovery

**ADDED**:
- `init: true` on all services
- Read-only `:ro` mounts for configs
- Proper `restart_policy` with timeouts on ALL services
- Health checks on every service
- Prometheus labels on all services for auto-scraping
- Service name labels for observability correlation

### 6. Observability Stack Hardening
**FIXED**:
- Prometheus: Added 30-day retention + 50GB size limit, lifecycle API
- Grafana: Fixed root URL (was localhost), added connection pooling
- Loki/Tempo/Promtail: Added `init: true`, proper restart policies, health checks
- All added Prometheus scrape labels for auto-discovery

---

## DEPLOYMENT CHECKLIST

### 1. Create Required Directories
```bash
for dir in postgres-data postgres-backup-data minio-data minio-config redis-master-data redis-replica-1-data redis-replica-2-data redis-sentinel-data rabbitmq-data vault-1-data vault-1-logs vault-2-data vault-2-logs vault-3-data vault-3-logs traefik-letsencrypt-data traefik-logs prometheus-data grafana-data loki-data tempo-data portainer redisinsight-data; do
  sudo mkdir -p /opt/containers/storages/$dir
  sudo chown -R 1000:1000 /opt/containers/storages/$dir 2>/dev/null || true
done
```

### 2. Create Docker Secrets
```bash
# Database secrets
docker secret create db_name - < <(echo "proptech")
docker secret create db_user - < <(echo"proptech")
docker secret create db_password - < <(openssl rand -base64 32)
docker secret create postgres_password - < <(openssl rand -base64 32)
docker secret create db_app_password - < <(openssl rand -base64 32)
docker secret create db_ro_password - < <(openssl rand -base64 32)

# Vault secrets
docker secret create vault_root_token - < <(openssl rand -base64 32)
docker secret create vault_unseal_key - < <(echo "YOUR_UNSEAL_KEY_HERE")
docker secret create vault_connection_url - < <(echo "https://vault:8200")

# Redis secrets
docker secret create redis_root_password - < <(openssl rand -base64 32)

# RabbitMQ secrets
docker secret create rabbit_password - < <(openssl rand -base64 32)
docker secret create rabbit_erlang_cookie - < <(openssl rand -base64 32)

# MinIO secrets
docker secret create minio_root_password - < <(openssl rand -base64 32)
docker secret create minio_access_key - < <(echo "minioadmin")

# Grafana secrets
docker secret create grafana_root_password - < <(openssl rand -base64 32)

# Traefik secrets (basic auth: admin:admin)
echo "admin:$(openssl passwd -apr1 admin)" | docker secret create traefik_basicauth -

# JWT & backup secrets
docker secret create jwt_secret_key - < <(openssl rand -base64 32)
docker secret create postgres_backup_encryption_pass - < <(openssl rand -base64 32)

# ImgProxy secrets
docker secret create imgproxy_key - < <(openssl rand -base64 32)
docker secret create imgproxy_salt - < <(openssl rand -base64 32)

# Tempo S3 credentials
echo "[default]
aws_access_key_id = minioadmin
aws_secret_access_key = YOUR_MINIO_PASSWORD
" | docker secret create tempo_s3_credentials -
```

### 3. Create Docker Networks
```bash
docker network create --driver overlay traefik-public
docker network create --driver overlay shared-network
docker network create --driver overlay observability --opt encrypted=true
```

### 4. Configure Node Labels (for placement constraints)
```bash
# On vault provider nodes
docker node update --label-add vault-node-1=true <NODE_ID>

# On Redis replica nodes (if deploying replicas)
docker node update --label-add redis-replica-1=true <REPLICA_NODE_1>
docker node update --label-add redis-replica-2=true <REPLICA_NODE_2>
```

### 5. Create External Config for ImgProxy Watermark
```bash
docker config create imgproxy_watermark ./imgproxy/watermark/logo-96x96.png
```

### 6. Deploy Stack
```bash
docker stack deploy --compose-file docker-stack.yml production
```

### 7. Verify Deployment
```bash
# Check all services running
docker stack ps production

# Scale up Traefik if needed
docker service scale production_traefik=3

# Check HAProxy upstream servers
docker exec $(docker ps -q -f label=com.docker.swarm.service.name=production_haproxy) \
  curl -s http://localhost:8404/stats | grep traefik

# Verify Redis Sentinel
docker exec $(docker ps -q -f label=com.docker.swarm.service.name=production_redis-sentinel) \
  redis-cli -p 26379 SENTINEL masters

# Verify Vault cluster status
docker exec $(docker ps -q -f label=com.docker.swarm.service.name=production_vault-1) \
  vault operator raft list-peers
```

---

## CONFIGURATION FILES REFERENCE

| Service | Config File | Purpose |
|---------|------------|---------|
| HAProxy | haproxy/haproxy-prod.cfg | 10-server Traefik backend, HA config |
| Traefik | traefik/traefik-prod.yml | HA production settings, swarmMode |
| Traefik Dynamic | traefik/dynamic/traefik_routers.yml | 3-node Vault LB, middleware config |
| Redis | redis/redis-prod.conf | Production tuning, Sentinel-ready |
| RabbitMQ | rabbitmq/rabbitmq.conf | Cluster discovery, DN S peer resolution |
| Vault | vault/vault-prod-{1,2,3}.hcl | Per-node Raft clustering |
| PostgreSQL | postgres/postgresql.conf.custom | Performance tuning for 6 vCPU, 12GB RAM |
| Prometheus | prometheus/prometheus.yml | Service discovery scrape configs |
| Loki | loki/loki-config.yaml | Log aggregation retention |
| Tempo | tempo/tempo.yaml | Trace storage with MinIO backend |
| Promtail | promtail/promtail-config.yml | Container log shipping |

---

## VOLUMES & PERSISTENT STORAGE

All volumes use `bind` mount driver pointing to `/opt/containers/storages/`:

| Service | Volume Path | Purpose |
|---------|------------|---------|
| PostgreSQL | postgres-data/ | Main database files + WAL |
| PostgreSQL Backup | postgres-backup-data/ | Encrypted backups staged locally |
| MinIO | minio-data/ | S3-compatible object storage |
| Redis Master | redis-master-data/ | Master RDB + AOF |
| Redis Replicas | redis-replica-{1,2}-data/ | Replica RDB + AOF |
| Redis Sentinel | redis-sentinel-data/ | Sentinel state |
| RabbitMQ | rabbitmq-data/ | Queue persistence |
| Vault | vault-{1,2,3}-data/ | Raft consensus DB per node |
| Traefik ACME | traefik-letsencrypt-data/ | Let's Encrypt certificates |
| Prometheus | prometheus-data/ | TSDB (30 days, 50GB max) |
| Grafana | grafana-data/ | Dashboards + datasources |
| Loki | loki-data/ | Log chunks + index |
| Tempo | tempo-data/ | Trace WAL + cache |

---

## NETWORKING TOPOLOGY

```
┌─────────────────────────────────────┐
│           Public Internet            │
└──────────────┬──────────────────────┘
               │ :80, :443
               ↓
        ┌──────────────┐
        │    HAProxy   │ (1 replica)
        │   (:80/443)  │
        └──────────────┘
               │ tasks.traefik DNS
               ↓ (10 x server-template)
    ┌──────────────────────────────┐
    │     Traefik Cluster (HA)     │ (3 replicas, DNSRR)
    │  · traefik-prod.yml config   │ (API dashboards)
    │  · TLS termination            │ (Let's Encrypt)
    │  · Service discovery          │
    └──────────────────────────────┘
               │ (service routing)
               │
    ┌──────────────────────────────────────────────────────────┐
    │ traefik-public overlay network (encrypted)               │
    │  · Ingress layer                                         │
    │  · Public dashboards (Traefik, Portal, MinIO, etc.)       │
    │  · Inter-service discovery                              │
    └──────────────────────────────────────────────────────────┘
               │
    ┌──────────────────────────────────────────────────────────┐
    │  backend overlay network (internal: true, encrypted)     │
    │  · PostgreSQL (5432)                                    │
    │  · RabbitMQ (5672, 15672)                              │
    │  · MinIO (9000, 9001)                                  │
    │  · Redis Master (6379)                                 │
    │  · Redis Replicas (6379)                               │
    │  · Redis Sentinel (26379)                              │
    │  · Vault Cluster (8200, 8201)                          │
    │  · Observability stack (Prometheus, Grafana, etc.)     │
    └──────────────────────────────────────────────────────────┘
               │
    ┌──────────────────────────────────────────────────────────┐
    │  observability overlay network (encrypted)               │
    │  · Loki (3100)                                          │
    │  · Tempo (3200)                                         │
    │  · Promtail (9080, global mode)                         │
    │  · Prometheus (9090)                                    │
    └──────────────────────────────────────────────────────────┘

shared-network:
    ┌──────────────────────────────────────────────────────────┐
    │  shared network (for app services)                       │
    │  · Prometheus, Grafana, Traefik, Loki, Tempo            │
    │  · Application microservices connect here               │
    └──────────────────────────────────────────────────────────┘
```

---

## SERVICE HEALTH & READINESS

All services now include health checks:
- **HTTP services**: wget or curl to health endpoints
- **TCP services**: TCP connection attempts
- **Databases**: Native readiness probes (pg_isready, redis-cli ping)
- **Startup period**: 10-60s before health checks start

Example monitoring:
```bash
docker service ls -q | xargs -I {} docker service ps {} \
  | grep -E "running|unhealthy" | sort | uniq -c
```

---

## SCALING GUIDELINES

### Traefik (DNS RR Mode - True HA)
```bash
# Scale to 5 replicas (max 1 per node with current config)
docker service scale production_traefik=5

# HAProxy automatically discovers via tasks.traefik DNS
```

### Redis Replicas
```bash
# First label additional nodes
docker node update --label-add redis-replica-1=true NODE_2
docker node update --label-add redis-replica-2=true NODE_3

# Scale replicas
docker service scale production_redis-replica-1=1
docker service scale production_redis-replica-2=1

# Configure master to replicate
docker service update --env-add REDIS_REPLICATE=yes production_redis-master
```

### ImgProxy
```bash
# Currently 2 replicas, scale up as needed
docker service scale production_imgproxy=5
```

### Vault Cluster (Advanced)
For truly HA Vault, deploy vault-2 and vault-3 to separate manager nodes with proper labels:
```bash
docker node update --label-add vault-node-1=true MANAGER_1
docker node update --label-add vault-node-2=true MANAGER_2  # or any manager
docker node update --label-add vault-node-3=true MANAGER_3  # or any manager
```

---

## BACKUP & DISASTER RECOVERY

### PostgreSQL Automated Backups
The `postgres-backup` service runs via cron to MinIO:
```bash
# Run backup manually
docker service logs production_postgres-backup
```

### Redis Persistence
- **Master**: RDB + AOF enabled, replicated to Sentinel
- **Sentinel**: Monitors master, auto-failover on failure

### Vault State
- **Raft backend**: All state in `/vault/data` (persisted volumes)
- **Regular snapshots**: Configure external backup job

### Configuration Backup
```bash
# Backup all configs to MinIO
tar czf - ./traefik ./haproxy ./prometheus ./grafana | \
  aws s3 cp - s3://postgres-backups/configs/prod-$(date +%Y%m%d).tar.gz \
  --endpoint-url http://minio:9000
```

---

## MONITORING & ALERTING

### Key Metrics to Monitor
```
Traefik (traefik:9080/metrics):
  - traefik_service_requests_total{service="..."}
  - traefik_service_request_duration_seconds

Redis (redis:6379):
  - redis_connected_clients
  - redis_used_memory
  - redis_replication_role

PostgreSQL (postgres:5432):
  - pg_stat_database_tup_returned
  - pg_stat_statements_total_time
  - pg_replication_lag (when replicas enabled)

RabbitMQ (rabbit:15692/metrics):
  - rabbitmq_channels
  - rabbitmq_queues

Vault (vault:8200/v1/sys/metrics):
  - vault_core_unsealed
  - vault_raft_apply
  - vault_raft_followers
```

### Prometheus Scrape Targets
All services auto-discovered via labels:
```
http://prometheus:9090/targets
```

### Grafana Datasources
Pre-configured:
- **Prometheus**: http://prometheus:9090
- **Loki**: http://loki:3100
- **Tempo**: http://tempo:3200

---

## TROUBLESHOOTING

### Services failing to start
```bash
docker service logs production_SERVICE_NAME --tail 50
docker service inspect production_SERVICE_NAME | jq .UpdateStatus
```

### HAProxy not discovering Traefik
```bash
# Check DNS resolution
docker exec $(docker ps -q -f label=com.docker.swarm.service.name=production_haproxy) \
  nslookup tasks.traefik

# Check server template expansion
docker exec $(docker ps -q -f label=com.docker.swarm.service.name=production_haproxy) \
  curl localhost:8404/stats | grep server
```

### Vault cluster not forming
```bash
docker exec $(docker ps -q -f label=com.docker.swarm.service.name=production_vault-1) \
  vault operator raft list-peers
# Should show all 3 nodes
```

### Redis replication lag
```bash
docker exec $(docker ps -q -f label=com.docker.swarm.service.name=production_redis-master) \
  redis-cli info replication
```

### PostgreSQL replication (future)
```bash
docker exec $(docker ps -q -f label=com.docker.swarm.service.name=production_postgres) \
  psql -U proptech -d proptech -c "
  SELECT usename, backend_start, state FROM pg_stat_replication;"
```

---

## PRODUCTION READINESS CHECKLIST

- [x] All services with `init: true` (PID 1 signal handling)
- [x] All configs mounted read-only (`:ro`)
- [x] Proper restart policies (on-failure with max_attempts)
- [x] Health checks on all services (15-30s defaults)
- [x] Secrets mounted at /run/secrets (not env vars)
- [x] Encrypted overlay networks (backend, ci-network)
- [x] Internal-only networks where appropriate (backend)
- [x] Resource limits & reservations on all services
- [x] HA/multi-replica setup (Traefik 3, Sentinel 3, Vault 3)
- [x] Prometheus auto-discovery labels on all services
- [x] Unified logging to stdout (Docker logs aggregation)
- [x] PostgreSQL WAL-safe, backup-ready
- [x] MinIO with persistent storage
- [x] TLS termination at Traefik + Let's Encrypt
- [x] HAProxy with SSL, compression, session stickiness
- [x] Swarm-native service discovery
- [x] Anti-affinity constraints where needed (max_replicas_per_node)
- [x] No hardcoded credentials in configs
- [x] Proper placement constraints (manager-only for critical services)
- [x] Zero-downtime update strategy (parallelism: 1, failure_action: rollback)

---

## NEXT STEPS FOR ADVANCED HA

1. **PostgreSQL Replication**: Deploy hot-standby replicas using built-in streaming replication
2. **Redis Cluster Mode**: Migrate from Sentinel to true Redis Cluster when 6+ nodes available
3. **Vault Auto-Unseal**: Integrate AWS KMS or HSM instead of manual unseal key
4. **Distributed Data**: MinIO server pool for object distribution
5. **Canary Deployments**: Implement weighted routing in Traefik for gradual rollouts
6. **Observability**: Add alertmanager, rule evaluation, dashboards
7. **Backup Vault**: External backup job targeting S3/MinIO for disaster recovery
8. **DR Site**: Geo-redundancy with cross-DC replication


