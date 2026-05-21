# Single-node overlay

Use this overlay when running the full platform on **one VPS** (staging).

Argo CD Applications should reference:

| Component | Path / values file |
|-----------|-------------------|
| platform-data | `kubernetes/overlays/single-node` |
| Vault Helm | `kubernetes/overlays/single-node/vault-helm-values.yaml` |
| Traefik Helm | `kubernetes/overlays/single-node/traefik-helm-values.yaml` |
| Longhorn | `defaultReplicaCount: "1"` in Argo Helm values |

Production clusters (3+ nodes) should use `kubernetes/platform-data` and the default HA Helm values under `kubernetes/platform-data/vault/` and `kubernetes/ingress/helm/`.
