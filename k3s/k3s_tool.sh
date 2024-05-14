#!/bin/bash

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
  fetch_file "https://get.k3s.io" "./install.sh"
  fetch_file "https://github.com/k3s-io/k3s/releases/download/v1.29.1-rc2+k3s1/k3s-airgap-images-amd64.tar.gz" "./k3s-airgap-images-amd64.tar.gz"
  fetch_file "https://github.com/k3s-io/k3s/releases/download/v1.29.1-rc2+k3s1/k3s" "./k3s"
  fetch_file "https://github.com/k3s-io/k3s-selinux/releases/download/v1.0.1-rc1+k3s1/k3s-selinux.tar.gz" "./k3s-selinux.tar.gz"
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

# Display options if no arguments are provided
if [ -z "$1" ]; then
  echo "Usage: $0 [option]"
  echo "Options:"
  echo "  --remove-k3s: Uninstall k3s"
  echo "  --online-install: Install k3s online"
  echo "  --offline-prep: Prepare for offline installation"
  echo "  --offline-install: Install k3s offline"
fi
