# Production Infrastructure Validation Checklist

## PRE-DEPLOYMENT CHECKS

- [ ] **Docker Swarm Initialized**: `docker info | grep -i swarm`
- [ ] **Manager Nodes**: At least 1 manager node available
- [ ] **Disk Space**: 500GB+ available on all nodes at `/opt/containers/storages`
- [ ] **CPU**: Minimum 4 vCPU per node for production
- [ ] **RAM**: Minimum 8GB RAM per node
- [ ] **Network**: Overlay network support enabled (ports 7946, 4789 open)
- [ ] **Docker Version**: 20.10+ (`docker version`)
- [ ] **All config files present**:
  - `docker-stack-prod.yml`
  - `haproxy/haproxy-prod.cfg`
  - `traefik/traefik-prod.yml`
  - `traefik/dynamic/traefik_*.yml`
  - `redis/redis-prod.conf`
  - `rabbitmq/rabbitmq.conf`
  - `vault/vault-prod-{1,2,3}.hcl`
  - `postgres/init.sh`, `init.sql.template`, `postgresql.conf.custom`
  - `prometheus/prometheus.yml`
  - `loki/loki-config.yaml`
  - `tempo/tempo.yaml`
  - `promtail/promtail-config.yml`

---

## DEPLOYMENT EXECUTION

```bash
# 1. Create volume directories
for dir in postgres-data postgres-backup-data minio-data minio-config redis-master-data redis-replica-{1,2}-data redis-sentinel-data rabbitmq-data vault-{1,2,3}-{data,logs} traefik-{letsencrypt-data,logs} prometheus-data grafana-data loki-data tempo-data portainer redisinsight-data; do
  sudo mkdir -p /opt/containers/storages/$dir
  sudo chmod 755 /opt/containers/storages/$dir
done

# 2. Run secrets initialization (generates all Docker secrets)
bash init-production-secrets.sh

# 3. Create overlay networks (if not already created)
docker network create --driver overlay traefik-public || true
docker network create --driver overlay shared-network || true
docker network create --driver overlay observability --opt encrypted=true || true

# 4. Apply node labels for placement constraints
docker node update --label-add vault-node-1=true MANAGER_NODE_ID

# 5. Deploy the stack
docker stack deploy --compose-file docker-stack.yml production
```

---

## IMMEDIATE POST-DEPLOYMENT VALIDATION (0-5 minutes)

### Services Status
```bash
# Should see all services deploying or running
docker stack ps production --no-trunc | head -30

# All services started check:
docker service ls --filter label=com.docker.stack.namespace=production \
  --format "{{.Name}}\t{{.Replicas}}\t{{.Mode}}"

# Expected output (sample):
# production_adminer          1/1        replicated
# production_grafana          1/1        replicated
# production_haproxy          1/1        replicated
# production_imgproxy         2/2        replicated
# production_loki             1/1        replicated
# production_minio            1/1        replicated
# production_postgres         1/1        replicated
# production_portainer        1/1        replicated
# production_prometheus       1/1        replicated
# production_promtail         3/3        global
# production_rabbitmq         1/1        replicated
# production_redis-master     1/1        replicated
# production_redis-sentinel   3/3        replicated
# production_traefik          3/3        replicated
# production_vault-1          1/1        replicated
# production_vault-2          1/1        replicated
# production_vault-3          1/1        replicated
```

### Ingress Health
```bash
# HAProxy stats page (if accessible)
docker exec $(docker ps -q -f label=com.docker.swarm.service.name=production_haproxy) \
  curl -s http://localhost:8404/stats 2>/dev/null | grep "traefik" | head -5

# Expected: Should see "traefik" servers with "UP" status
```

#### Traefik Health
```bash
# Traefik ping endpoint (through HAProxy)
curl -s -H "Host: traefik.cyberstarsng.com" http://localhost/ping
# Expected: OK

# Or directly to one Traefik replica
TRAEFIK_IP=$(docker exec $(docker ps -q -f label=com.docker.swarm.service.name=production_traefik | head -1) hostname -i)
curl -s http://$TRAEFIK_IP:8080/ping
# Expected: OK
```

---

## COMPONENT HEALTH CHECKS (5-15 minutes)

