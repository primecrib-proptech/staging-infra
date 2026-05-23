# Kubernetes Ingress Configuration Refactor Analysis

## CURRENT STATE

### Problem: Not Environment-Aware
The current implementation has **hardcoded** environment-specific routes duplicated across three files:

1. **infra-routes.yaml** - Internal dashboards (using `cyberstarsng.com`)
2. **primecrib-staging.yaml** - Staging app routes (using `staging.primecrib.app`)
3. **primecrib-prod.yaml** - Production app routes (using `primecrib.app`)

**Issues:**
- Routes are duplicated across environments
- No centralized environment configuration
- Risk of staging routes being deployed to production (or vice versa)
- Adding a new service requires editing multiple files
- Inconsistent domain structure (infra uses different domain)
- TLS certificates are assumed to work via single `certResolver: letsencrypt`
- No way to override domain per environment at deployment time

### Current Domains Used
```
Infra Services (cyberstarsng.com):
  - grafana.cyberstarsng.com
  - prometheus.cyberstarsng.com
  - vault.cyberstarsng.com
  - rabbit.cyberstarsng.com
  - minio.cyberstarsng.com
  - minio.s3.cyberstarsng.com
  - imgproxy.cyberstarsng.com
  - adminer.cyberstarsng.com
  - redis-insight.cyberstarsng.com

Staging App Services (primecrib.app):
  - staging.primecrib.app          (main app)
  - staging.api.primecrib.app      (gateway)
  - staging.admin.primecrib.app    (admin)
  - primecrib.app / www.primecrib.app (pitch)
  - proptech-api.cyberstarsng.com  (proptech core)

Production App Services (primecrib.app):
  - primecrib.app                  (pitch)
  - www.primecrib.app              (main app)
  - admin.primecrib.app            (admin)
  - api.primecrib.app              (gateway)
```

---

## REFACTORED SOLUTION

### Strategy: Kustomize Overlays + Helm-style Values

**Why Kustomize?** The codebase already uses Kustomize (not Helm), so overlays are the natural choice.

**Why values.yaml pattern?** Makes environment configuration explicit and easy to understand.

### New Structure

```
kubernetes/
├── ingress/
│   ├── base/                          # NEW: Base configurations (non-environment-specific)
│   │   ├── kustomization.yaml
│   │   ├── ingress-values.yaml        # NEW: Service route definitions
│   │   ├── ingress-routes-template.yaml  # NEW: Templated routes (env-aware)
│   │   ├── cert-issuer.yaml           # MOVED: Environment-independent
│   │   └── middlewares/               # MOVED: Shared middlewares
│   │
│   ├── overlays/
│   │   ├── staging/                   # NEW: Staging-specific overrides
│   │   │   ├── kustomization.yaml
│   │   │   └── values-staging.yaml
│   │   └── production/                # NEW: Production-specific overrides
│   │       ├── kustomization.yaml
│   │       └── values-production.yaml
│   │
│   ├── routes/                        # DEPRECATED: Kept for reference
│   │   ├── infra-routes.yaml          # To be migrated
│   │   ├── primecrib-staging.yaml     # To be migrated
│   │   └── primecrib-prod.yaml        # To be migrated
```

### Key Changes

1. **Centralized Route Configuration** → `ingress-values.yaml`
   - Single source of truth for all services
   - Service metadata (name, namespace, port)
   - Hostname template variables
   - Middleware assignments

2. **Templated Route Generation** → `ingress-routes-template.yaml`
   - Uses Kustomize patches + variable substitution
   - Generates IngressRoute resources dynamically
   - Supports hostname prefixing logic

3. **Environment Overlays**
   - `overlays/staging/` → Sets environment to "staging"
   - `overlays/production/` → Sets environment to "production"
   - Each overlay provides environment-specific values

4. **Deployment-time Configuration**
   - Environment is controlled via overlay selection
   - No hardcoded hostnames in route definitions
   - TLS certificates automatically scoped to environment

