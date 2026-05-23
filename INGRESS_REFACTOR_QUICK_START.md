# Ingress Configuration Refactor - Quick Start Guide

**TL;DR:** Environment-aware ingress routes. Deploy staging OR production. One overlay at a time.

---

## Quick Facts

| Aspect | Details |
|--------|---------|
| **What** | Kubernetes ingress routes refactored for environment isolation |
| **Why** | Eliminate 50% route duplication, prevent staging/prod pollution |
| **How** | Kustomize overlays with strategic merge patches |
| **When** | Use immediately for new deployments |
| **Where** | `/kubernetes/ingress/base/` and `/kubernetes/ingress/overlays/` |

---

## 5-Minute Overview

### The Problem
Before: 3 separate route files, duplicated 50%
```
primecrib-staging.yaml (128 lines)
primecrib-prod.yaml (93 lines)
infra-routes.yaml (210 lines)
```

### The Solution
After: Single base + environment overlays
```
base/ingress-routes.yaml (370 lines - staging as default)
overlays/staging/kustomization.yaml (30 lines)
overlays/production/kustomization.yaml (70 lines - patches only)
```

### Key Insight
**Base = Staging (default)**  
**Production = Base + Patches**

Example:
- Base has: `Host(staging.api.primecrib.app)` + namespace `apps-staging`
- Production patches to: `Host(api.primecrib.app)` + namespace `apps-prod`

---

## Deployment (Copy-Paste Commands)

### Deploy to Staging
```bash
# Build first (verify output)
kustomize build kubernetes/ingress/overlays/staging > /tmp/staging.yaml

# Dry run (no actual deployment)
kubectl apply -k kubernetes/ingress/overlays/staging \
  --dry-run=client \
  -n ingress

# Deploy (actual)
kubectl apply -k kubernetes/ingress/overlays/staging -n ingress

# Verify
kubectl get ingressroute -n ingress -L environment
# Shows: ENVIRONMENT=staging
```

### Deploy to Production
```bash
# Backup first
kubectl get ingressroute -n ingress -o yaml > /tmp/prod-backup-$(date +%s).yaml

# Build first (verify output)
kustomize build kubernetes/ingress/overlays/production > /tmp/production.yaml

# Dry run (no actual deployment)
kubectl apply -k kubernetes/ingress/overlays/production \
  --dry-run=client \
  -n ingress

# Deploy (actual)
kubectl apply -k kubernetes/ingress/overlays/production -n ingress

# Verify
kubectl get ingressroute -n ingress -L environment
# Shows: ENVIRONMENT=production
```

---

## What Gets Deployed?

### Staging
```
Hostnames:
  ✅ staging.api.primecrib.app
  ✅ staging.primecrib.app
  ✅ staging.admin.primecrib.app
  ✅ primecrib.app + www.primecrib.app (pitch)
  ✅ proptech-api.cyberstarsng.com
  ✅ grafana.cyberstarsng.com (infra)
  ✅ ... other infrastructure services

Namespaces:
  ✅ apps-staging (for app services)
  ✅ platform-data, observability, platform-tools (for infra)
```

### Production
```
Hostnames:
  ✅ api.primecrib.app              (NOT staging.api...)
  ✅ www.primecrib.app              (NOT staging.primecrib.app)
  ✅ admin.primecrib.app            (NOT staging.admin...)
  ✅ primecrib.app                  (pitch - no www)
  ✅ proptech-api.cyberstarsng.com  (unchanged)
  ✅ grafana.cyberstarsng.com       (infra - unchanged)
  ✅ ... other infrastructure services

Namespaces:
  ✅ apps-prod (for app services)
  ✅ platform-data, observability, platform-tools (for infra)
```

---

## File Organization

### Base Configuration (Shared)
```
kubernetes/ingress/base/
├── kustomization.yaml           ← Orchestrates base
├── ingress-routes.yaml          ← All routes (staging default)
├── ingress-values.yaml          ← Service metadata reference
├── cert-issuer.yaml             ← Certificate resolver
└── middlewares/                 ← Shared middleware definitions
```

### Staging Overlay (Explicit)
```
kubernetes/ingress/overlays/staging/
└── kustomization.yaml           ← Explicit ENVIRONMENT=staging
```

### Production Overlay (Patches)
```
kubernetes/ingress/overlays/production/
└── kustomization.yaml           ← ENVIRONMENT=production + patches
```

---

## Common Tasks

### Add a New Service

**Example:** Add service `foo.primecrib.app`

**Step 1:** Add to base/ingress-values.yaml (reference)
```yaml
appServices:
  - name: foo
    displayName: foo
    serviceName: foo-service
    port: 3000
    middlewares: [...]
```

**Step 2:** Add IngressRoute to base/ingress-routes.yaml (staging)
```yaml
---
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: foo
  namespace: ingress
  annotations:
    environment: "staging"
spec:
  entryPoints: [websecure]
  routes:
    - match: Host(`staging.foo.primecrib.app`)
      kind: Rule
      services:
        - name: foo-service
          namespace: apps-staging
          port: 3000
      middlewares: [...]
  tls:
    certResolver: letsencrypt
```

