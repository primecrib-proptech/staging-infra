# Ingress Configuration Refactor - Testing & Validation Guide

## Overview

This guide provides step-by-step validation procedures to ensure the refactored ingress configuration works correctly and safely.

---

## Pre-Deployment Validation

### 1. Verify Kustomize Output (Dry Run)

Before deploying anything, verify what Kustomize will generate:

#### Staging Configuration
```bash
# Build and view all resources that will be created
kustomize build kubernetes/ingress/overlays/staging > /tmp/staging-output.yaml

# Verify routes use staging hostnames
grep "Host(" /tmp/staging-output.yaml | sort
# Expected output:
# match: Host(`staging.api.primecrib.app`)
# match: Host(`staging.primecrib.app`)
# match: Host(`staging.admin.primecrib.app`)
# match: Host(`primecrib.app`) || Host(`www.primecrib.app`)  [pitch route]
# match: Host(`proptech-api.cyberstarsng.com`)                [legacy]
# match: Host(`grafana.cyberstarsng.com`)                     [infra - unchanged]
# ... (all other cyberstarsng.com routes)

# Verify namespaces are apps-staging
grep "namespace: apps-staging" /tmp/staging-output.yaml | wc -l
# Expected: 5 (gateway, primecrib-app, primecrib-admin, primecrib-pitch, proptech-core)

# Verify environment ConfigMap
grep -A 2 "kind: ConfigMap" /tmp/staging-output.yaml | grep ENVIRONMENT
# Expected output: ENVIRONMENT=staging
```

#### Production Configuration
```bash
# Build and view all resources that will be created
kustomize build kubernetes/ingress/overlays/production > /tmp/production-output.yaml

# Verify routes use production hostnames
grep "Host(" /tmp/production-output.yaml | sort
# Expected output:
# match: Host(`api.primecrib.app`)           [NOT staging.api...]
# match: Host(`www.primecrib.app`)           [NOT staging.primecrib.app]
# match: Host(`admin.primecrib.app`)         [NOT staging.admin.primecrib.app]
# match: Host(`primecrib.app`)               [Pitch route - only primecrib.app, no www]
# match: Host(`proptech-api.cyberstarsng.com`)                [legacy]
# match: Host(`grafana.cyberstarsng.com`)                     [infra - unchanged]
# ... (all other cyberstarsng.com routes)

# Verify namespaces are apps-prod
grep "namespace: apps-prod" /tmp/production-output.yaml | wc -l
# Expected: 5 (gateway, primecrib-app, primecrib-admin, primecrib-pitch, proptech-core)

# Verify environment ConfigMap
grep -A 2 "kind: ConfigMap" /tmp/production-output.yaml | grep ENVIRONMENT
# Expected output: ENVIRONMENT=production
```

### 2. Verify Hostname Uniqueness (No Conflicts)

Ensure no duplicate hostnames across all routes:

```bash
# Extract all hostnames from staging
echo "=== STAGING HOSTNAMES ===" 
kustomize build kubernetes/ingress/overlays/staging | \
  grep "match:" | sed 's/.*Host(`//g' | sed 's/`).*//g' | sort

# Extract all hostnames from production
echo "=== PRODUCTION HOSTNAMES ==="
kustomize build kubernetes/ingress/overlays/production | \
  grep "match:" | sed 's/.*Host(`//g' | sed 's/`).*//g' | sort

# Verify no overlaps (run SEPARATELY for each environment)
echo "=== PRODUCTION ONLY ROUTES ==="
comm -13 \
  <(kustomize build kubernetes/ingress/overlays/staging | grep "match:" | sed 's/.*Host(`//g' | sed 's/`).*//g' | sort -u) \
  <(kustomize build kubernetes/ingress/overlays/production | grep "match:" | sed 's/.*Host(`//g' | sed 's/`).*//g' | sort -u)
# Expected: api.primecrib.app, admin.primecrib.app, www.primecrib.app, etc. (NOT staging.*)
```

### 3. Verify Resource Counts

Ensure all resources are generated correctly:

```bash
# Staging
echo "=== STAGING RESOURCE COUNT ==="
kustomize build kubernetes/ingress/overlays/staging | grep "^kind:" | sort | uniq -c

# Expected output:
#  1 kind: ClusterIssuer
#  1 kind: ConfigMap (ingress-environment)
#  13 kind: Middleware
#  1 kind: ServersTransport
#  10 kind: IngressRoute (9 app services + 1 pitch route... adjust based on actual)

