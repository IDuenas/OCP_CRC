# OpenShift Local (CRC) GitOps Deployment Guide

This repository contains the Infrastructure as Code (IaC) required to bootstrap a complete development environment on OpenShift Local (CRC) using Red Hat OpenShift GitOps (Argo CD).

## Architecture Overview

The deployment leverages an **Argo CD ApplicationSet** (`dev-stack-generator`) configured with a **Git Generator**. This enables dynamic and automatic deployment of any service simply by creating a new directory under `clusters/crc/services/`.

The cluster is specifically tuned for an **ARM64 (Apple Silicon M2 Max)** environment.

### Core Components

1.  **Red Hat OpenShift GitOps:** The primary controller managing the synchronization of the repository state with the cluster.
2.  **Cert-Manager (`cert-manager-operator`):** Automates the issuance of TLS certificates. A Local Certificate Authority (CA) is created here to issue trusted SSL certificates for local `.apps-crc.testing` domains.
3.  **PostgreSQL (`postgres`):** A development-optimized PostgreSQL instance acting as the backend database for Keycloak. It utilizes a `10Gi` PersistentVolumeClaim and is tuned for 128GB RAM constraints.
4.  **Red Hat Build of Keycloak (`keycloak`):** The IAM/SSO provider, deployed using the RHBK Operator. It is securely configured with a Postgres backend and properly terminated SSL via Cert-Manager.
5.  **Console Customization (`console-customization`):** Injects a direct dashboard link to Keycloak within the Developer Tools section of the OpenShift Web Console.

## Prerequisites

Before deploying the stack, ensure the following are installed and configured:

1.  **OpenShift Local (CRC)** installed and actively running (`crc start`).
2.  Hardware minimums: At least 32GB RAM and 8 CPU cores allocated to CRC. (Production/Heavy development setups on Apple Silicon recommend expanding the CRC virtual disk to 64GB+ using `crc config set disk-size 64`).
3.  **Red Hat OpenShift GitOps Operator** must be installed on the cluster.
4.  Must be authenticated to the cluster (`oc login -u kubeadmin -p <password> https://api.crc.testing:6443`).

## Setup Instructions

### 1. Configure the Stack (Optional Turn-Key Setup)
To customize parameters like the Keycloak admin credentials or automatically download/configure OpenShift Local constraints (CPU, RAM, Disk):

```bash
chmod +x setup.sh
./setup.sh
```
*Note: This script will dynamically template the GitOps Secrets and values based on your input.*

### 2. Bootstrap the Cluster

A bootstrap script has been provided to initialize the GitOps flow.

```bash
chmod +x bootstrap.sh
./bootstrap.sh
```

**What this does:** It applies the `clusters/crc/applicationset.yaml`, which instructs Argo CD to scan the `services/` directory and deploy all configured applications automatically.

### 2. Monitor Deployment

You can log into the OpenShift Web Console or the OpenShift GitOps (Argo) dashboard to monitor the synchronization. 

*   **Argo Default Credentials:**
    *   **Username:** `admin`
    *   **Password:** Run `oc extract secret/openshift-gitops-cluster -n openshift-gitops --keys=admin.password --to=-`

### 3. Trust the Local CA (macOS)

To ensure secure, padlock-verified connections (avoiding "Connection is not private" errors in Chrome/Safari) without public certificate warnings:

1. Locate the generated `local-ca.crt` file in your repository root.
2. Double-click it to open **Keychain Access**.
3. Double-click the imported certificate named `local-ca`.
4. Expand the **Trust** section.
5. Change **"When using this certificate"** to **Always Trust**.
6. Restart your browser.

## Git Workflow Details

This repository adheres to standard GitOps practices:

- **Declarative Operations:** All cluster modifications or Operator subscriptions MUST be enacted by creating or modifying manifests in the `clusters/crc/services` directory. Avoid manually running `oc create` or editing resources directly in the UI.
- **Commit History:** Every deployment change is tracked. Git commit messages follow descriptive conventions (e.g., `feat:`, `fix:`, `docs:`) to document exactly what infrastructure changes were introduced.

### Engineering Notes

- **Architecture Filtering:** When managing operators via the OpenShift UI, ensure "ARM64" filtering is toggled, as some multi-arch operators are accidentally hidden by default.
- **Single-Namespace Operators:** Operators such as RHBK use a single-namespace installation model (an isolated `OperatorGroup` inside the `keycloak` namespace) due to limitations with `AllNamespaces` requirements in newer operator lifecycle pipelines. 
- **Resource Tolerations:** By default, CRC runs with tight disk quotas (~32GB default). If usage exceeds 85%, OpenShift taints the node with disk-pressure. All Deployments and StatefulSets here are configured with `node.kubernetes.io/disk-pressure` tolerations to prevent service outages.
