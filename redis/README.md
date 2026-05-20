## Future Cluster Configuration Notes

This stack currently runs single-instance services, but is prepped for future clustering.
Use this section as the reference when moving to 3-node HA.

---

### RabbitMQ (Quorum-ready cluster)

#### Current readiness in stack
- `docker-stack.yml` uses one `rabbitmq` service with:
  - `RABBITMQ_ERLANG_COOKIE` sourced from secret `rabbit_erlang_cookie`
  - DNS peer discovery-ready config in `rabbitmq/rabbitmq.conf`
- `rabbitmq.conf` includes:
  - `cluster_formation.peer_discovery_backend = rabbit_peer_discovery_dns`
  - `cluster_formation.dns.hostname = tasks.rabbitmq`
  - `cluster_partition_handling = pause_minority`
  - `cluster_formation.target_cluster_size_hint = 3`

#### Scale to cluster
1. Keep same service (`rabbitmq`) and increase replicas to 3:
   - `deploy.replicas: 3`
2. Ensure secret exists and is same for all nodes:
   - `rabbit_erlang_cookie`
3. Verify cluster:
   - `rabbitmqctl cluster_status`
4. Use quorum queues (policy):
   - Example:
     `rabbitmqctl set_policy quorum-all ".*" '{"queue-type":"quorum"}' --apply-to queues`

> Note: switching existing classic queues to quorum requires migration planning.

---

### Vault (Raft HA cluster)

#### Important
Vault should **not** be scaled by only increasing `replicas` in current single-service setup.
For robust HA in Swarm, use **3 distinct Vault services** (`vault-1`, `vault-2`, `vault-3`) with:
- unique persistent volume per node
- unique `node_id`
- stable DNS/addresses
- `retry_join` blocks

#### Example `vault.hcl` pattern (per node)
ui = true
disable_mlock = false

api_addr = "https://vault-1.example.internal:8200"
cluster_addr = "https://vault-1.example.internal:8201"

listener "tcp" {
  address         = "0.0.0.0:8200"
  cluster_address = "0.0.0.0:8201"
  tls_disable     = 0
  tls_cert_file   = "/vault/certs/vault.crt"
  tls_key_file    = "/vault/certs/vault.key"
  tls_client_ca_file = "/vault/certs/vault-ca.pem"
}

storage "raft" {
  path    = "/vault/data"
  node_id = "vault-1"

  retry_join { leader_api_addr = "https://vault-1.example.internal:8200" }
  retry_join { leader_api_addr = "https://vault-2.example.internal:8200" }
  retry_join { leader_api_addr = "https://vault-3.example.internal:8200" }
}


Bootstrap sequence
Start vault-1, init/unseal.
Start vault-2 and vault-3, join raft + unseal.
Verify:
vault operator raft list-peers
Put traffic behind one VIP/Traefik route to active leader.


Redis (future Redis Cluster)
Current readiness in stack
Redis starts with:
--requirepass and --masterauth from secret
redis.conf includes cluster parameters but currently:
cluster-enabled no
When moving to cluster
Change in redis.conf:
cluster-enabled yes
Run 6 nodes minimum for production cluster:
3 masters + 3 replicas
Ensure node-to-node gossip port is reachable:
6379 and 16379 (cluster bus)
Create cluster:
redis-cli --cluster create <node1:6379> ... <node6:6379> --cluster-replicas 1 -a <password>
Verify:
redis-cli -a <password> cluster info
redis-cli -a <password> cluster nodes
> Redis Cluster is not the same as Sentinel. Cluster is sharding + HA; Sentinel is failover for master-replica.
Storage requirements for all clusters
Do not rely on single-node bind mount for HA.
Use either:
replicated storage backend, or
app-level replication with per-node local volumes and tested backup/restore.
If you want, I can also provide a shorter “ops checklist” version (one-page runbook style).



What changed
Kept existing redis service as the master (replicas: 1).
Added redis-replica service, but disabled for now:
deploy.replicas: 0 (enable later when ready).
Added redis-sentinel service:
starts Sentinel with generated runtime config
monitors mymaster at redis:6379
currently quorum 1 for single-sentinel mode
set this to 2 when you scale sentinel replicas to 3.
Added new volume definition:
redis_replica_data -> /opt/containers/storages/redis-replica-data