### PostgreSQL
```bash
# Container is running and healthy
docker service logs production_postgres | grep "database system is ready"

# Check health
docker exec $(docker ps -q -f label=com.docker.swarm.service.name=production_postgres) \
  pg_isready -U proptech -d proptech

# Connect to database (if needed)
docker exec -it $(docker ps -q -f label=com.docker.swarm.service.name=production_postgres) \
  psql -U proptech -d proptech -c "SELECT version();"
```

### Redis Master & Replicas
```bash
# Red is master running
docker service logs production_redis-master | grep "The server is now ready"

# Check master status
docker exec $(docker ps -q -f label=com.docker.swarm.service.name=production_redis-master) \
  redis-cli -a $(docker secret inspect redis_root_password --format '{{.Spec.Data}}' | base64 -d) \
  INFO replication

# Check replicas (should show 0 if only master exists)
# Expected output: role:master, connected_slaves:0
```

### Redis Sentinel (HA Monitor)
```bash
# Should have 3 healthy sentinels
docker service ls -f name=production_redis-sentinel

# Check sentinel masters list
docker exec $(docker ps -q -f label=com.docker.swarm.service.name=production_redis-sentinel | head -1) \
  redis-cli -p 26379 -a $(docker secret inspect redis_root_password --format '{{.Spec.Data}}' | base64 -d) \
  SENTINEL masters

# Expected: Should see "mymaster" with 2 qorum votes
```

### RabbitMQ
```bash
# Check management API
docker exec $(docker ps -q -f label=com.docker.swarm.service.name=production_rabbitmq) \
  rabbitmq-diagnostics ping

# Check cluster status
docker exec $(docker ps -q -f label=com.docker.swarm.service.name=production_rabbitmq) \
  rabbitmq-diagnostics status 2>&1 | head -20

# Expected: Status line showing "RabbitMQ running"
```

### MinIO
```bash
# Check health endpoint
docker exec $(docker ps -q -f label=com.docker.swarm.service.name=production_minio) \
  curl -s http://localhost:9000/minio/health/live
# Expected: HTTP 200

# Check buckets
docker exec $(docker ps -q -f label=com.docker.swarm.service.name=production_minio) \
  mc alias set local http://localhost:9000 minioadmin $(docker secret inspect minio_root_password --format '{{.Spec.Data}}' | base64 -d) && \
  mc ls local/
# Expected: Should see "tempo/" and "postgres-backups/" buckets
```

### Vault Cluster
```bash
# Check vault-1 unsealed status
docker exec $(docker ps -q -f label=com.docker.swarm.service.name=production_vault-1) \
  vault status
# Expected: Unsealed: true, Raft Leadership: true (for leader)

# List Raft peers
docker exec $(docker ps -q -f label=com.docker.swarm.service.name=production_vault-1) \
  vault operator raft list-peers
# Expected: All 3 nodes listed with "leader" and "follower" roles

# Check cluster health
docker exec $(docker ps -q -f label=com.docker.swarm.service.name=production_vault-1) \
  vault status | grep -E "Sealed|Nodes|Node ID"
```

### Prometheus
```bash
# Check configuration loaded
docker exec $(docker ps -q -f label=com.docker.swarm.service.name=production_prometheus) \
  curl -s http://localhost:9090/-/healthy
# Expected: Prometheus is Healthy

# Check targets
docker service logs production_prometheus | grep "Loading configuration"

# View targets in web UI or API
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets | length'
# Expected: Should see multiple active targets
```

### Grafana
```bash
# Health check
docker exec $(docker ps -q -f label=com.docker.swarm.service.name=production_grafana) \
  curl -s http://localhost:3000/api/health
# Expected: database_ok: true

# Check datasources loaded
docker exec $(docker ps -q -f label=com.docker.swarm.service.name=production_grafana) \
  curl -s -H "Authorization: Bearer admin" http://localhost:3000/api/datasources 2>&1 | head
```

### Loki
```bash
# Readiness check
docker exec $(docker ps -q -f label=com.docker.swarm.service.name=production_loki) \
  curl -s http://localhost:3100/ready
# Expected: OK

# Query logs (should have some from startup)
curl -s "http://localhost:3100/loki/api/v1/query?query={job%3D%22docker%22}" | jq '.data.result | length'
```

