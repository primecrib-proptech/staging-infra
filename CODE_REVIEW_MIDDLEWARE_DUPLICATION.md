# Code Review: Middleware Duplication Analysis & Remediation

**Date:** May 23, 2026  
**Reviewer:** Senior DevOps/Platform Engineer  
**Status:** 🔴 CRITICAL DUPLICATION FOUND - REMEDIATION REQUIRED  

---

## 1. FINDINGS

### Middleware Duplication Detected

**Location 1 (Original):**
```
/kubernetes/ingress/middlewares/          [ROOT LEVEL - LEGACY]
├── dashboard-auth.yaml
├── security-headers.yaml
├── frontend-security-headers.yaml
├── rate-limit.yaml
├── compression.yaml
├── retry.yaml
├── circuit-breaker.yaml
├── buffering.yaml
├── cache-static-long.yaml
├── cache-no-store.yaml
├── rabbitmq-csp.yaml
├── redirect-https.yaml
└── kustomization.yaml
```

**Location 2 (Refactored):**
```
/kubernetes/ingress/base/middlewares/     [BASE LEVEL - NEW]
├── dashboard-auth.yaml
├── security-headers.yaml
├── frontend-security-headers.yaml
├── rate-limit.yaml
├── compression.yaml
├── retry.yaml
├── circuit-breaker.yaml
├── buffering.yaml
├── cache-static-long.yaml
├── cache-no-store.yaml
├── rabbitmq-csp.yaml
├── redirect-https.yaml
└── kustomization.yaml
```

### Comparison Result

**✓ IDENTICAL - NO DIFFERENCES FOUND**

```bash
$ diff -r /kubernetes/ingress/middlewares /kubernetes/ingress/base/middlewares
# (no output = perfect match)
```

**Finding:** 100% byte-for-byte duplication across all 13 middleware files + kustomization.yaml

---

## 2. ROOT CAUSE ANALYSIS

### How Duplication Occurred

During the refactor:
1. Created new `kubernetes/ingress/base/` directory structure
2. **Copied** middlewares into `base/middlewares/` ✓ (correct)
3. **Failed to remove** original `ingress/middlewares/` ✗ (mistake)

### Reference Points

**Root kustomization.yaml** (`/kubernetes/ingress/kustomization.yaml`):
```yaml
resources:
  - cert-issuer.yaml
  - middlewares/           ← References ROOT level middlewares
  - routes/
```

**Base kustomization.yaml** (`/kubernetes/ingress/base/kustomization.yaml`):
```yaml
resources:
  - cert-issuer.yaml
  - middlewares/           ← References BASE level middlewares
  - ingress-routes.yaml
```

### The Problem

When **root kustomization** is applied, it loads middlewares from **`/ingress/middlewares/`** (original).  
When **overlays** are applied, they inherit from **`/ingress/base/middlewares/`** (copy).

**Result:** Two identical copies exist simultaneously in memory during deployment, causing:
- ❌ Wasted resources (duplicate CRDs)
- ❌ Confusion about canonical source
- ❌ Maintenance burden (changes must be made in 2 places)
- ❌ Risk of divergence if only one copy is updated

---

## 3. REFERENCE ANALYSIS

### Which is the Canonical Definition?

**Base path (`/ingress/base/middlewares/`)** should be canonical because:

1. **Kustomize Best Practices**
   - Base contains all shared/reusable components
   - Overlays extend/patch the base
   - Middlewares are shared across all environments

2. **Current Architecture**
   - `overlays/staging/` references base
   - `overlays/production/` references base
   - **Both overlays inherit base middlewares**

3. **Forward Compatibility**
   - New deployments use `kubectl apply -k overlays/{staging,production}`
   - These build from `base/`
   - Root ingress/ is legacy (not used by overlays)

4. **Structural Alignment**
   - All core components in base:
     - `base/ingress-routes.yaml` ✓
     - `base/ingress-values.yaml` ✓
     - `base/cert-issuer.yaml` ✓
     - `base/middlewares/` ✓
   - Original remains as deprecated reference only

### What Would Break Without Each?

**If we DELETE `/ingress/base/middlewares/`:**
- ❌ **CRITICAL FAILURE** - Overlays (staging/production) cannot build
- ❌ New deployments fail: `kubectl apply -k overlays/staging`
- ❌ All middleware references fail