**Step 3:** Add patch to overlays/production/kustomization.yaml (production override)
```yaml
patchesStrategicMerge:
  - apiVersion: traefik.io/v1alpha1
    kind: IngressRoute
    metadata:
      name: foo
    spec:
      routes:
        - match: Host(`foo.primecrib.app`)
          services:
            - namespace: apps-prod
```

**Done!** Service scales automatically to both environments.

### Verify Current Environment

```bash
kubectl get configmap ingress-environment -n ingress -o jsonpath='{.data.ENVIRONMENT}'
# Output: staging or production
```

### View All Routes

```bash
# Show route hostnames
kubectl get ingressroute -n ingress -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.routes[0].match}{"\n"}{end}'

# Show with environment label
kubectl get ingressroute -n ingress -L environment
```

### Rollback to Previous

```bash
# If deployment went wrong
kubectl apply -f /tmp/prod-backup-*.yaml
```

---

## Validation

### Pre-Deployment Checklist

- [ ] Kustomize builds without errors: `kustomize build kubernetes/ingress/overlays/staging`
- [ ] Staging hostnames correct: `grep "staging\." /tmp/staging-output.yaml`
- [ ] Production hostnames correct: `grep -v "staging\." /tmp/production-output.yaml`
- [ ] No staging hostnames in production build
- [ ] No duplicate hostnames

### Post-Deployment Checklist

- [ ] Routes created: `kubectl get ingressroute -n ingress`
- [ ] Environment set: `kubectl get configmap ingress-environment -n ingress`
- [ ] DNS resolves: `nslookup api.primecrib.app` (or staging.api.primecrib.app)
- [ ] HTTPS works: `curl -I https://api.primecrib.app`
- [ ] Backend services responding: Check app service logs
- [ ] Certificates valid: `kubectl get certificate -n ingress`

---

## Troubleshooting

### Routes not appearing
```bash
# Check if Traefik CRD is installed
kubectl get crd | grep traefik

# Check IngressRoute creation
kubectl get ingressroute -n ingress

# Check Traefik logs
kubectl logs -f -n ingress -l app.kubernetes.io/name=traefik | grep -i error
```

### Certificate not created
```bash
# Check cert-manager
kubectl get certificate -n ingress

# Check cert-manager logs
kubectl logs -f -n cert-manager -l app=cert-manager

# Verify DNS
nslookup api.primecrib.app
```

### 502 Bad Gateway
```bash
# Check backend service
kubectl get svc -n apps-prod | grep gateway-service

# Check pods running
kubectl get pods -n apps-prod

# Check service endpoints
kubectl get endpoints gateway-service -n apps-prod
```

---

## Documentation Links

| Document | Purpose |
|----------|---------|
| `INGRESS_REFACTOR_ANALYSIS.md` | Problem analysis + solution strategy |
| `INGRESS_REFACTOR_IMPLEMENTATION.md` | Detailed implementation guide |
| `INGRESS_REFACTOR_DETAILED_DIFF.md` | Before/after comparisons |
| `INGRESS_REFACTOR_TESTING.md` | Validation procedures |
| `INGRESS_REFACTOR_EXECUTIVE_SUMMARY.md` | High-level overview |
| `validate-ingress-refactor.sh` | Validation script |

---

## Q&A

**Q: Can I deploy both staging and production at the same time?**  
A: No. You choose ONE overlay per cluster. Staging and production should be on different clusters.

**Q: What if I need a different middleware for production?**  
A: Patch it in `overlays/production/kustomization.yaml`. Same pattern as hostnames.

**Q: Can I add a third environment?**  
A: Yes! Create `overlays/qa/kustomization.yaml` with QA-specific patches.

**Q: Do I need to modify this for each new service?**  
A: Only add 3 small sections: values definition, base route, production patch. No duplication.

**Q: What about backwards compatibility?**  
A: Old route files (`primecrib-staging.yaml`, `primecrib-prod.yaml`) are kept as reference. Delete after successful deployment.

---

## Next Steps

1. **Review:** Read `INGRESS_REFACTOR_IMPLEMENTATION.md` for full context
2. **Validate:** Run `validate-ingress-refactor.sh` to check configuration
3. **Test Staging:** Deploy to staging cluster first
4. **Test Production:** Deploy to production cluster (after staging succeeds)
5. **Monitor:** Watch for 24-48 hours for any issues
6. **Cleanup:** Archive old route files after successful deployment

---

## Support

If you encounter issues:

1. Check `INGRESS_REFACTOR_TESTING.md` for troubleshooting
2. Review logs: `kubectl logs -f -n ingress -l app.kubernetes.io/name=traefik`
3. Run validation: `validate-ingress-refactor.sh`
4. Compare outputs: `kustomize build kubernetes/ingress/overlays/staging > staging.yaml`

---

**Ready to deploy?** Start with:
```bash
kubectl apply -k kubernetes/ingress/overlays/staging --dry-run=client -n ingress
```