### Tempo
```bash
# Status check
docker exec $(docker ps -q -f label=com.docker.swarm.service.name=production_tempo) \
  curl -s http://localhost:3200/status
# Expected: HTTP 200 with version info

# Check WAL directory
docker exec $(docker ps -q -f label=com.docker.swarm.service.name=production_tempo) \
  ls -lah /var/tempo/
```

### Promtail
```bash
# Check readiness (should be on all nodes in global mode)
docker service ls -f name=production_promtail
# Expected: Replicas should show N/N (e.g., 3/3 for 3-node cluster)

docker service logs production_promtail | grep -i "started processing" | head -3
```

---

## NETWORK & SERVICE DISCOVERY

### Network Verification
```bash
# Check networks created
docker network ls | grep -E "traefik-public|shared-network|observability"

# Verify backend network is internal
docker network inspect production_backend | jq '.Internal'
# Expected: true

# Verify encryption on backend & observability
docker network inspect production_backend --format '{{json .DriverOpts}}' | grep encrypted
docker network inspect production_observability --format '{{json .DriverOpts}}' | grep encrypted
# Expected: "encrypted": "true"
```

### Service Discovery (DNS Resolution)
```bash
# From inside a container, verify DNS works
docker exec $(docker ps -q -f label=com.docker.swarm.service.name=production_postgres) \
  nslookup redis-master.production.backend

# Expected: Should resolve to virtual IP (10.0.x.x typically)

# Test service discovery from Traefik
docker exec $(docker ps -q -f label=com.docker.swarm.service.name=production_traefik -m 1) \
  nslookup tasks.rabbitmq

# Expected: Should resolve to multiple A records (one per replica)
```

---

## PERSISTENCE & DATA

### Volume Mounts
```bash
# Verify all volumes are properly bound
docker volume ls | grep production | wc -l
# Expected: Should show many volumes

# Check specific volume
docker volume inspect production_postgres_data | jq '.Mountpoint'
# Expected: Should show path like /opt/containers/storages/postgres-data
```

### PostgreSQL Data
```bash
# Check database exists
docker exec $(docker ps -q -f label=com.docker.swarm.service.name=production_postgres) \
  psql -U proptech -l | grep proptech
# Expected: Should show "proptechdb" and "quartzdb"

# Check users/roles created
docker exec $(docker ps -q -f label=com.docker.swarm.service.name=production_postgres) \
  psql -U proptech -d proptech -c "\du"
# Expected: Should show "proptech", "proptechro", "proptechapp" roles
```

### Redis Persistence
```bash
# Check RDB and AOF files
docker exec $(docker ps -q -f label=com.docker.swarm.service.name=production_redis-master) \
  ls -lah /data/
# Expected: Should show "dump.rdb" and "appendonly.aof"
```

---

## SECURITY CHECKS

### Secrets Management
```bash
# Verify no secrets in environment variables
docker exec $(docker ps -q -f label=com.docker.swarm.service.name=production_postgres) \
  env | grep -i password
# Expected: Should NOT show any database passwords

# Secrets should be in /run/secrets
docker exec $(docker ps -q -f label=com.docker.swarm.service.name=production_postgres) \
  ls -1 /run/secrets/ | head
# Expected: Should see db_name, db_user, postgres_password, etc.
```

### TLS/SSL
```bash
# Check Traefik HTTPS readiness (once Let's Encrypt cert obtained)
docker exec $(docker ps -q -f label=com.docker.swarm.service.name=production_traefik -m 1) \
  ls -lah /letsencrypt/acme.json
# Expected: File should exist with 0644 permissions

# Verify certificate issuer (after first request)
curl -s -I https://traefik.cyberstarsng.com 2>/dev/null | grep -i strict-transport
```

### Network Isolation
```bash
# Verify backend network is internal (no outbound access)
docker exec $(docker ps -q -f label=com.docker.swarm.service.name=production_postgres) \
  ping -c 1 8.8.8.8
# Expected: Should FAIL (no external network access)

# Backend services should reach other backend services
docker exec $(docker ps -q -f label=com.docker.swarm.service.name=production_postgres) \
  ping -c 1 redis-master
# Expected: Should SUCCEED
```

