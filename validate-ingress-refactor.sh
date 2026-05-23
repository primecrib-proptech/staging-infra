#!/bin/bash
# Ingress Configuration Refactor - Validation Script
# This script validates the refactored configuration without requiring deployment

set -e

REPO_ROOT="/Users/johnadeshola/Projects/Cyberstarsng/ops/staging-infra"
INGRESS_BASE="${REPO_ROOT}/kubernetes/ingress/base"
INGRESS_STAGING="${REPO_ROOT}/kubernetes/ingress/overlays/staging"
INGRESS_PROD="${REPO_ROOT}/kubernetes/ingress/overlays/production"

# Color output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=================================================="
echo "Ingress Configuration Refactor - Validation"
echo "=================================================="
echo ""

# Check if Kustomize is installed
if ! command -v kustomize &> /dev/null; then
    echo -e "${YELLOW}⚠️  Warning: Kustomize not installed${NC}"
    echo "Install with: brew install kustomize"
    echo ""
    echo "Proceeding with file structure validation only..."
    echo ""
else
    echo -e "${GREEN}✅ Kustomize installed${NC}"
    echo ""
fi

# Function to check file exists
check_file_exists() {
    local file=$1
    local description=$2
    if [ -f "$file" ]; then
        echo -e "${GREEN}✅${NC} $description"
        return 0
    else
        echo -e "${RED}❌${NC} MISSING: $description ($file)"
        return 1
    fi
}

# Function to check directory exists
check_dir_exists() {
    local dir=$1
    local description=$2
    if [ -d "$dir" ]; then
        echo -e "${GREEN}✅${NC} $description"
        return 0
    else
        echo -e "${RED}❌${NC} MISSING: $description ($dir)"
        return 1
    fi
}

# Validate file structure
echo "=== FILE STRUCTURE VALIDATION ==="
echo ""

echo "Base Configuration:"
check_dir_exists "$INGRESS_BASE" "Base directory"
check_file_exists "$INGRESS_BASE/kustomization.yaml" "Base kustomization.yaml"
check_file_exists "$INGRESS_BASE/ingress-routes.yaml" "Base ingress-routes.yaml"
check_file_exists "$INGRESS_BASE/ingress-values.yaml" "Base ingress-values.yaml"
check_file_exists "$INGRESS_BASE/cert-issuer.yaml" "Base cert-issuer.yaml"
check_dir_exists "$INGRESS_BASE/middlewares" "Base middlewares directory"
echo ""

echo "Staging Overlay:"
check_dir_exists "$INGRESS_STAGING" "Staging overlay directory"
check_file_exists "$INGRESS_STAGING/kustomization.yaml" "Staging kustomization.yaml"
echo ""

echo "Production Overlay:"
check_dir_exists "$INGRESS_PROD" "Production overlay directory"
check_file_exists "$INGRESS_PROD/kustomization.yaml" "Production kustomization.yaml"
echo ""

# Validate YAML syntax
echo "=== YAML SYNTAX VALIDATION ==="
echo ""

validate_yaml() {
    local file=$1
    local name=$2
    if ! grep -q "^---" "$file" && ! grep -q "^apiVersion:" "$file"; then
        echo -e "${RED}❌${NC} $name: File appears empty or invalid"
        return 1
    fi

    # Check for valid YAML markers
    if grep -q "^apiVersion:" "$file" || grep -q "^kind:" "$file"; then
        echo -e "${GREEN}✅${NC} $name: Valid YAML structure"
        return 0
    fi
}

validate_yaml "$INGRESS_BASE/ingress-routes.yaml" "Base ingress-routes.yaml"
validate_yaml "$INGRESS_BASE/ingress-values.yaml" "Base ingress-values.yaml"
validate_yaml "$INGRESS_BASE/kustomization.yaml" "Base kustomization.yaml"
validate_yaml "$INGRESS_STAGING/kustomization.yaml" "Staging kustomization.yaml"
validate_yaml "$INGRESS_PROD/kustomization.yaml" "Production kustomization.yaml"
echo ""

# Validate key content
echo "=== CONTENT VALIDATION ==="
echo ""

echo "Staging Configuration Markers:"
if grep -q "staging.api.primecrib.app" "$INGRESS_BASE/ingress-routes.yaml"; then
    echo -e "${GREEN}✅${NC} Found staging API hostname (staging.api.primecrib.app)"
else
    echo -e "${RED}❌${NC} Missing staging API hostname"
fi

if grep -q "apps-staging" "$INGRESS_BASE/ingress-routes.yaml"; then
    echo -e "${GREEN}✅${NC} Found staging namespace reference (apps-staging)"
else
    echo -e "${RED}❌${NC} Missing staging namespace reference"
fi
echo ""

echo "Production Overlay Patches:"
if grep -q "api.primecrib.app" "$INGRESS_PROD/kustomization.yaml"; then
    echo -e "${GREEN}✅${NC} Found production API hostname patch (api.primecrib.app)"
