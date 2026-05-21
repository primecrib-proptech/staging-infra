# Kubernetes Platform (ported from staging-infra)

**Start here:** [KUBERNETES_VPS_SETUP.md](./KUBERNETES_VPS_SETUP.md) — install RKE2 on your VPS (staging 1 node, production 3+ nodes).

This directory is the Kubernetes equivalent of [docker-stack.yml](../docker-stack.yml). Config values are sourced from sibling folders (`traefik/`, `prometheus/`, `vault/`, etc.).

## Prerequisites

- RKE2 or kubeadm cluster (3 control-plane, 3+ workers)
- Cilium CNI
- Longhorn CSI (default StorageClass)
- MetalLB L2 pool for ingress VIP
- Argo CD installed (see [primecrib-gitops](https://github.com/cyberstarsng/primecrib-gitops))

**Git branch:** push this directory on the `kubernetes` branch of `cyberstarsng/staging-infra`. Argo CD uses `targetRevision: kubernetes`.

## Swarm → Kubernetes mapping

| Swarm service | K8s path | Namespace |
|---------------|----------|-----------|
| haproxy | `bootstrap/metallb.yaml` | metallb-system |
| traefik | `ingress/helm/` | ingress |
| postgres | `platform-data/postgres/` | platform-data |
| postgres-backup | CNPG ScheduledBackup | platform-data |
| rabbitmq | `platform-data/rabbitmq/` | platform-data |
| redis-* | `platform-data/redis/` | platform-data |
| minio | `platform-data/minio/` | platform-data |
| vault-1/2/3 | `platform-data/vault/` | platform-data |
| prometheus | `observability/prometheus/` | observability |
| grafana | `observability/grafana/` | observability |
| loki | `observability/loki/` | observability |
| tempo | `observability/tempo/` | observability |
| promtail | `observability/fluent-bit/` | observability |
| imgproxy | `platform-tools/imgproxy/` | platform-tools |
| adminer, redis-insight | `platform-tools/` (staging) | platform-tools |
| portainer | omitted | — |

## Network mapping

| Swarm overlay | K8s namespace |
|---------------|---------------|
| backend | platform-data |
| traefik-public | ingress |
| shared-network | cross-namespace DNS |
| observability | observability |

## Bootstrap secrets

```bash
./scripts/init-k8s-secrets.sh   # seeds Vault KV (not committed)
```

## Deploy via Argo CD

Applications are defined in [primecrib-gitops](../../../primecrib-gitops/bootstrap/).

Manual apply (bootstrap only):

```bash
kubectl apply -k kubernetes/bootstrap/
kubectl apply -k kubernetes/ingress/
```

See [MIGRATION.md](./MIGRATION.md) for cutover from Docker Swarm.

## Single-node staging overlay

For **1 VPS** clusters, use [overlays/single-node](./overlays/single-node/) (reduced replica counts). Argo CD `platform-data` on staging points to this path by default.