# Production
echo "=== PRODUCTION RESOURCE COUNT ==="
kustomize build kubernetes/ingress/overlays/production | grep "^kind:" | sort | uniq -c
# Should match staging count (patches don't add/remove resources)
```

---

## Deployment Testing

### Test Environment: Staging

#### Step 1: Dry Run (No Actual Deployment)
```bash
# Apply to staging cluster with --dry-run
kubectl apply -k kubernetes/ingress/overlays/staging \
  --dry-run=client \
  -n ingress

# Verify no errors
# Expected output: Resource names and counts, no errors
```

#### Step 2: Server Dry Run (Validates Against API Server)
```bash
# Test against actual API server (no persistence)
kubectl apply -k kubernetes/ingress/overlays/staging \
  --dry-run=server \
  -n ingress

# Verify no errors
# This catches CRD validation errors, etc.
```

#### Step 3: Actual Deployment (Staging)
```bash
# Deploy to staging
kubectl apply -k kubernetes/ingress/overlays/staging -n ingress

# Wait for resources to be created
kubectl rollout status -n ingress --timeout=60s

# Expected: All resources created successfully
```

#### Step 4: Verify Staging Routes Were Created
```bash
# List all IngressRoutes
kubectl get ingressroute -n ingress -o wide

# Verify environment label
kubectl get ingressroute -n ingress -L environment

# Expected output:
# NAME                 AGE     ENVIRONMENT
# gateway-app          2m      staging
# primecrib-app        2m      staging
# primecrib-admin      2m      staging
# primecrib-pitch      2m      staging
# grafana              2m      
# prometheus           2m      
# ... (other infra routes without environment label)

# Inspect a specific route to verify hostname
kubectl get ingressroute gateway-app -n ingress -o jsonpath='{.spec.routes[0].match}'
# Expected: Host(`staging.api.primecrib.app`)

# Inspect namespace
kubectl get ingressroute gateway-app -n ingress -o jsonpath='{.spec.routes[0].services[0].namespace}'
# Expected: apps-staging
```

#### Step 5: Verify Staging Environment ConfigMap
```bash
# Check environment variable
kubectl get configmap ingress-environment -n ingress -o jsonpath='{.data.ENVIRONMENT}'
# Expected: staging
```

#### Step 6: Verify TLS/Certificates
```bash
# List certificates created by cert-manager
kubectl get certificates -n ingress

# Check specific certificate for staging
kubectl describe certificate -n ingress staging.api.primecrib.app-cert
# Expected: Certificate created and ready

# View certificate details (if using Let's Encrypt)
kubectl get secret -n ingress -o name | grep tls | head -5
# List TLS secrets created by cert-manager
```

---

### Test Environment: Production

⚠️ **CAUTION:** Only proceed with production deployment after staging tests pass.

#### Step 1: Backup Current Production Routes
```bash
# Before deploying production overlay, backup existing routes
kubectl get ingressroute -n ingress -o yaml > /tmp/production-routes-backup-$(date +%s).yaml
echo "Backup saved to /tmp/production-routes-backup-*.yaml"
```

#### Step 2: Dry Run (Production)
```bash
# Apply to production cluster with --dry-run
kubectl apply -k kubernetes/ingress/overlays/production \
  --dry-run=client \
  -n ingress

# Verify routes use production hostnames
# Expected: api.primecrib.app, admin.primecrib.app, www.primecrib.app, etc.
```

#### Step 3: Server Dry Run (Production)
```bash
# Test against production API server (no persistence)
kubectl apply -k kubernetes/ingress/overlays/production \
  --dry-run=server \
  -n ingress

# Verify no validation errors
```

#### Step 4: Actual Deployment (Production)
```bash
# Deploy to production with explicit confirmation
echo "⚠️  Deploying production ingress configuration"
echo "Ctrl+C now to cancel, or wait 5 seconds..."
sleep 5

kubectl apply -k kubernetes/ingress/overlays/production -n ingress

# Verify deployment
kubectl rollout status -n ingress --timeout=60s
```

#### Step 5: Verify Production Routes Were Updated
```bash
# List all IngressRoutes
kubectl get ingressroute -n ingress -o wide

# Verify production hostnames
kubectl get ingressroute -n ingress -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.routes[0].match}{"\n"}{end}'

# Expected output:
# gateway-app              Host(`api.primecrib.app`)
# primecrib-app            Host(`www.primecrib.app`)
# primecrib-admin          Host(`admin.primecrib.app`)
# primecrib-pitch          Host(`primecrib.app`)
# grafana                  Host(`grafana.cyberstarsng.com`)
# ... etc

