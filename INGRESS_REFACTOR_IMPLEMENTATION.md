# Kubernetes Ingress Configuration Refactor - Implementation Guide

## Overview

This refactoring converts the hardcoded, environment-duplicated ingress configuration into a **centralized, environment-aware system** using Kustomize overlays.

**Key Achievement:** Single source of truth for all routes, with environment-specific behavior controlled via overlays.

---

## Directory Structure

### Before (Current - NOT Environment-Aware)
```
kubernetes/ingress/
├── routes/
│   ├── infra-routes.yaml          ← All infra services hardcoded
│   ├── primecrib-staging.yaml     ← Staging routes (full duplication)
│   └── primecrib-prod.yaml        ← Production routes (full duplication)
├── middlewares/
├── cert-issuer.yaml
└── kustomization.yaml
```

**Problem:** Routes are duplicated across files. To add a new service, you must edit both staging AND production files.

### After (Refactored - Environment-Aware)
```
kubernetes/ingress/
├── base/                          ← NEW: Shared base configuration
│   ├── kustomization.yaml         ← Kustomize config with environment variables
│   ├── cert-issuer.yaml           ← Copied from parent (environment-independent)
│   ├── middlewares/               ← Copied from parent (shared middlewares)
│   ├── ingress-routes.yaml        ← Core routes (staging as default)
│   └── ingress-values.yaml        ← Service definitions (for reference)
│
├── overlays/
│   ├── staging/                   ← NEW: Staging-specific overrides
│   │   └── kustomization.yaml     ← Applies staging environment
│   │
│   └── production/                ← NEW: Production-specific overrides
│       └── kustomization.yaml     ← Applies production patches
│
├── routes/                        ← OLD FILES (deprecated, kept for reference)
│   ├── infra-routes.yaml
│   ├── primecrib-staging.yaml
│   └── primecrib-prod.yaml
│
├── middlewares/                   ← OLD LOCATION (kept for compatibility)
├── cert-issuer.yaml               ← OLD LOCATION (kept for compatibility)
└── kustomization.yaml             ← OLD (updated to reference overlays)
```

---

## Configuration Changes

### 1. New File: `base/ingress-values.yaml`

**Purpose:** Centralized service metadata (reference documentation)

**What it contains:**
- Service name, namespace, port
- Middleware assignments
- TLS configuration
- Sticky session settings

**Example:**
```yaml
appServices:
  - name: gateway
    displayName: api
    serviceName: gateway-service
    port: 8008
    stickySession:
      cookieName: proptech_gateway_sticky
    middlewares:
      - security-headers
      - compression
      - rate-limit
```

**Why:** Provides single reference point for all services. Makes scaling easier when adding new services.

---

### 2. New File: `base/ingress-routes.yaml`

**Purpose:** Core IngressRoute definitions (environment-aware)

**What changed:**
- Infra routes remain unchanged (cyberstarsng.com - environment-agnostic)
- App routes use staging defaults:
  - `staging.api.primecrib.app` (not `api.primecrib.app`)
  - `staging.primecrib.app` (not `primecrib.app`)
  - `staging.admin.primecrib.app` (not `admin.primecrib.app`)
  - Namespace: `apps-staging` (not `apps-prod`)

**Key Design Decision:** Staging is the base because:
1. It's typically where development/testing happens first
2. Production overrides are more deliberate (safety)
3. Overlays clearly document environment separation

**Example - Before (duplication):**
```yaml
# primecrib-staging.yaml
Host(`staging.api.primecrib.app`)
namespace: apps-staging

# primecrib-prod.yaml
Host(`api.primecrib.app`)
namespace: apps-prod
```

**Example - After (single source):**
```yaml
# base/ingress-routes.yaml
Host(`staging.api.primecrib.app`)  ← Base (staging)
namespace: apps-staging

# overlays/production/kustomization.yaml (patch)
Host(`api.primecrib.app`)          ← Override (production)
namespace: apps-prod
```

---

### 3. New File: `base/kustomization.yaml`

**Purpose:** Tie base configuration together