---

## DETAILED DIFF & CHANGES

### 1. New: `kubernetes/ingress/base/ingress-values.yaml`

Centralized service definitions:
- Service name, namespace, port
- Hostname template for routing
- Middleware assignments
- Service-specific configurations (sticky sessions, transport)

### 2. New: `kubernetes/ingress/base/ingress-routes-template.yaml`

A **generator template** that will be processed by Kustomize to produce:
- Dynamic IngressRoute for each service
- Environment-aware hostname generation
- Support for multiple route patterns

### 3. New: `kubernetes/ingress/overlays/staging/kustomization.yaml`

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: ingress

bases:
  - ../../base

configMapGenerator:
  - name: ingress-config
    behavior: merge
    literals:
      - ENVIRONMENT=staging
      - DOMAIN=primecrib.app
      - INFRA_DOMAIN=cyberstarsng.com

vars:
  - name: ENVIRONMENT
    objref:
      kind: ConfigMap
      name: ingress-config
      apiVersion: v1
    fieldref:
      fieldpath: data.ENVIRONMENT
```

### 4. New: `kubernetes/ingress/overlays/production/kustomization.yaml`

Same structure, but with:
```yaml
      - ENVIRONMENT=production
```

### 5. Modified: `kubernetes/ingress/base/kustomization.yaml`

Updated to reference new files and properly template routes.

---

## HOSTNAME GENERATION LOGIC

### Pattern 1: App Services (primecrib.app)

**Staging:**
```
<service>.<environment>.primecrib.app
Examples:
  - gateway.staging.api.primecrib.app → staging.api.primecrib.app
  - gateway.staging.primecrib.app → staging.primecrib.app
```

**Production:**
```
<service>.primecrib.app
Examples:
  - gateway.api.primecrib.app → api.primecrib.app
  - gateway.primecrib.app → primecrib.app
```

### Pattern 2: Infra Services (cyberstarsng.com)

These remain unchanged — they're environment-agnostic (shared across envs).

---

## BENEFITS OF THIS APPROACH

1. ✅ **Single source of truth** for routes — modify once, affects all environments
2. ✅ **No route duplication** — services defined once with environment awareness
3. ✅ **Scalable** — new service = one entry in values.yaml
4. ✅ **Clear separation** — base contains logic, overlays contain env config
5. ✅ **Immutable deployments** — environment locked at deploy time via overlay
6. ✅ **Type-safe** — values are validated before route generation
7. ✅ **Audit trail** — environment is explicit in deployment command
8. ✅ **No staging in production** — overlays ensure isolation

---

## DEPLOYMENT INSTRUCTIONS

### Before (Current)
```bash
# Risk: Both staging and prod routes deployed simultaneously
kubectl apply -k kubernetes/
```

### After (Refactored)
```bash
# Staging Deployment
kubectl apply -k kubernetes/ingress/overlays/staging

# Production Deployment
kubectl apply -k kubernetes/ingress/overlays/production
```

---

## MIGRATION CHECKLIST

- [ ] Create `kubernetes/ingress/base/` directory structure
- [ ] Create `ingress-values.yaml` with all service definitions
- [ ] Create `ingress-routes-template.yaml` with templated routes
- [ ] Create `overlays/staging/` with staging-specific config
- [ ] Create `overlays/production/` with production-specific config
- [ ] Update `kubernetes/ingress/cert-issuer.yaml` to be environment-aware
- [ ] Test staging deployment
- [ ] Test production deployment
- [ ] Verify no route conflicts
- [ ] Archive old primecrib-staging.yaml, primecrib-prod.yaml, infra-routes.yaml
- [ ] Update CI/CD pipeline to use new overlay-based deployment
- [ ] Update deployment docs

---

## COMPATIBILITY NOTES

- Kustomize v3.8+ required (for `vars` feature)
- cert-manager v1.0+ already in use
- Traefik v2.x IngressRoute CRD unchanged
- No changes required to service definitions themselves