**If we DELETE `/ingress/middlewares/`:**
- ⚠️ **LEGACY IMPACT** - Old deployments using root ingress fail
- ✓ **NOT USED** by new architecture (overlays)
- ✓ Safe to remove (it's deprecated)

### Verdict

**Canonical:** `/kubernetes/ingress/base/middlewares/`  
**Status:** Base is the active, production-path middleware definition  
**Legacy:** `/kubernetes/ingress/middlewares/` is a remnant from copy operation  
**Action:** **DELETE ROOT LEVEL (legacy), KEEP BASE LEVEL (canonical)**

---

## 4. IMPACT ASSESSMENT

### Current Active References

| Reference | Location | Used By | Impact |
|-----------|----------|---------|--------|
| `base/middlewares/` | `/ingress/base/kustomization.yaml` | ✅ overlays/staging | **PRIMARY** |
| `base/middlewares/` | `/ingress/base/kustomization.yaml` | ✅ overlays/production | **PRIMARY** |
| `middlewares/` | `/ingress/kustomization.yaml` | ⚠️ root ingress (deprecated) | **LEGACY** |

### Deployment Paths

**ACTIVE (Recommended):**
```
kubectl apply -k kubernetes/ingress/overlays/staging
  └─ loads: /ingress/base/kustomization.yaml
    └─ loads: /ingress/base/middlewares/  ✅ Uses BASE
```

**LEGACY (Not Recommended):**
```
kubectl apply -k kubernetes/ingress/
  └─ loads: /ingress/kustomization.yaml
    └─ loads: /ingress/middlewares/       ⚠️ Uses ROOT
    └─ also loads: /ingress/routes/       (deprecated)
```

---

## 5. RECOMMENDED ACTION

### Decision: **DELETE ROOT-LEVEL MIDDLEWARE COPY**

**Rationale:**
1. ✅ Base-level middlewares are actively used by all overlays
2. ✅ Base-level path aligns with Kustomize best practices
3. ✅ No active deployments depend on root-level copy
4. ✅ Eliminates maintenance burden (100% duplication)
5. ✅ Clarifies single source of truth

### Changes Required

1. **Delete Deprecated Middleware Copy**
   - Remove: `/kubernetes/ingress/middlewares/` (entire directory)

2. **Update Root Kustomization (if used)**
   - File: `/kubernetes/ingress/kustomization.yaml`
   - Update reference from `middlewares/` → `base/middlewares/`
   - Maintains compatibility for legacy deployments

3. **Verify All Overlays Still Build**
   - Test: `kustomize build overlays/staging`
   - Test: `kustomize build overlays/production`
   - Confirm: No broken references

4. **Documentation Update**
   - Add note: Root ingress/ deprecated in favor of overlays/
   - Clear deployment path: Use `overlays/{staging,production}`

---

## 6. IMPLEMENTATION PLAN

### Phase 1: Update Root Kustomization (Safety)

**File:** `/kubernetes/ingress/kustomization.yaml`

**Before:**
```yaml
resources:
  - cert-issuer.yaml
  - middlewares/          ← Points to /ingress/middlewares/
  - routes/
```

**After:**
```yaml
resources:
  - cert-issuer.yaml
  - base/middlewares/     ← Points to /ingress/base/middlewares/
  - routes/
  
# NOTE: This kustomization is DEPRECATED
# Use: kubectl apply -k overlays/{staging|production}
# New deployments should use overlays, not root ingress
```

### Phase 2: Delete Legacy Copy

**Delete:** `/kubernetes/ingress/middlewares/` (entire directory)

**Files Removed:**
- buffering.yaml
- cache-no-store.yaml
- cache-static-long.yaml
- circuit-breaker.yaml
- compression.yaml
- dashboard-auth.yaml
- frontend-security-headers.yaml
- rabbitmq-csp.yaml
- rate-limit.yaml
- redirect-https.yaml
- retry.yaml
- security-headers.yaml
- kustomization.yaml

**Total:** 13 files deleted (100% duplicated)

### Phase 3: Verify All Deployment Paths

**Test 1: Staging Overlay Builds**
```bash
kustomize build kubernetes/ingress/overlays/staging
# Expected: Success, loads base/middlewares/
```

**Test 2: Production Overlay Builds**
```bash
kustomize build kubernetes/ingress/overlays/production
# Expected: Success, loads base/middlewares/
```

**Test 3: Root Kustomization Builds**
```bash
kustomize build kubernetes/ingress/
# Expected: Success, loads base/middlewares/ (via updated reference)
```

---

## 7. IMPLEMENTATION

Now executing the remediation...