```yaml
configMapGenerator:
  - name: ingress-environment
    behavior: create
    literals:
      - ENVIRONMENT=staging  # Default
```

**Why:** Makes environment explicit as a Kubernetes ConfigMap that can be queried/referenced.

---

### 4. New File: `overlays/staging/kustomization.yaml`

**Purpose:** Staging-specific configuration

```yaml
bases:
  - ../../base

configMapGenerator:
  - name: ingress-environment
    behavior: merge
    literals:
      - ENVIRONMENT=staging
```

**What it does:**
- References the base configuration
- Explicitly sets ENVIRONMENT=staging
- Adds labels/annotations for audit trail

**Why:** Makes staging deployment explicit and reproducible.

---

### 5. New File: `overlays/production/kustomization.yaml`

**Purpose:** Production-specific patches and overrides

```yaml
bases:
  - ../../base

configMapGenerator:
  - name: ingress-environment
    behavior: merge
    literals:
      - ENVIRONMENT=production

patchesStrategicMerge:
  # Gateway: staging.api.primecrib.app → api.primecrib.app
  - apiVersion: traefik.io/v1alpha1
    kind: IngressRoute
    metadata:
      name: gateway-app
    spec:
      routes:
        - match: Host(`api.primecrib.app`)
          services:
            - namespace: apps-prod

  # App: staging.primecrib.app → www.primecrib.app
  - apiVersion: traefik.io/v1alpha1
    kind: IngressRoute
    metadata:
      name: primecrib-app
    spec:
      routes:
        - match: Host(`www.primecrib.app`)
          services:
            - namespace: apps-prod

  # Admin: staging.admin.primecrib.app → admin.primecrib.app
  - apiVersion: traefik.io/v1alpha1
    kind: IngressRoute
    metadata:
      name: primecrib-admin
    spec:
      routes:
        - match: Host(`admin.primecrib.app`)
          services:
            - namespace: apps-prod

  # ... (other patches)
```

**Why:** Strategic Merge Patches allow precise override of host and namespace without duplicating the entire route definition.

---

## Detailed Diff: Current vs. Refactored

### Current Implementation Issues

#### Issue 1: Route Duplication
```diff
# CURRENT (BAD - duplicated)
primecrib-staging.yaml:
  Host(`staging.api.primecrib.app`)
  namespace: apps-staging

primecrib-prod.yaml:
  Host(`api.primecrib.app`)
  namespace: apps-prod

# REFACTORED (GOOD - single source)
base/ingress-routes.yaml:
  Host(`staging.api.primecrib.app`)
  namespace: apps-staging

overlays/production/kustomization.yaml (patch):
  Host(`api.primecrib.app`)
  namespace: apps-prod
```

#### Issue 2: Service Metadata Scattered
```diff
# CURRENT (BAD - no centralized reference)
primecrib-staging.yaml:
  gateway-service: port 8008, sticky session, 6 middlewares
primecrib-prod.yaml:
  gateway-service: port 8008, sticky session, 6 middlewares
# ^^ Same info in two places!

# REFACTORED (GOOD - single reference)
base/ingress-values.yaml:
  gateway:
    serviceName: gateway-service
    port: 8008
    stickySession: {...}
    middlewares: [...]
```

#### Issue 3: Environment Risk
```diff
# CURRENT (RISKY)
kubectl apply -k kubernetes/
# ↑ This ALWAYS deploys BOTH staging and production routes
# ↑ Risk: Staging routes might conflict with production in production environment

# REFACTORED (SAFE)
# Staging only:
kubectl apply -k kubernetes/ingress/overlays/staging

# Production only:
kubectl apply -k kubernetes/ingress/overlays/production
# ↑ Environment is explicit at deploy time
# ↑ No risk of cross-environment pollution
```

