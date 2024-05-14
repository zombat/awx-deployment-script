# Readme.md

## K3s Installation and Management Script

This script provides functionalities to manage K3s installations, including online and offline installation, and firewall configurations. Below are the instructions for using the script.

## Usage

```bash
./k3s/k3s_tool.sh [option]
```
```text
Options
    --remove-k3s: Uninstall K3s.
    --online-install: Install K3s online.
    --offline-prep: Prepare files for offline installation.
    --offline-install: Install K3s offline.
```

## AWX Deployment Script

This script provides functionalities to deploy AWX on a Kubernetes cluster. It handles the setup of necessary namespaces, secrets, and configurations, and prompts the user for required input. Below are the instructions for using the script.

## Prerequisites

Ensure the following prerequisites are met:
- `git` is installed on the system.
- `kubectl` is installed and configured to interact with your Kubernetes cluster.
- `openssl` is available for generating certificates.

## Usage

```bash
./operator/deploy_awx.sh
