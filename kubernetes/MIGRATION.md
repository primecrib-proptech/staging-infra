# Swarm to Kubernetes Migration

Migrate from [docker-stack.yml](../docker-stack.yml) to manifests in this directory.

## Phase 0: Cluster bootstrap

Follow **[KUBERNETES_VPS_SETUP.md](./KUBERNETES_VPS_SETUP.md)** for full VPS install steps (staging 1 VPS or production 3 VPS).

1. Install RKE2 ([scripts/install-rke2-staging.sh](./scripts/install-rke2-staging.sh) for single-node staging).
2. Install Cilium, Longhorn (default StorageClass).
3. Install Argo CD; apply [primecrib-gitops/bootstrap/root-application.yaml](../../../primecrib-gitops/bootstrap/root-application.yaml).
4. Ensure GitHub repos exist: `cyberstarsng/primecrib-gitops`, `cyberstarsng/staging-infra` (Argo `repoURL` values are preconfigured).
5. Add `GITOPS_PAT` on each service repo for cross-repo image tag bumps.
6. Patch [bootstrap/metallb.yaml](./bootstrap/metallb.yaml) VIP to your network.

## Phase 1: Platform (parallel to Swarm)

1. Sync Argo apps: operators → platform-data → observability → ingress.
2. Run [scripts/init-k8s-secrets.sh](./scripts/init-k8s-secrets.sh) after Vault is unsealed.
3. Verify CNPG cluster, Redis Sentinel, RabbitMQ, MinIO buckets, Vault HA.

## Phase 2: Data migration

| Data | Method |
|------|--------|
| PostgreSQL | `pg_dump` from Swarm → restore to CNPG primary |
| Redis | Accept cache warm-up OR RDB export/import |
| RabbitMQ | Shovel/federation bridge during cutover |
| MinIO | `mc mirror` from Swarm volume to K8s tenant |

## Phase 3: Apps

1. Deploy staging apps via Argo (`apps-staging` Applications).
2. Run E2E against K8s ingress (staging hostnames).
3. GitHub Actions: `workflow_dispatch` with `deploy_target: kubernetes`.

## Phase 4: DNS cutover

1. Lower TTL to 300s on `*.primecrib.app`, `*.cyberstarsng.com`.
2. Point API/app hosts to MetalLB VIP.
3. Monitor gateway 5xx and Postgres replication lag.

## Rollback

1. Revert DNS to Swarm HAProxy VIP.
2. Scale K8s app Deployments to 0 (keep data plane for forensics).
3. `docker stack deploy` on staging-infra if stacks were kept.

## Post-migration

- Set repo variable `DEFAULT_DEPLOY_TARGET=kubernetes` when Swarm is retired.
- Remove SSH deploy jobs from service workflows.