#### Issue 4: Scaling Problem
```diff
# CURRENT (BAD - requires editing multiple files)
Adding new service "foo":
  1. Edit primecrib-staging.yaml (create new IngressRoute)
  2. Edit primecrib-prod.yaml (create new IngressRoute)
  3. Update route/kustomization.yaml if needed
  4. Risk of forgetting one file → inconsistency

# REFACTORED (GOOD - single entry point)
Adding new service "foo":
  1. Add to base/ingress-values.yaml (metadata)
  2. Add IngressRoute to base/ingress-routes.yaml (staging version)
  3. Add patch to overlays/production/kustomization.yaml (production override)
  4. Done! Consistent across all environments
```

---

## Hostname Mapping

### Staging (overlay/staging applied)
```
Service Name         Display Name    Hostname Pattern                  Result
─────────────────────────────────────────────────────────────────────────────
gateway              api             <display>.staging.primecrib.app   staging.api.primecrib.app
primecrib-app        primecrib       <display>.staging.primecrib.app   staging.primecrib.app
primecrib-admin      admin           <display>.staging.primecrib.app   staging.admin.primecrib.app
primecrib-pitch      root            primecrib.app, www.primecrib.app  (unchanged - root routes)
proptech-core        proptech-api    proptech-api.cyberstarsng.com     (unchanged - infra domain)
```

### Production (overlay/production applied)
```
Service Name         Display Name    Hostname Pattern                  Result
─────────────────────────────────────────────────────────────────────────────
gateway              api             <display>.primecrib.app           api.primecrib.app
primecrib-app        primecrib       www.primecrib.app                 www.primecrib.app
primecrib-admin      admin           <display>.primecrib.app           admin.primecrib.app
primecrib-pitch      root            primecrib.app                     primecrib.app
proptech-core        proptech-api    proptech-api.cyberstarsng.com     (unchanged - infra domain)
```

### Infrastructure (unchanged - all environments)
```
Service Name         Display Name    Hostname Pattern
────────────────────────────────────────────────────
grafana              grafana         grafana.cyberstarsng.com
prometheus           prometheus      prometheus.cyberstarsng.com
vault                vault           vault.cyberstarsng.com
rabbitmq             rabbit          rabbit.cyberstarsng.com
minio-console        minio           minio.cyberstarsng.com
minio-s3             minio.s3        minio.s3.cyberstarsng.com
imgproxy             imgproxy        imgproxy.cyberstarsng.com
adminer              adminer         adminer.cyberstarsng.com
redis-insight        redis-insight   redis-insight.cyberstarsng.com
```

---

## Deployment Instructions

### Before (Current - Risk of Cross-Environment Pollution)
```bash
# This deploys ALL routes (staging + production) at once
# Very dangerous - staging routes could collide with production
cd kubernetes
kubectl apply -k .
```

### After (Refactored - Environment Isolation)

#### Deploy to Staging
```bash
# Only staging routes are deployed
# No production routes, no conflict risk
cd kubernetes/ingress
kubectl apply -k overlays/staging

# Verify:
kubectl get ingressroute -n ingress -L environment
# Shows: gateway-app, primecrib-app, etc. with environment=staging label
```

#### Deploy to Production
```bash
# Only production routes are deployed
# Staging hostnames/namespaces are patched to production equivalents
cd kubernetes/ingress
kubectl apply -k overlays/production

# Verify:
kubectl get ingressroute -n ingress -L environment
# Shows: gateway-app (with api.primecrib.app host), etc.
```

#### Verify Environment Isolation
```bash
# Check which environment is active:
kubectl get configmap ingress-environment -n ingress -o yaml
# Shows: ENVIRONMENT=staging or ENVIRONMENT=production

# List all routes with their hostnames:
kubectl get ingressroute -n ingress -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.routes[0].match}{"\n"}{end}'
```

---

## CI/CD Pipeline Integration

### GitOps Workflow (ArgoCD Example)
```yaml
# Before
Application:
  path: kubernetes/

# After - Staging
Application:
  path: kubernetes/ingress
  kustomization:
    overlay: staging

# After - Production  
Application:
  path: kubernetes/ingress
  kustomization:
    overlay: production
```

### Helm (if needed)
```bash
# Install with environment-aware values
helm install primecrib ./chart \
  --set environment=staging \
  --set kustomizeOverlay=overlays/staging

# Or for production
helm install primecrib ./chart \
  --set environment=production \
  --set kustomizeOverlay=overlays/production
```

