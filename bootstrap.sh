#!/bin/bash
set -e

# Define color codes for output
GREEN='\033[0;32m'
NC='\033[0m' # No Color

echo -e "${GREEN}==> Bootstrapping CRC OpenShift Cluster with ArgoCD GitOps...${NC}"

# Ensure the user is logged in
if ! oc whoami >/dev/null 2>&1; then
  echo "Error: You must be logged in to OpenShift (e.g., oc login -u kubeadmin -p <password> https://api.crc.testing:6443)"
  exit 1
fi

echo -e "${GREEN}==> Deploying the ApplicationSet Git Generator (dev-stack-generator)...${NC}"
oc apply -f clusters/crc/applicationset.yaml

echo -e "${GREEN}==> Done! ArgoCD ApplicationSet created.${NC}"
echo "    Check ArgoCD / OpenShift Console to monitor the syncing of the 'clusters/crc/services' directory."
echo ""
echo "    Remember: The services will deploy to their respective namespaces automatically."
echo "    (e.g., keycloak to 'keycloak', postgres to 'postgres')"
