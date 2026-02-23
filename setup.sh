#!/usr/bin/env bash

# Exit immediately if a command exits with a non-zero status
set -e

# Format colors
RED='\039[0;31m'
GREEN='\039[0;32m'
YELLOW='\039[1;33m'
NC='\039[0m' # No Color

echo -e "${GREEN}================================================${NC}"
echo -e "${GREEN}  OpenShift Local (CRC) GitOps Setup Wizard     ${NC}"
echo -e "${GREEN}================================================${NC}"
echo ""

# -------------------------------------------------------------------------
# Phase 1: OpenShift Local (CRC) Verification & Hardware Provisioning
# -------------------------------------------------------------------------
echo -e "${YELLOW}Phase 1: Environment Check${NC}"

if ! command -v crc &> /dev/null; then
  echo -e "${RED}[!] 'crc' binary is NOT installed or NOT in your PATH.${NC}"
  read -p "Would you like to install OpenShift Local (CRC) now? (y/n): " install_crc
  if [[ "$install_crc" =~ ^[Yy]$ ]]; then
    # Standard macOS download instructions for CRC
    echo -e "${GREEN}[+] Downloading latest OpenShift Local for Apple Silicon...${NC}"
    curl -L -o crc-mac-arm64.pkg "https://developers.redhat.com/content-gateway/rest/mirror/pub/openshift-v4/clients/crc/latest/crc-mac-arm64.pkg"
    echo -e "${GREEN}[+] Running macOS installer... (You may be prompted for your password)${NC}"
    sudo installer -pkg crc-mac-arm64.pkg -target /
    rm crc-mac-arm64.pkg
    echo -e "${GREEN}[+] OpenShift Local installed successfully.${NC}"
    export PATH=$PATH:/usr/local/bin
  else
    echo -e "${RED}[!] Installation aborted. Please install CRC manually and run setup again.${NC}"
    exit 1
  fi
else
  echo -e "${GREEN}[+] 'crc' binary is installed.${NC}"
fi

echo ""
echo -e "${YELLOW}OpenShift Local Hardware Configuration${NC}"
echo "We need to ensure your CRC VM has enough resources for this GitOps stack."

read -p "Target memory in MB (Default: 32768 [32GB]): " crc_ram
crc_ram=${crc_ram:-32768}

read -p "Target CPUs (Default: 8): " crc_cpu
crc_cpu=${crc_cpu:-8}

read -p "Target Disk Size in GB (Default: 64): " crc_disk
crc_disk=${crc_disk:-64}

echo -e "${GREEN}[+] Applying CRC hardware constraints...${NC}"
crc config set memory $crc_ram
crc config set cpus $crc_cpu
crc config set disk-size $crc_disk

echo -e "${GREEN}[✓] CRC Configuration saved. Remember to run 'crc setup' and 'crc start' later!${NC}"
echo ""

# -------------------------------------------------------------------------
# Phase 2: Template Configuration Generation
# -------------------------------------------------------------------------
echo -e "${YELLOW}Phase 2: Dynamic GitOps Configuration${NC}"

K_USER="iduenas"
K_PASS="cluster#01"
K_DOMAIN="apps-crc.testing"

# Due to CRC limitations, the domain is hardcoded to .testing. 
echo -e "${YELLOW}Note: OpenShift Local (CRC) strictly enforces the base domain 'testing' and apps domain 'apps-crc.testing'.${NC}"
echo -e "${YELLOW}This wizard will configure the stack against this static routing.${NC}"
echo ""

read -p "Enter Keycloak Initial Admin Username [$K_USER]: " input_user
K_USER=${input_user:-$K_USER}

read -p "Enter Keycloak Initial Admin Password [$K_PASS]: " -s input_pass
echo ""
K_PASS=${input_pass:-$K_PASS}

read -p "Specify TLS Strategy ('local-ca' or 'custom') [local-ca]: " input_tls
K_TLS=${input_tls:-"local-ca"}

echo ""
echo -e "${GREEN}[+] Generating Keycloak Database Secret...${NC}"

# Create/Overwrite the Postgres & Keycloak shared database Secret Manifest
cat <<EOF > clusters/crc/services/postgres/secret.yaml
apiVersion: v1
kind: Secret
metadata:
  name: keycloak-db-secret
  namespace: postgres
  annotations:
    argocd.argoproj.io/sync-wave: "-1"
type: Opaque
stringData:
  POSTGRES_DB: keycloak
  POSTGRES_USER: keycloak
  POSTGRES_PASSWORD: ${K_PASS}
EOF

# Provide a copy for the Keycloak CR itself to mount (cross-namespace secrets are not permitted)
cat <<EOF > clusters/crc/services/keycloak/db-secret.yaml
apiVersion: v1
kind: Secret
metadata:
  name: keycloak-db-secret
  namespace: keycloak
  annotations:
    argocd.argoproj.io/sync-wave: "-1"
type: Opaque
stringData:
  POSTGRES_DB: keycloak
  POSTGRES_USER: keycloak
  POSTGRES_PASSWORD: ${K_PASS}
EOF

# Ensure the db-secret is added to the keycloak kustomization
if ! grep -q "db-secret.yaml" clusters/crc/services/keycloak/kustomization.yaml; then
  echo "  - db-secret.yaml" >> clusters/crc/services/keycloak/kustomization.yaml