# Verify namespace changes
kubectl get ingressroute gateway-app -n ingress -o jsonpath='{.spec.routes[0].services[0].namespace}'
# Expected: apps-prod (NOT apps-staging)
```

#### Step 6: Verify Production Environment ConfigMap
```bash
# Check environment variable
kubectl get configmap ingress-environment -n ingress -o jsonpath='{.data.ENVIRONMENT}'
# Expected: production
```

#### Step 7: Verify Traefik Dashboard (If Accessible)
```bash
# If Traefik dashboard is accessible, verify routes are active
# URL: https://traefik.cyberstarsng.com/dashboard/ (or similar)

# Expected to see:
# - api.primecrib.app routing to apps-prod namespace
# - admin.primecrib.app routing to apps-prod namespace
# - www.primecrib.app routing to apps-prod namespace
# - Infra routes (unchanged)
```

---

## Post-Deployment Validation

### 1. DNS Resolution Test

```bash
# Test staging domains resolve
for domain in staging.api.primecrib.app staging.primecrib.app staging.admin.primecrib.app; do
  echo "Resolving $domain..."
  nslookup $domain
done

# Test production domains resolve
for domain in api.primecrib.app primecrib.app admin.primecrib.app www.primecrib.app; do
  echo "Resolving $domain..."
  nslookup $domain
done

# Test infrastructure domains
for domain in grafana.cyberstarsng.com prometheus.cyberstarsng.com vault.cyberstarsng.com; do
  echo "Resolving $domain..."
  nslookup $domain
done
```

### 2. HTTPS Connectivity Test

```bash
# Test staging routes are accessible via HTTPS
for domain in staging.api.primecrib.app staging.primecrib.app staging.admin.primecrib.app; do
  echo "Testing $domain..."
  curl -I https://$domain 2>&1 | grep -E "(HTTP|SSL|ERR)"
done

# Test production routes
for domain in api.primecrib.app primecrib.app admin.primecrib.app www.primecrib.app; do
  echo "Testing $domain..."
  curl -I https://$domain 2>&1 | grep -E "(HTTP|SSL|ERR)"
done
```

### 3. Service Connectivity Verification

```bash
# Test if gateway service responds on staging
kubectl port-forward -n apps-staging svc/gateway-service 8008:8008 &
sleep 2
curl -I http://localhost:8008

# Test if gateway service responds on production
kubectl port-forward -n apps-prod svc/gateway-service 8008:8008 &
sleep 2
curl -I http://localhost:8008

# Clean up
pkill -f "port-forward"
```

### 4. Cross-Environment Isolation Test

```bash
# Verify staging routes are NOT in production environment
# (if you ran both overlays against the same cluster)

kubectl get ingressroute -n ingress | grep staging
# Expected: Only IngressRoutes without "staging" in the hostname should be present
# If you see staging.* hostnames in production namespace, something is wrong!

# Verify production routes are NOT in staging environment
kubectl get ingressroute -n ingress | grep -v "staging"
# Expected: Routes like api.primecrib.app, admin.primecrib.app, etc.
# These should only exist if production overlay was applied
```

### 5. Certificate Validation

```bash
# Check certificate validity (staging)
echo | openssl s_client -servername staging.api.primecrib.app \
  -connect staging.api.primecrib.app:443 2>/dev/null | \
  openssl x509 -noout -dates -subject

# Check certificate validity (production)
echo | openssl s_client -servername api.primecrib.app \
  -connect api.primecrib.app:443 2>/dev/null | \
  openssl x509 -noout -dates -subject

# Expected: Valid certificates with correct hostnames
```

---

## Rollback Procedures

### If Something Goes Wrong (Staging)

```bash
# Option 1: Revert to previous state
kubectl delete -k kubernetes/ingress/overlays/staging -n ingress

# Option 2: Restore from backup (if using old configuration)
kubectl apply -f /tmp/staging-routes-backup-*.yaml

# Verify rollback
kubectl get ingressroute -n ingress
```

### If Something Goes Wrong (Production)

```bash
# Option 1: Restore from backup
kubectl apply -f /tmp/production-routes-backup-*.yaml

# Option 2: Delete problematic routes and recreate
kubectl delete ingressroute gateway-app -n ingress
kubectl delete ingressroute primecrib-app -n ingress
# ... (repeat for each problematic route)

# Then reapply the overlay
kubectl apply -k kubernetes/ingress/overlays/production -n ingress

# Option 3: Use GitOps (ArgoCD) to auto-sync to previous commit
# (if using GitOps)
```

---

## Performance & Load Testing

### 1. Basic Load Test (Staging)

```bash
# Install load testing tool (if not present)
# brew install apache2  (on macOS) or apt-get install apache2-utils (on Linux)

# Test gateway endpoint
ab -n 1000 -c 10 https://staging.api.primecrib.app/health

