# Kubernetes VPS Installation Guide

Step-by-step guide to install **RKE2 Kubernetes** on your VPS and deploy the Primecrib platform via **Argo CD GitOps**. This replaces a prior **Docker Swarm** installation.

| Environment | VPS count | Manifest profile |
|-------------|-----------|------------------|
| **Staging** | 1 | Single-node overlay ([overlays/single-node](./overlays/single-node/)) |
| **Production** | 3 minimum | Full HA manifests ([platform-data](./platform-data/)) |

**Related docs:**

- [README.md](./README.md) — manifest map
- [MIGRATION.md](./MIGRATION.md) — data migration and DNS cutover
- [primecrib-gitops/ARCHITECTURE.md](https://github.com/cyberstarsng/primecrib-gitops/blob/main/ARCHITECTURE.md) — architecture
- [primecrib-gitops/REPO_SETUP.md](https://github.com/cyberstarsng/primecrib-gitops/blob/main/REPO_SETUP.md) — publish Git repos

---

## Table of contents

1. [Overview](#1-overview)
2. [Repository requirements](#2-repository-requirements)
3. [Part A — Staging (1 VPS)](#part-a--staging-1-vps)
4. [Part B — Production (3 VPS)](#part-b--production-3-vps)
5. [Resource sizing](#5-resource-sizing)
6. [Ports and firewall](#6-ports-and-firewall)
7. [Post-install checklist](#7-post-install-checklist)
8. [Troubleshooting](#8-troubleshooting)
9. [Rollback](#9-rollback)

---

## 1. Overview

```text
                         DNS (staging.*.primecrib.app / *.primecrib.com)
                                    │
                         MetalLB VIP → Traefik (ingress)
                                    │
              ┌─────────────────────┼─────────────────────┐
              │                     │                     │
        apps-staging          apps-prod           observability
        (GitOps)              (GitOps prod)       Prometheus/Grafana/Loki
              │                     │
              └──────────┬──────────┘
                         │
                  platform-data
                  Postgres, Redis, RabbitMQ, MinIO, Vault
                         │
                    Longhorn PVCs
                         │
                    RKE2 + Cilium
```

**Stack choices (already in your repos):**

- **Kubernetes:** RKE2
- **CNI:** Cilium
- **Storage:** Longhorn
- **Load balancer:** MetalLB (replaces HAProxy VIP)
- **Ingress:** Traefik + cert-manager
- **GitOps:** Argo CD → `staging-infra` + `primecrib-gitops`

---

## 2. Repository requirements

Push these branches before installing Argo CD:

| Repository | Branch | Contents |
|------------|--------|----------|
| `cyberstarsng/staging-infra` | **`kubernetes`** | `kubernetes/*` manifests |
| `cyberstarsng/primecrib-gitops` | **`main`** | Argo apps + application deployments |

```bash
# staging-infra
cd staging-infra
git checkout kubernetes
git push origin kubernetes

# primecrib-gitops (publish from monorepo folder if needed)
cd primecrib-gitops
git push origin main
```

---

## Part A — Staging (1 VPS)

Use this path on your **single staging VPS**. You chose to **remove Swarm first**, then install Kubernetes on a clean host.

### A0. Prerequisites

| Requirement | Value |
|-------------|-------|
| OS | Ubuntu 22.04 or 24.04 LTS |
| CPU | 8 vCPU minimum |
| RAM | **32 GB** recommended (16 GB possible with reduced observability) |
| Disk | 200 GB+ SSD |
| Access | root or sudo SSH |

**Before you start:**

1. Note your VPS **public IP** (used for MetalLB and DNS).
2. Ensure DNS for staging hosts can be updated to point to this IP later.
3. Have GitHub `GITOPS_PAT` ready for CI image bumps (optional until apps deploy).

### A1. Decommission Docker Swarm

Run on the staging VPS **after backups are verified**.

#### A1.1 Export data (mandatory)

```bash
# PostgreSQL
docker exec $(docker ps -qf name=postgres) pg_dumpall -U proptech > /backup/pg-all.sql

# MinIO (if mc configured)
mc mirror local/proptech-pub /backup/minio-proptech-pub

# Vault (if unsealed)
vault operator raft snapshot save /backup/vault.snap
```

Store backups off-server (S3, another machine).

#### A1.2 Remove Swarm stacks

```bash
cd /path/to/staging-infra
docker stack rm proptech   # or your STACK_NAME
docker stack ls            # confirm empty
```

#### A1.3 Clean up (optional)

```bash
# Do NOT remove volumes until backups are confirmed
docker system prune -f     # containers/networks only
# docker volume prune      # only when data is migrated
```

Docker Engine can remain installed for debugging; RKE2 uses **containerd**.

### A2. OS preparation

```bash
sudo swapoff -a
sudo sed -i '/ swap / s/^/#/' /etc/fstab

sudo hostnamectl set-hostname staging-k8s-01

# Kernel modules (RKE2 installer usually handles this)
sudo modprobe br_netfilter overlay
```

#### Firewall (UFW example)

```bash
sudo ufw allow 22/tcp
sudo ufw allow 6443/tcp      # Kubernetes API
sudo ufw allow 9345/tcp      # RKE2 supervisor (for future nodes)
sudo ufw allow 80,443/tcp   # Ingress
sudo ufw allow 7946/tcp      # Cilium health
sudo ufw allow 8472/udp     # Cilium VXLAN
sudo ufw enable
```

Or configure equivalent rules in your cloud provider firewall.

### A3. Install RKE2 (single-server)

Use the helper script or run manually:

```bash
# From repo (on VPS after git clone) or copy script
sudo bash kubernetes/scripts/install-rke2-staging.sh
```

**Manual install:**

```bash
curl -sfL https://get.rke2.io | INSTALL_RKE2_TYPE="server" sh -
sudo mkdir -p /etc/rancher/rke2
sudo tee /etc/rancher/rke2/config.yaml <<EOF
tls-san:
  - "$(curl -s ifconfig.me)"
  - "staging-k8s-01"
write-kubeconfig-mode: "0644"
EOF
sudo systemctl enable rke2-server --now
```

**Configure kubectl:**

```bash
export KUBECONFIG=/etc/rancher/rke2/rke2.yaml
# Or for your user:
mkdir -p ~/.kube
sudo cp /etc/rancher/rke2/rke2.yaml ~/.kube/config
sudo chown $(id -u):$(id -g) ~/.kube/config

kubectl get nodes
# Expected: staging-k8s-01   Ready   control-plane,etcd,master
```

### A4. Install Cilium CNI

RKE2 ships with Canal by default. Install Cilium **before** workloads schedule:

```bash
helm repo add cilium https://helm.cilium.io/
helm repo update
helm install cilium cilium/cilium \
  --namespace kube-system \
  --set kubeProxyReplacement=true \
  --set k8sServiceHost=127.0.0.1 \
  --set k8sServicePort=6443

kubectl -n kube-system rollout status ds/cilium --timeout=300s
kubectl get pods -n kube-system
```

If RKE2 already installed Canal and pods are stuck, follow [RKE2 docs](https://docs.rke2.io/networking/basic_network_options) to disable default CNI and install Cilium only.

### A5. Patch MetalLB VIP

Edit [bootstrap/metallb.yaml](./bootstrap/metallb.yaml) **before** applying bootstrap:

```yaml
spec:
  addresses:
    - YOUR.VPS.PUBLIC.IP/32   # e.g. 203.0.113.10/32
```

Commit and push to `staging-infra` `kubernetes` branch, or patch locally then apply.

### A6. Install Argo CD

```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/v2.13.2/manifests/install.yaml
kubectl wait --for=condition=available deployment/argocd-server -n argocd --timeout=300s
```

**Get admin password:**

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d && echo
```

**Port-forward UI (optional):**

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
# https://localhost:8080  user: admin
```

#### Register Git repositories

In Argo CD UI → Settings → Repositories, add:

- `https://github.com/cyberstarsng/staging-infra.git` (branch `kubernetes`)
- `https://github.com/cyberstarsng/primecrib-gitops.git` (branch `main`)

Or via CLI:

```bash
argocd repo add https://github.com/cyberstarsng/staging-infra.git --username git --password <token>
argocd repo add https://github.com/cyberstarsng/primecrib-gitops.git --username git --password <token>
```

### A7. Bootstrap GitOps (staging = single-node)

Clone `primecrib-gitops` on your laptop or VPS:

```bash
git clone https://github.com/cyberstarsng/primecrib-gitops.git
cd primecrib-gitops

kubectl apply -f projects/primecrib.yaml
kubectl apply -f bootstrap/root-application.yaml
```

**Staging Argo paths (already configured for 1 VPS):**

| Argo Application | Source path |
|------------------|-------------|
| `platform-data` | `kubernetes/overlays/single-node` |
| `vault` (Helm values) | `kubernetes/overlays/single-node/vault-helm-values.yaml` |
| `traefik` (Helm values) | `kubernetes/overlays/single-node/traefik-helm-values.yaml` |
| `longhorn` | Helm `defaultReplicaCount: "1"` |

See [primecrib-gitops/bootstrap/applications/staging/platform-data.yaml](https://github.com/cyberstarsng/primecrib-gitops/blob/main/bootstrap/applications/staging/platform-data.yaml).

**Sync order (Argo UI or CLI):**

1. `longhorn` → `cert-manager` → `cnpg-operator` → `redis-operator` → `rabbitmq-operator` → `minio-operator` → `external-secrets`
2. `primecrib-bootstrap` (namespaces, MetalLB, network policies)
3. `platform-data` → `vault`
4. `kube-prometheus-stack` → `loki` → `tempo` → `observability-kustomize`
5. `traefik` → `ingress-routes` → `platform-tools`
6. App apps: `gateway-service-staging`, `proptech-core-service-staging`, frontends

```bash
# Watch sync status
kubectl get applications -n argocd
argocd app sync longhorn --async
# ... repeat per app or sync root
```

### A8. Longhorn default storage class

```bash
kubectl patch storageclass longhorn -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
```

### A9. Vault TLS and secrets

1. Create TLS secret for Vault (from existing `vault/cert` material or cert-manager).
2. Unseal Vault pods after `vault` Application syncs.
3. Run secrets bootstrap:

```bash
export VAULT_ADDR=https://vault.platform-data.svc:8200
export VAULT_TOKEN=<root-token>
cd staging-infra/kubernetes/scripts
./init-k8s-secrets.sh
```

4. Add GHCR pull secret to Vault for External Secrets:

```bash
vault kv put secret/platform/ghcr dockerconfigjson='{"auths":{"ghcr.io":{...}}}'
```

### A10. DNS for staging

Point records to your MetalLB VIP (VPS public IP):

| Host | Service |
|------|---------|
| `staging.api.primecrib.app` | gateway-service |
| `staging.primecrib.app` | primecrib-app |
| `staging.admin.primecrib.app` | primecrib-admin |
| `primecrib.app` / `www.primecrib.app` | primecrib-pitch |
| `proptech-api.cyberstarsng.com` | proptech-core-service |

Routes: [ingress/routes/primecrib-staging.yaml](./ingress/routes/primecrib-staging.yaml).

### A11. Deploy applications

```bash
# GitHub Actions in each service repo:
# workflow_dispatch → deploy_target: kubernetes

# Or verify Argo apps are Synced/Healthy
kubectl get pods -n apps-staging
```

---

## Part B — Production (3 VPS)

Use **three VPS instances** in the same network (private connectivity strongly recommended).

### B1. Topology

```text
  vps-1 (initial server)  <----->  vps-2 (join server)
         ^    \                      /
         |     \                    /
         +------ vps-3 (join server)

  MetalLB VIP (floating) → Traefik → apps-prod
```

Each node runs **RKE2 server** (control-plane + worker) for etcd quorum.

| Node | Hostname | Labels (after join) |
|------|----------|---------------------|
| VPS 1 | `prod-k8s-01` | `workload=data`, `longhorn.io/node=true` |
| VPS 2 | `prod-k8s-02` | `workload=data`, `longhorn.io/node=true` |
| VPS 3 | `prod-k8s-03` | `workload=observability` (optional) |

### B2. Install RKE2 — node 1 (initial)

```bash
curl -sfL https://get.rke2.io | INSTALL_RKE2_TYPE="server" sh -
sudo tee /etc/rancher/rke2/config.yaml <<EOF
tls-san:
  - "$(curl -s ifconfig.me)"
  - "prod-k8s-01"
  - "prod-k8s-02"
  - "prod-k8s-03"
write-kubeconfig-mode: "0644"
EOF
sudo systemctl enable rke2-server --now

sudo cat /var/lib/rancher/rke2/server/node-token
# Save token and vps-1 internal IP
```

### B3. Install RKE2 — nodes 2 and 3 (join)

On **each** additional VPS:

```bash
export RKE2_TOKEN="<node-token-from-vps-1>"
export RKE2_SERVER_URL="https://<vps-1-private-ip>:9345"

curl -sfL https://get.rke2.io | INSTALL_RKE2_TYPE="server" sh -
sudo systemctl enable rke2-server --now
```

Verify:

```bash
# From vps-1
export KUBECONFIG=/etc/rancher/rke2/rke2.yaml
kubectl get nodes
# 3 nodes Ready
```

### B4. Label nodes

```bash
kubectl label node prod-k8s-01 workload=data longhorn.io/node=true --overwrite
kubectl label node prod-k8s-02 workload=data longhorn.io/node=true --overwrite
kubectl label node prod-k8s-03 workload=observability --overwrite
```

### B5. Cilium, Argo CD, GitOps (HA manifests)

Follow [A4](#a4-install-cilium-cni) and [A6](#a6-install-argo-cd) on the production cluster.

**Production differences from staging:**

| Setting | Staging (1 VPS) | Production (3 VPS) |
|---------|-----------------|---------------------|
| `platform-data` Argo path | `kubernetes/overlays/single-node` | `kubernetes/platform-data` |
| Vault values file | `overlays/single-node/vault-helm-values.yaml` | `platform-data/vault/helm-values.yaml` |
| Traefik values | `overlays/single-node/traefik-helm-values.yaml` | `ingress/helm/traefik-values.yaml` |
| Longhorn `defaultReplicaCount` | `"1"` | `"3"` |
| MetalLB VIP | Staging VPS IP | Production VIP |

Patch [bootstrap/metallb.yaml](./bootstrap/metallb.yaml) with the production VIP before sync.

Apply production apps root:

```bash
kubectl apply -f bootstrap/root-application-prod.yaml
```

Platform operators and data plane still sync from `primecrib-root-staging` (shared cluster model per [primecrib-gitops/bootstrap/applications/prod/README.md](https://github.com/cyberstarsng/primecrib-gitops/blob/main/bootstrap/applications/prod/README.md)).

If production runs on a **dedicated cluster**, duplicate `bootstrap/applications/staging/*.yaml` into a `production/` folder with HA paths and unique Application names.

### B6. Production DNS

| Host | Service |
|------|---------|
| `api.primecrib.com` | gateway-service |
| `app.primecrib.com` | primecrib-app |
| `admin.primecrib.com` | primecrib-admin |
| `pitch.primecrib.com` | primecrib-pitch |

Routes: [ingress/routes/primecrib-prod.yaml](./ingress/routes/primecrib-prod.yaml).

---

## 5. Resource sizing

| Profile | Nodes | vCPU | RAM | Disk |
|---------|-------|------|-----|------|
| Staging full | 1 | 8 | 32 GB | 200 GB |
| Staging reduced | 1 | 4 | 16 GB | 120 GB (disable Loki/Tempo or reduce retention) |
| Production | 3 | 8 each | 32 GB each | 200 GB each |

---

## 6. Ports and firewall

| Port | Protocol | Purpose |
|------|----------|---------|
| 22 | TCP | SSH |
| 6443 | TCP | Kubernetes API |
| 9345 | TCP | RKE2 node join |
| 80, 443 | TCP | HTTP/HTTPS ingress |
| 10250 | TCP | Kubelet |
| 2379-2380 | TCP | etcd (on server nodes) |
| 7946 | TCP | Cilium health |
| 8472 | UDP | Cilium VXLAN |

Between production nodes, allow **all traffic** on the private network for etcd and Longhorn replication.

---

## 7. Post-install checklist

```bash
# Cluster
kubectl get nodes
kubectl get pods -A | grep -v Running

# Platform
kubectl get cluster -n platform-data proptech-pg
kubectl get redisreplication,redissentinel -n platform-data
kubectl get rabbitmqcluster -n platform-data
kubectl get tenant -n platform-data
kubectl exec -n platform-data vault-0 -- vault status

# Ingress
kubectl get svc -n ingress traefik
kubectl get ingressroute -n ingress

# Apps
kubectl get deploy -n apps-staging
kubectl get externalsecret -A

# Argo
kubectl get applications -n argocd
```

Full checklist: [VALIDATION_CHECKLIST.md](../VALIDATION_CHECKLIST.md) (Kubernetes section).

---

## 8. Troubleshooting

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| Nodes `NotReady` | CNI not installed | Install Cilium; check `kubectl -n kube-system get pods` |
| Pods `Pending` PVC | Longhorn not ready | Sync `longhorn` Argo app; check `kubectl get pods -n longhorn-system` |
| Traefik no EXTERNAL-IP | MetalLB pool wrong | Patch [metallb.yaml](./bootstrap/metallb.yaml) with correct IP |
| Argo `ComparisonError` | Wrong branch/path | Use `kubernetes` branch; staging uses `overlays/single-node` |
| Vault sealed | Not unsealed after install | `vault operator unseal` on each pod (or configure auto-unseal) |
| ExternalSecret `SecretSyncedError` | Missing Vault KV path | Run `init-k8s-secrets.sh`; add `platform/ghcr` |
| ImagePullBackOff | Private GHCR | Sync `ghcr-credentials` ExternalSecret; check Vault KV |
| CNPG 3 instances on 1 node | Wrong overlay | Argo `platform-data` path must be `kubernetes/overlays/single-node` |

**Logs:**

```bash
kubectl logs -n argocd deployment/argocd-application-controller --tail=100
kubectl describe application platform-data -n argocd
journalctl -u rke2-server -f
```

---

## 9. Rollback

If the migration fails before DNS cutover:

1. Keep Kubernetes cluster stopped or apps scaled to 0.
2. Restore Swarm from backups (see [MIGRATION.md](./MIGRATION.md)).
3. Re-point DNS to the previous Swarm/HAProxy VIP.

After DNS cutover, rollback requires DNS revert and redeploying Swarm from [docker-stack.yml](../docker-stack.yml).

---

## Quick reference — staging commands

```bash
# Install RKE2 (helper)
sudo bash kubernetes/scripts/install-rke2-staging.sh

# Bootstrap (manual, without Argo)
kubectl apply -k kubernetes/bootstrap/

# Argo root app
kubectl apply -f https://raw.githubusercontent.com/cyberstarsng/primecrib-gitops/main/projects/primecrib.yaml
kubectl apply -f https://raw.githubusercontent.com/cyberstarsng/primecrib-gitops/main/bootstrap/root-application.yaml
```

**Next:** [MIGRATION.md](./MIGRATION.md) for data import and production cutover.
