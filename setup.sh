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
# Phase 2: Day 0 Security Bootstrap
# -------------------------------------------------------------------------
echo -e "${YELLOW}Phase 2: Day 0 Security Bootstrap (Sealed Secrets)${NC}"

# Ensure kube-system exists or the secret will fail
oc create namespace kube-system --dry-run=client -o yaml | oc apply -f -

if [ -f "master.key" ]; then
  echo -e "${GREEN}[+] Found master.key! Restoring the Bitnami Sealed Secrets master key...${NC}"
  oc apply -f master.key
  echo -e "${GREEN}[✓] Master key restored. ArgoCD will be able to decrypt your repository's secrets.${NC}"
else
  echo -e "${YELLOW}[!] No master.key found locally.${NC}"
  echo -e "    If this is your first time running, the Bitnami controller will generate a new one."
  echo -e "    Be sure to back it up later by running:"
  echo -e "    oc get secret -n kube-system -l sealedsecrets.bitnami.com/sealed-secrets-key=active -o yaml > master.key"
fi

echo ""

# -------------------------------------------------------------------------
# Phase 3: Final Deployment Hooks
# -------------------------------------------------------------------------
echo -e "${YELLOW}Phase 3: Finalize Setup${NC}"

echo ""
echo -e "${GREEN}================================================${NC}"
echo -e "${GREEN}  Setup Complete!                                ${NC}"
echo -e "${GREEN}================================================${NC}"
echo ""
echo "Next Steps:"
echo "1. Stage ONLY non-secret tracked changes:"
echo "     git add -u && git commit -m 'chore: run setup wizard'"
echo "   ⚠  Do NOT run 'git add .' — secret files are .gitignored and must stay local."
echo "2. Push to your Git Repository: git push origin main"
echo "3. Run your bootstrap script: ./bootstrap.sh"
echo ""
