#!/usr/bin/env bash
# RKE2 cluster prep checklist (run on each node as root).
# See kubernetes/README.md and MIGRATION.md.
set -euo pipefail

echo "=== Primecrib RKE2 prep ==="
echo "1. Install RKE2: curl -sfL https://get.rke2.io | sh -"
echo "2. Label data nodes: kubectl label node <node> workload=data longhorn.io/node=true"
echo "3. Label obs nodes: kubectl label node <node> workload=observability"
echo "4. Install Longhorn, Cilium, MetalLB via Argo CD"
echo "5. Set default StorageClass: longhorn"
echo "6. Apply: kubectl apply -k kubernetes/bootstrap/"