### Read-Only Configs
```bash
# Verify configs are mounted read-only
docker inspect $(docker ps -q -f label=com.docker.swarm.service.name=production_traefik -m 1) \
  | jq '.Mounts[] | select(.Mode | contains("ro"))'
# Expected: Should see ro flags for config mounts
```

---

## PERFORMANCE BASELINE

### Resource Utilization
```bash
# Check memory usage per service
docker stats --no-stream --format "table {{.Container}}\t{{.MemUsage}}\t{{.CPUPerc}}" \
  $(docker ps -q -f label=com.docker.stack.namespace=production)

# Expected (approximate):
# - Traefik: 50-150MB
# - Prometheus: 200-500MB
# - Grafana: 100-200MB
# - PostgreSQL: 500MB-2GB
# - RabbitMQ: 300-800MB (depending on queue load)
# - Vault: 100-200MB each
# - Redis: 50-300MB (depends on data size)
```

### Disk Usage
```bash
# Check container storage
du -sh /opt/containers/storages/*

# Expected breakdown:
# - postgres-data: 100MB-10GB+ (DB size dependent)
# - redis-*-data: 50MB-5GB+ (data size dependent)
# - minio-data: 100MB-unlimited
# - prometheus-data: 100MB-50GB (retention-dependent)
# - traefik-letsencrypt-data: < 1MB
# - grafana-data: 50-200MB
```

---

## LOAD & STRESS TESTING

### HAProxyDynamic Backend Discovery
```bash
# Scale Traefik to test HAProxy discovery
docker service scale production_traefik=5

# Wait 30 seconds for DNS to update
sleep 30

# Check HAProxy sees all replicas  
docker exec $(docker ps -q -f label=com.docker.swarm.service.name=production_haproxy) \
  curl -s http://localhost:8404/stats | grep "server-template" | wc -l
# Expected: Should show >=5 traefik servers

# Scale back down
docker service scale production_traefik=3
```

### Redis Failover Test
```bash
# Kill Redis master
docker kill $(docker ps -q -f label=com.docker.swarm.service.name=production_redis-master)

# Wait 10 seconds for Sentinel failover
sleep 10

# Check new master elected
docker exec $(docker ps -q -f label=com.docker.swarm.service.name=production_redis-sentinel -m 1) \
  redis-cli -p 26379 -a $(docker secret inspect redis_root_password --format '{{.Spec.Data}}' | base64 -d) \
  SENTINEL masters | grep -E "name|addr|port"

# Container should auto-restart and rejoin
docker service logs production_redis-master | tail -5
```

### Vault Failover Test
```bash
# Kill the Vault leader
docker kill $(docker ps -q -f label=com.docker.swarm.service.name=production_vault-1)

# Wait 10 seconds
sleep 10

# Check leadership changed on remaining nodes
docker exec $(docker ps -q -f label=com.docker.swarm.service.name=production_vault-2) \
  vault operator raft list-peers

# Check node auto-restarts
docker service logs production_vault-1 | tail -5 | grep -i "started\|running"
```

---

## OPERATIONAL MONITORING (Ongoing)

### Daily Checks
```bash
# Service health
docker stack ps production | grep -v Running

# Recent errors
docker service logs production_postgres --tail 50 | grep -i error
docker service logs production_traefik --tail 50 | grep -i error
docker service logs production_vault-1 --tail 50 | grep -i error

# Disk usage trending
du -sh /opt/containers/storages/* | tail -5
```

### Weekly Checks
```bash
# Backup verification
ls -lah /opt/containers/storages/postgres-backup-data/ | tail -5

# Restore from backup test (on staging)
# Verify backup encryption works

# Certificate expiry
docker exec $(docker ps -q -f label=com.docker.swarm.service.name=production_traefik -m 1) \
  curl -s https://traefik.cyberstarsng.com/metrics 2>&1 | grep expires
```