fi

# Use sed/awk equivalents to safely replace username/pw in gitops config if needed 
# Instead, we will generate the keycloak initial admin secret dynamically.
cat <<EOF > clusters/crc/services/keycloak/admin-secret.yaml
apiVersion: v1
kind: Secret
metadata:
  name: custom-keycloak-admin-secret
  namespace: keycloak
type: Opaque
stringData:
  username: ${K_USER}
  password: ${K_PASS}
EOF

# Ensure the admin-secret is added to the keycloak kustomization
if ! grep -q "admin-secret.yaml" clusters/crc/services/keycloak/kustomization.yaml; then
  echo "  - admin-secret.yaml" >> clusters/crc/services/keycloak/kustomization.yaml
fi

echo -e "${GREEN}[✓] Secrets successfully templated!${NC}"
echo ""

echo -e "${YELLOW}Phase 2.5: OpenShift Identity Provider Integration${NC}"

# Generate a secure OAuth client secret
OIDC_SECRET=$(openssl rand -hex 16)

# Generate the Keycloak Realm Import YAML
cat <<EOF > clusters/crc/services/keycloak/realm-import.yaml
apiVersion: k8s.keycloak.org/v2alpha1
kind: KeycloakRealmImport
metadata:
  name: openshift-realm
  namespace: keycloak
spec:
  keycloakCRName: keycloak
  realm:
    id: openshift
    realm: openshift
    enabled: true
    loginWithEmailAllowed: false
    users:
      - username: ${K_USER}
        enabled: true
        emailVerified: true
        firstName: ${K_USER}
        lastName: Admin
        email: ${K_USER}@conflux.local
        requiredActions: []
        credentials:
          - type: password
            value: "${K_PASS}"
            temporary: false
        realmRoles:
          - default-roles-openshift
    clients:
      - clientId: openshift
        secret: ${OIDC_SECRET}
        enabled: true
        protocol: openid-connect
        standardFlowEnabled: true
        implicitFlowEnabled: false
        directAccessGrantsEnabled: true
        redirectUris:
          - "https://oauth-openshift.apps-crc.testing/*"
          - "https://console-openshift-console.apps-crc.testing/*"
EOF

# Ensure realm-import is added to keycloak kustomization
if ! grep -q "realm-import.yaml" clusters/crc/services/keycloak/kustomization.yaml; then
  echo "  - realm-import.yaml" >> clusters/crc/services/keycloak/kustomization.yaml
fi

# Prepare OpenShift-Config OIDC Secret for OpenShift OAuth
mkdir -p clusters/crc/services/openshift-config
cat <<EOF > clusters/crc/services/openshift-config/oidc-secret.yaml
apiVersion: v1
kind: Secret
metadata:
  name: keycloak-oidc-secret
  namespace: openshift-config
type: Opaque
stringData:
  clientSecret: ${OIDC_SECRET}
EOF

# Create OpenShift ClusterRoleBinding for the created user
cat <<EOF > clusters/crc/services/openshift-config/cluster-role-binding.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: keycloak-cluster-admin-${K_USER}
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
  - kind: User
    name: ${K_USER}
EOF

# Provide OpenShift OAuth with the trusted CA for Keycloak
if [ "${K_TLS}" == "local-ca" ]; then
  if [ -f "local-ca.crt" ]; then
    CA_CONTENT=$(cat local-ca.crt | sed 's/^/    /')
    cat <<EOF > clusters/crc/services/openshift-config/oidc-ca.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: keycloak-oidc-ca
  namespace: openshift-config
data:
  ca.crt: |
${CA_CONTENT}
EOF
  else
    echo -e "\${YELLOW}[!] local-ca.crt not found, skipping CA map for OIDC.\${NC}"
  fi
else
    echo -e "\${YELLOW}[!] Custom TLS: Defaulting to an empty CA map.\${NC}"
    cat <<EOF > clusters/crc/services/openshift-config/oidc-ca.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: keycloak-oidc-ca
  namespace: openshift-config
EOF
fi

echo -e "${GREEN}[✓] OpenShift Single Sign-On templated!${NC}"
echo ""

# -------------------------------------------------------------------------
# Phase 3: Final Deployment Hooks
# -------------------------------------------------------------------------
echo -e "${YELLOW}Phase 3: Finalize Setup${NC}"

# Persist selections to values-template for future reference
cat <<EOF > values-template.yaml
# Automatically generated configuration 
cluster:
  domain: ${K_DOMAIN}
keycloak:
  admin_user: ${K_USER}
  hostname: keycloak-keycloak.${K_DOMAIN}
tls:
  provider: ${K_TLS}
EOF

echo ""
echo -e "${GREEN}================================================${NC}"
echo -e "${GREEN}  Setup Complete!                                ${NC}"
echo -e "${GREEN}================================================${NC}"
echo ""
echo "Next Steps:"
echo "1. Commit these unstaged changes: git add . && git commit -m 'chore: run setup wizard'"
echo "2. Push to your Git Repository: git push origin main"
echo "3. Run your bootstrap script: ./bootstrap.sh"
echo ""