# Expected: All requests succeed, no 502/503 errors
```

### 2. Monitor Traefik Metrics

```bash
# If Prometheus is enabled, check Traefik metrics
kubectl port-forward -n observability svc/kube-prometheus-prometheus 9090:9090 &

# Visit http://localhost:9090 and search for:
# traefik_router_request_total
# traefik_service_requests_total
# traefik_service_server_up

# Expected: Metrics show traffic routing to correct services
```

### 3. Check Logs (Staging)

```bash
# View Traefik logs for staging routes
kubectl logs -n ingress -l app.kubernetes.io/name=traefik --tail=100

# Expected: Logs show successful routing to staging services
# Look for warnings or errors related to staging routes

# Verify no routing loops or TLS issues
kubectl logs -n ingress -l app.kubernetes.io/name=traefik | grep -i "error\|warn" | head -20
```

---

## Validation Checklist

Before declaring the refactoring complete, verify:

- [ ] **Dry Run Passed:** Kustomize builds without errors
- [ ] **Staging Routes Correct:** All routes use staging.* hostnames and apps-staging namespace
- [ ] **Production Routes Correct:** All routes use production hostnames and apps-prod namespace
- [ ] **No Route Conflicts:** No duplicate hostnames across environments
- [ ] **Environment ConfigMap:** ENVIRONMENT variable set correctly (staging/production)
- [ ] **Certificates Valid:** TLS certificates created and valid for all hostnames
- [ ] **DNS Resolution:** All routes resolve correctly
- [ ] **HTTPS Connectivity:** All routes accessible via HTTPS
- [ ] **Service Connectivity:** Backend services responding correctly
- [ ] **Cross-Environment Isolation:** Staging routes not accessible in production (and vice versa)
- [ ] **Logs Clean:** No errors or warnings in Traefik/cert-manager logs
- [ ] **Load Test Passed:** Basic load tests show no errors
- [ ] **Backup Created:** Previous configuration backed up before production deployment
- [ ] **Rollback Tested:** Can quickly rollback if needed
- [ ] **Documentation Updated:** Team knows how to deploy/troubleshoot new configuration

---

## Quick Reference: Common Commands

```bash
# Build Kustomize output for inspection
kustomize build kubernetes/ingress/overlays/staging | less
kustomize build kubernetes/ingress/overlays/production | less

# Deploy staging
kubectl apply -k kubernetes/ingress/overlays/staging -n ingress

# Deploy production
kubectl apply -k kubernetes/ingress/overlays/production -n ingress

# Check environment
kubectl get configmap ingress-environment -n ingress -o jsonpath='{.data.ENVIRONMENT}'

# List all routes
kubectl get ingressroute -n ingress

# Inspect specific route
kubectl get ingressroute gateway-app -n ingress -o yaml

# View Traefik logs
kubectl logs -f -n ingress -l app.kubernetes.io/name=traefik

# Verify hostnames
kubectl get ingressroute -n ingress -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.routes[0].match}{"\n"}{end}' | sort

# Get resource count
kustomize build kubernetes/ingress/overlays/staging | grep "^kind:" | sort | uniq -c
```

---

## Troubleshooting Guide

### Issue: Routes not appearing after deployment

**Diagnosis:**
```bash
kubectl get ingressroute -n ingress
# Should show routes

kubectl describe ingressroute gateway-app -n ingress
# Check for errors or warnings
```

**Solution:**
- Verify Traefik CRDs are installed: `kubectl get crd | grep traefik`
- Check Traefik logs: `kubectl logs -f -n ingress -l app.kubernetes.io/name=traefik`
- Verify IngressRoute namespace: `kubectl get ingressroute --all-namespaces`

### Issue: Certificate not created

**Diagnosis:**
```bash
kubectl get certificate -n ingress
kubectl describe certificate -n ingress api.primecrib.app-cert
```

**Solution:**
- Verify cert-manager is installed: `kubectl get deploy -n cert-manager`
- Check cert-manager logs: `kubectl logs -f -n cert-manager -l app=cert-manager`
- Verify DNS can be resolved: `nslookup api.primecrib.app`

### Issue: 404 or 502 errors on routes

**Diagnosis:**
```bash
# Check if backend service exists
kubectl get svc -n apps-prod | grep gateway-service

# Check if pods are running
kubectl get pods -n apps-prod

# Check Traefik logs for routing errors
kubectl logs -f -n ingress -l app.kubernetes.io/name=traefik | grep -i "error"
```

**Solution:**
- Ensure services are deployed in correct namespace (apps-staging or apps-prod)
- Verify service names match IngressRoute definitions
- Check firewall/network policies: `kubectl get networkpolicies -n apps-prod`


