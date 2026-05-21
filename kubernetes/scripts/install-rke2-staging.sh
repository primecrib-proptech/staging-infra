#!/usr/bin/env bash
# Install RKE2 single-server cluster for staging (1 VPS).
# See ../KUBERNETES_VPS_SETUP.md for full guide.
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run as root: sudo $0"
  exit 1
fi

log() { echo "[install-rke2-staging] $*"; }

log "Disabling swap..."
swapoff -a || true
if grep -q '^[^#].*\sswap\s' /etc/fstab 2>/dev/null; then
  sed -i '/ swap / s/^/#/' /etc/fstab
fi

log "Loading kernel modules..."
modprobe br_netfilter 2>/dev/null || true
modprobe overlay 2>/dev/null || true

PUBLIC_IP="${PUBLIC_IP:-$(curl -sf ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')}"
HOSTNAME="${HOSTNAME_OVERRIDE:-$(hostname -s)}"

log "Installing RKE2 server (public IP: ${PUBLIC_IP})..."
curl -sfL https://get.rke2.io | INSTALL_RKE2_TYPE="server" sh -

mkdir -p /etc/rancher/rke2
if [[ ! -f /etc/rancher/rke2/config.yaml ]]; then
  cat > /etc/rancher/rke2/config.yaml <<EOF
tls-san:
  - "${PUBLIC_IP}"
  - "${HOSTNAME}"
write-kubeconfig-mode: "0644"
cni: none
EOF
  log "Wrote /etc/rancher/rke2/config.yaml (cni: none — install Cilium after start)"
else
  log "Keeping existing /etc/rancher/rke2/config.yaml"
fi

systemctl enable rke2-server
systemctl restart rke2-server

log "Waiting for node Ready (up to 5 min)..."
export KUBECONFIG=/etc/rancher/rke2/rke2.yaml
for i in $(seq 1 30); do
  if /var/lib/rancher/rke2/bin/kubectl get nodes 2>/dev/null | grep -q Ready; then
    /var/lib/rancher/rke2/bin/kubectl get nodes
    log "RKE2 is ready. Next steps:"
    log "  1. Install Cilium (see KUBERNETES_VPS_SETUP.md)"
    log "  2. Patch kubernetes/bootstrap/metallb.yaml with VIP ${PUBLIC_IP}/32"
    log "  3. Install Argo CD and apply primecrib-gitops bootstrap"
    exit 0
  fi
  sleep 10
done

log "Node not Ready yet. Check: journalctl -u rke2-server -f"
exit 1
