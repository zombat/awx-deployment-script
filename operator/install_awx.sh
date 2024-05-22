#!/usr/bin/env bash

# Define the paths for your certificate and key files
CERT_FILE="./server.crt"
KEY_FILE="./server.key"

# Ensure git is installed
if ! command -v git &> /dev/null; then
    sudo dnf install -y git
fi

create_directory() {
    local dir="$1"
    if [ ! -d "$dir" ]; then
        mkdir -p "$dir"
    fi
}

prompt_for_input() {
    local prompt_message="$1"
    local default_value="$2"
    local input
    while true; do
        read -p "$prompt_message" input
        input=${input:-$default_value}
        read -p "You entered $input. Is this correct? (y/n): " yn
        case $yn in
            [Yy]* ) echo "$input"; break;;
            [Nn]* ) continue;;
            * ) echo "Please answer yes or no.";;
        esac
    done
}

get_and_confirm_password() {
    local password
    local confirm_password
    while true; do
        echo >&2
        read -s -p "Enter the AWX Password: " password
        echo >&2
        read -s -p "Confirm the AWX Password: " confirm_password
        echo >&2
        if [ "$password" == "$confirm_password" ]; then
            echo "Password confirmed." >&2
            break
        else
            echo "Passwords do not match. Please try again." >&2
        fi
    done
    printf "%s" "$password"
}

create_secret() {
    local namespace="$1"
    local password="$2"
    if ! kubectl get -n "$namespace" secret awx-admin-password &> /dev/null; then
        kubectl create secret generic awx-admin-password --from-literal=password="\"$password\"" -n $namespace
        echo "Secret awx-admin-password created."
    else
        echo "Secret awx-admin-password already exists. Skipping creation."
    fi
}

apply_kustomization() {
    local stage="$1"
    if [ "$stage" == "stage_one" ]; then
        if kubectl get deployment awx-operator-controller-manager -n "$namespace" &> /dev/null; then
            local action
            read -p "AWX Operator is already running in the cluster. Overwrite? (y/n): " action
            [[ "$action" =~ [Yy] ]] && kubectl apply -k "$stage/" || echo "Skipping installation."
        else
            echo "Deploying AWX Operator."
            kubectl apply -k "$stage/"
            # Wait 60 seconds for the operator to be ready
            echo "Waiting for 60 seconds for the operator to be ready..."
            sleep 60
        fi
    elif [ "$stage" == "stage_two" ]; then
        if kubectl get pods -n "$namespace" -l "app.kubernetes.io/component=database" --no-headers | grep -q '.'; then
            local action
            read -p "AWX may already be deployed. Overwrite? (y/n): " action
            [[ "$action" =~ [Yy] ]] && kubectl apply -k "$stage/" || echo "Skipping installation."
        else
            echo "Deploying AWX."
            kubectl apply -k "$stage/"
        fi
    fi
}

create_directory "./stage_one"
create_directory "./stage_two"

# Pods won't come online with firewalld enabled... Not sure what ports it needs...
echo "Disabling firewall"
sudo systemctl disable firewalld
sudo systemctl stop firewalld
echo ""

namespace=$(prompt_for_input "Enter the Operator/AWX Namespace: " "awx")
operator_version=$(prompt_for_input "Enter the target Operator version: " "2.13.1")
username=$(prompt_for_input "Enter the AWX Username: " "awx_admin")
awx_fqdn=$(prompt_for_input "Enter the AWX FQDN: " "awx.local")
password=$(get_and_confirm_password)
echo ""
echo ""

# Check if the certificate and key files already exist
if [[ ! -f "$CERT_FILE" || ! -f "$KEY_FILE" ]]; then
    echo "Generating self-signed certificate and key with FQDN: $awx_fqdn."

    # Generate a new self-signed certificate and key pair using openssl
    openssl req -x509 -newkey rsa:2048 -nodes -keyout "$KEY_FILE" -out "$CERT_FILE" -days 365 \
        -subj "/C=US/ST=State/L=City/O=Organization/OU=Unit/CN=$awx_fqdn"

    echo "Self-signed certificate and key have been generated."
else
    echo "Certificate and key already exist, skipping generation."
fi

# Create configurations
cp "./templates/stage_one_kustomization.yml" "./stage_one/kustomization.yaml"
cp "./templates/stage_two_kustomization.yml" "./stage_two/kustomization.yaml"
cp "./templates/stage_two_awx.yaml" "./stage_two/awx.yaml"
cp "./templates/stage_two_awx-ingress.yaml" "./stage_two/awx-ingress.yaml"

# Substitute placeholders
sed -i "s/<NAMESPACE>/$namespace/g" ./stage_one/kustomization.yaml ./stage_two/kustomization.yaml
sed -i "s/<OPERATOR_VERSION>/$operator_version/g" ./stage_one/kustomization.yaml ./stage_two/kustomization.yaml
sed -i "s/<ADMIN_USER>/$username/g" ./stage_two/awx.yaml
sed -i "s/<AWX_FQDN>/$awx_fqdn/g" ./stage_two/awx-ingress.yaml
sed -i "s/<NAMESPACE>/$namespace/g" ./stage_two/awx-ingress.yaml

# sudo firewall-cmd --add-port=8080/tcp --permanent
# sudo firewall-cmd --reload
apply_kustomization "stage_one"

echo ""
kubectl -n $namespace create secret generic awx-admin-password --from-literal=password=$password
echo ""
kubectl create secret -n $namespace tls awx-tls --cert=$CERT_FILE --key=$KEY_FILE
sudo cp $CERT_FILE /etc/pki/ca-trust/source/anchors/
echo ""
echo "Updating CA trust"
sudo update-ca-trust
echo ""

echo "Deploying AWX..."
apply_kustomization "stage_two"

echo ""
echo ""
echo "Wait for 2 minutes and check: http://$awx_fqdn"
echo "You can also run: watch kubectl get pods -n $namespace"
echo "You can also watch the logs with: kubectl logs -f deployments/awx-operator-controller-manager -c awx-manager --namespace $namespace"

echo ""
echo "Your admin username is: $username"
echo "Your password is: $password"