### Monthly Checks
```bash
# Disaster recovery drill
# Test Vault initialization from backup
# Test PostgreSQL restore from S3 backup
# Test Vault secrets rotation

# Performance review
# Compare metrics baseline with current
# Identify optimization opportunities

# Security audit
# Review secrets rotation
# Audit Docker config changes
# Verify no credentials in logs
```

---

## TROUBLESHOOTING QUICK REF

| Symptom | Check | Fix |
|---------|-------|-----|
| Services stuck in "pending" | `docker service ps production_SERVICE` | Check resource limits, node availability |
| HAProxy not routing | `curl http://localhost:8404/stats` | Scale Traefik, check health checks |
| Redis failover not working | `docker exec -it sentinel SENTINEL masters` | Verify 3 sentinels running, check network |
| Vault cluster split | `vault operator raft list-peers` on each node | Verify Raft addresses, check network |
| High memory usage | `docker stats` per service | Increase limits or add replicas |
| Disk full | `df -h /opt` | Archive old Prometheus data to S3 |
| No logs | Check Loki → Promtail → Docker logs | Restart promtail, verify network |
| Certificate not renewing | Check Traefik logs | Verify ACME challenge setup, ports 80/443 |

---

## Sign-Off

- [ ] All services running and healthy
- [ ] Core services tested (DB, Cache, Secrets, Message Queue)
- [ ] HAProxy/Traefik load balancing verified
- [ ] High availability components tested
- [ ] Backup systems operational
- [ ] Monitoring & logging functional
- [ ] Security controls validated
- [ ] Documentation updated with actual endpoints
- [ ] On-call runbook distributed
- [ ] Team trained on incident response

**Deployment Date**: _______________  
**Deployed By**: _______________  
**Validated By**: _______________  
**Sign-Off**: _______________

---

## Kubernetes validation (GitOps)

After syncing [kubernetes/](./kubernetes/) via Argo CD:

### Cluster bootstrap
- [ ] Namespaces exist: `ingress`, `platform-data`, `platform-tools`, `observability`, `apps-staging`
- [ ] MetalLB pool assigned; Traefik Service has EXTERNAL-IP
- [ ] cert-manager ClusterIssuer `letsencrypt-prod` Ready
- [ ] Longhorn volumes bound for stateful pods

### Platform-data
```bash
kubectl get cluster -n platform-data proptech-pg
kubectl get redisreplication,redissentinel -n platform-data
kubectl get rabbitmqcluster -n platform-data
kubectl get tenant -n platform-data
kubectl exec -n platform-data vault-0 -- vault status
```
- [ ] CNPG cluster 3/3 instances healthy
- [ ] Redis Sentinel failover test (delete master pod)
- [ ] RabbitMQ 3-node cluster `kubectl exec ... rabbitmq-diagnostics ping`
- [ ] MinIO buckets: tempo, postgres-backups, proptech-pub

### Observability
```bash
kubectl get pods -n observability
kubectl port-forward -n observability svc/kube-prometheus-prometheus 9090:9090
```
- [ ] Prometheus targets UP for apps (ServiceMonitors)
- [ ] Grafana datasources: Prometheus, Loki, Tempo
- [ ] Fluent Bit pods Running on all nodes
- [ ] Tempo traces visible in Grafana

### Ingress
```bash
kubectl get ingressroute -n ingress
curl -I https://staging.api.primecrib.app
curl -I https://grafana.cyberstarsng.com
```
- [ ] TLS certificates issued (cert-manager / Traefik ACME)
- [ ] Staging app routes return 200

### Applications (apps-staging)
```bash
kubectl get deploy,hpa,pdb -n apps-staging
kubectl logs -n apps-staging deploy/gateway-service --tail=50
kubectl logs -n apps-staging deploy/proptech-core-service --tail=50
```
- [ ] All Deployments Available
- [ ] Readiness probes passing
- [ ] ExternalSecrets synced (`kubectl get externalsecret -A`)

### GitOps CI
- [ ] Workflow `deploy_target: kubernetes` bumps `primecrib-gitops/apps/*/overlays/*`
- [ ] Trivy scan passes (no CRITICAL)
- [ ] Argo CD auto-sync deploys new image tag

See [kubernetes/MIGRATION.md](./kubernetes/MIGRATION.md) for cutover steps.