---

## Migration Path

### Phase 1: Deploy Refactored Config (Non-Destructive)
1. Create new base/ and overlays/ directories ✅ (done)
2. Test staging overlay: `kubectl apply -k overlays/staging --dry-run`
3. Test production overlay: `kubectl apply -k overlays/production --dry-run`
4. **If satisfied:** Apply staging overlay first
5. Verify staging routes work

### Phase 2: Switch Production (Careful)
1. Backup current production routes: `kubectl get ingressroute -n ingress -oyaml > backup.yaml`
2. Apply production overlay: `kubectl apply -k overlays/production`
3. Verify production routes work
4. Monitor for 24-48 hours

### Phase 3: Cleanup (Archive Old Files)
1. After successful production deployment, archive old files:
   ```bash
   mkdir archive
   mv routes/primecrib-staging.yaml archive/
   mv routes/primecrib-prod.yaml archive/
   mv routes/infra-routes.yaml archive/
   ```
2. Update old kustomization.yaml to reference new overlays (if needed)
3. Update documentation

---

## Troubleshooting

### Routes not appearing
```bash
# Check if overlay applied correctly
kubectl get configmap ingress-environment -n ingress -o yaml

# Check patches were applied
kubectl get ingressroute -n ingress gateway-app -o yaml
# Should show either staging.api.primecrib.app or api.primecrib.app

# Check kustomize output
kustomize build overlays/staging | grep -A 5 "kind: IngressRoute"
```

### Hostname conflicts
```bash
# List all routes and their hosts
kubectl get ingressroute -n ingress -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.routes[*].match}{"\n"}{end}'

# Check if duplicate hosts exist (should not)
kubectl get ingressroute -n ingress -o jsonpath='{range .items[*].spec.routes[*]}{.match}{"\n"}{end}' | sort | uniq -d
```

### Certificate issues
```bash
# Check cert-manager status
kubectl get certificate -n ingress

# Check certificate renewal
kubectl describe certificate -n ingress primecrib-cert
```

---

## Files Created/Modified

### New Files
✅ `kubernetes/ingress/base/kustomization.yaml`
✅ `kubernetes/ingress/base/ingress-routes.yaml`
✅ `kubernetes/ingress/base/ingress-values.yaml`
✅ `kubernetes/ingress/base/cert-issuer.yaml` (copied)
✅ `kubernetes/ingress/base/middlewares/` (copied)
✅ `kubernetes/ingress/overlays/staging/kustomization.yaml`
✅ `kubernetes/ingress/overlays/production/kustomization.yaml`

### Existing Files (No Changes Required)
- `kubernetes/ingress/cert-issuer.yaml` (kept for backward compatibility)
- `kubernetes/ingress/middlewares/` (kept for backward compatibility)
- `kubernetes/ingress/routes/` (deprecated - kept for reference)
- `kubernetes/kustomization.yaml` (can stay as-is, or updated to use overlays)

---

## Benefits Summary

| Aspect | Before | After |
|--------|--------|-------|
| **Route Duplication** | 2x (staging + prod) | 1x (base) |
| **Source of Truth** | Scattered | Centralized |
| **Adding New Service** | Edit 2-3 files | Edit 2 places (values + base) |
| **Environment Isolation** | Weak | Strong |
| **Scaling** | Error-prone | Deterministic |
| **Audit Trail** | Implicit | Explicit (labels, overlays) |
| **Deployment Safety** | High risk | Low risk |
| **Configuration Visibility** | Difficult | Clear |

---

## References

- [Kustomize Documentation](https://kustomize.io/)
- [Strategic Merge Patches](https://kubernetes.io/docs/tasks/manage-kubernetes-objects/declarative-config/#strategic-merge-patch)
- [Traefik IngressRoute](https://docs.traefik.io/routing/providers/kubernetes-crd/)
- [Kubernetes ConfigMaps](https://kubernetes.io/docs/concepts/configuration/configmap/)