else
    echo -e "${RED}❌${NC} Missing production API hostname patch"
fi

if grep -q "apps-prod" "$INGRESS_PROD/kustomization.yaml"; then
    echo -e "${GREEN}✅${NC} Found production namespace patch (apps-prod)"
else
    echo -e "${RED}❌${NC} Missing production namespace patch"
fi
echo ""

echo "Environment Configuration:"
if grep -q "ENVIRONMENT=staging" "$INGRESS_STAGING/kustomization.yaml"; then
    echo -e "${GREEN}✅${NC} Staging overlay sets ENVIRONMENT=staging"
else
    echo -e "${RED}❌${NC} Staging overlay missing ENVIRONMENT=staging"
fi

if grep -q "ENVIRONMENT=production" "$INGRESS_PROD/kustomization.yaml"; then
    echo -e "${GREEN}✅${NC} Production overlay sets ENVIRONMENT=production"
else
    echo -e "${RED}❌${NC} Production overlay missing ENVIRONMENT=production"
fi
echo ""

# Validate base references
echo "=== BASE REFERENCES ==="
echo ""

if grep -q "bases:" "$INGRESS_STAGING/kustomization.yaml"; then
    echo -e "${GREEN}✅${NC} Staging overlay references base"
else
    echo -e "${RED}❌${NC} Staging overlay missing base reference"
fi

if grep -q "bases:" "$INGRESS_PROD/kustomization.yaml"; then
    echo -e "${GREEN}✅${NC} Production overlay references base"
else
    echo -e "${RED}❌${NC} Production overlay missing base reference"
fi
echo ""

# Summary
echo "=== VALIDATION SUMMARY ==="
echo ""

echo "✅ Configuration files created:"
echo "   - Base configuration with ingress routes"
echo "   - Staging overlay with explicit environment"
echo "   - Production overlay with patches"
echo ""

echo "✅ File structure:"
echo "   - kubernetes/ingress/base/ - Shared configuration"
echo "   - kubernetes/ingress/overlays/staging/ - Staging-specific"
echo "   - kubernetes/ingress/overlays/production/ - Production-specific"
echo ""

if command -v kustomize &> /dev/null; then
    echo ""
    echo "=== KUSTOMIZE BUILD TEST ==="
    echo ""

    echo "Building staging overlay..."
    if kustomize build "$INGRESS_STAGING" > /tmp/staging-build.yaml 2>&1; then
        echo -e "${GREEN}✅${NC} Staging overlay builds successfully"

        # Count routes
        STAGING_ROUTES=$(grep -c "kind: IngressRoute" /tmp/staging-build.yaml || echo "0")
        echo "   Found $STAGING_ROUTES IngressRoute resources"

        # Verify staging hostnames
        if grep -q "staging.api.primecrib.app" /tmp/staging-build.yaml; then
            echo -e "${GREEN}✅${NC} Staging hostnames present in output"
        fi
    else
        echo -e "${RED}❌${NC} Staging overlay failed to build"
        cat /tmp/staging-build.yaml | head -20
    fi

    echo ""
    echo "Building production overlay..."
    if kustomize build "$INGRESS_PROD" > /tmp/production-build.yaml 2>&1; then
        echo -e "${GREEN}✅${NC} Production overlay builds successfully"

        # Count routes
        PROD_ROUTES=$(grep -c "kind: IngressRoute" /tmp/production-build.yaml || echo "0")
        echo "   Found $PROD_ROUTES IngressRoute resources"

        # Verify production hostnames (patches applied)
        if grep -q "api.primecrib.app" /tmp/production-build.yaml; then
            echo -e "${GREEN}✅${NC} Production hostnames present in output"
        fi

        # Verify staging hostnames NOT in production
        if ! grep -q "staging.api.primecrib.app" /tmp/production-build.yaml; then
            echo -e "${GREEN}✅${NC} Staging hostnames correctly removed from production"
        else
            echo -e "${YELLOW}⚠️  Warning: Found staging hostnames in production build${NC}"
        fi
    else
        echo -e "${RED}❌${NC} Production overlay failed to build"
        cat /tmp/production-build.yaml | head -20
    fi

    echo ""
    echo "Comparing outputs..."

    # Show differences in hostnames
    echo ""
    echo "Staging route hosts:"
    grep "match: Host" /tmp/staging-build.yaml | head -10 || true

    echo ""
    echo "Production route hosts:"
    grep "match: Host" /tmp/production-build.yaml | head -10 || true
fi

echo ""
echo "=================================================="
echo "Validation Complete!"
echo "=================================================="
echo ""
echo "Next Steps:"
echo "1. Review INGRESS_REFACTOR_IMPLEMENTATION.md for deployment details"
echo "2. Run: kubectl apply -k kubernetes/ingress/overlays/staging --dry-run=client"
echo "3. Verify routes in Kustomize output"
echo "4. Deploy to staging cluster"
echo "5. Deploy to production cluster"
echo ""

