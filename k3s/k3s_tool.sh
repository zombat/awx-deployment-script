#!/bin/bash

# Function to find k3s versions in repository
k3s_versions() {
  curl -s https://api.github.com/repos/k3s-io/k3s/releases | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/'
}

check_and_disable_selinux() {
    if [ -f /etc/selinux/config ] && [ "$(getenforce)" = "Enforcing" ]; then
        echo ""
        echo "Disabling SELinux..."
        sudo sed -i 's/^SELINUX=.*/SELINUX=disabled/g' /etc/selinux/config
        sudo setenforce 0
        echo "SELinux is disabled. Please reboot the system to apply changes when convenient."
        echo ""
    else
        echo ""
        echo "SELinux is not in enforcing mode or not configured. No changes made."
        echo ""
    fi
}

# k3s firewall rules
set_firewall(){
  # if $1 == set, set firewall rules
  if [ "$1" == "set" ]; then
    echo ""
    echo "Setting k3s firewall rules..."
    echo ""
    echo "Opening ports 6443, 8472, 10250-10254, 30000-32767"
    sudo firewall-cmd --add-port=6443/tcp --permanent
    sudo firewall-cmd --add-port=8472/udp --permanent
    sudo firewall-cmd --add-port=10250-10254/tcp --permanent
    sudo firewall-cmd --add-port=30000-32767/tcp --permanent
    sudo firewall-cmd --reload
  fi
  # if $1 == unset, unset firewall rules
  if [ "$1" == "unset" ]; then
    echo ""
    echo "Unsetting k3s firewall rules..."
    echo ""
    echo "Closing ports 6443, 8472, 10250-10254, 30000-32767"
    sudo firewall-cmd --remove-port=6443/tcp --permanent
    sudo firewall-cmd --remove-port=8472/udp --permanent
    sudo firewall-cmd --remove-port=10250-10254/tcp --permanent
    sudo firewall-cmd --remove-port=30000-32767/tcp --permanent
    sudo firewall-cmd --reload
  fi
}

# Function to check file existence and download if not present
fetch_file() {
  local url=$1
  local file=$2
  if [ ! -f "$file" ]; then
    echo "Downloading $file..."
    curl -L -o "$file" "$url" || { echo "Failed to download $file"; exit 1; }
  else
    echo "$file exists"
  fi
}

# Uninstall k3s
if [ "$1" == "--remove-k3s" ]; then
  k3s-uninstall.sh
  set_firewall unset
  echo "Removing kubeconfig..."
  rm -f ~/.kube/config
  exit 0
fi

# Online installation of k3s
if [ "$1" == "--online-install" ]; then
  set_firewall set
  check_and_disable_selinux
  curl -sfL https://get.k3s.io | sh -s - --write-kubeconfig-mode 644
  export KUBECONFIG=~/.kube/config
  echo "export KUBECONFIG=~/.kube/config" >> ~/.bashrc
  mkdir ~/.kube
  sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
  sudo chown $USER:$USER ~/.kube/config
  sudo systemctl enable --now k3s
  systemctl status k3s > k3s.status.log
  kubectl describe nodes > k3s.nodes.log
fi

# Offline preparation
if [ "$1" == "--offline-prep" ]; then
  echo "Select k3s version for offline installation:"
  k3s_versions
  read -p "Enter k3s version: " version

  fetch_file "https://get.k3s.io" "./install.sh"
  fetch_file "https://github.com/k3s-io/k3s/releases/download/$version/k3s-airgap-images-amd64.tar.gz" "./k3s-airgap-images-amd64.tar.gz"
  fetch_file "https://github.com/k3s-io/k3s/releases/download/$version/k3s" "./k3s"
  fetch_file "https://github.com/k3s-io/k3s-selinux/releases/download/$version/k3s-selinux.tar.gz" "./k3s-selinux.tar.gz"
fi

# Offline installation
if [ "$1" == "--offline-install" ]; then
  if [ ! -f ./install.sh ] || [ ! -f ./k3s-airgap-images-amd64.tar.gz ] || [ ! -f ./k3s ]; then
    echo "Missing files for installation."
    exit 1
  fi
  set_firewall set
  check_and_disable_selinux
  chmod +x ./install.sh ./k3s
  sudo cp ./k3s /usr/local/bin/k3s
  sudo cp ./k3s /usr/bin/k3s
  ./install.sh --write-kubeconfig-mode 644
  export KUBECONFIG=~/.kube/config
  echo "export KUBECONFIG=~/.kube/config" >> ~/.bashrc
  mkdir ~/.kube
  sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
  sudo chown $USER:$USER ~/.kube/config
  sudo systemctl enable --now k3s
  systemctl status k3s > k3s.status.log
  kubectl describe nodes > k3s.nodes.log
fi

# Online add node
if [ "$1" == "--add-node-online" ]; then
  echo "Enter the IP address of the k3s server:"
  read -p "Server IP: " server_ip
  echo "Enter the token for joining the cluster:"
  read -p "Token: " token
  # Get kubeconfig from server
  mkdir -p ~/.kube
  scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null $server_ip:/etc/rancher/k3s/k3s.yaml ~/.kube/config
  export KUBECONFIG=~/.kube/config
  # replace server IP in kubeconfig
  sed -i "s/127.0.0.1/$server_ip/g" ~/.kube/config
  echo "export KUBECONFIG=~/.kube/config" >> ~/.bashrc
  curl -sfL https://get.k3s.io | K3S_URL=https://$server_ip:6443 K3S_TOKEN=$token sh -
fi

# Offline add node
if [ "$1" == "--add-node-offline" ]; then
  if [ ! -f ./install.sh ] || [ ! -f ./k3s-airgap-images-amd64.tar.gz ] || [ ! -f ./k3s ]; then
    echo "Missing files for installation."
    exit 1
  fi
  echo "Enter the IP address of the k3s server:"
  read -p "Server IP: " server_ip
  echo "To find the token, run the following command on the server:"
  echo "sudo cat /var/lib/rancher/k3s/server/node-token"
  echo "Enter the token for joining the cluster:"
  read -p "Token: " token
  chmod +x ./install.sh ./k3s
  sudo cp ./k3s /usr/local/bin/k3s
  sudo cp ./k3s /usr/bin/k3s
  # Get kubeconfig from server
  mkdir -p ~/.kube
  scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null $server_ip:/etc/rancher/k3s/k3s.yaml ~/.kube/config
  export KUBECONFIG=~/.kube/config
  # replace server IP in kubeconfig
  sed -i "s/127.0.0.1/$server_ip/g" ~/.kube/config
  echo "export KUBECONFIG=~/.kube/config" >> ~/.bashrc
  ./install.sh --server https://$server_ip:6443 --token $token
fi  

# Display options if no arguments are provided
if [ -z "$1" ]; then
  echo "Usage: $0 [option]"
  echo "Options:"
  echo "  --remove-k3s: Uninstall k3s"
  echo "  --online-install: Install k3s online"
  echo "  --offline-prep: Prepare for offline installation"
  echo "  --offline-install: Install k3s offline"
  echo "  --add-node-online: Add a node to the cluster online"
  echo "  --add-node-offline: Add a node to the cluster offline"
fi
