#!/bin/bash
#
# install.sh
#
# This script installs software prerequisites
#
# usage:
#
#   install-azure-space-sdk.sh

INSTALL_SCRIPT_URI_AZ="https://aka.ms/InstallAzureCLIDeb"
INSTALL_SCRIPT_URI_DOCKER="https://get.docker.com"
INSTALL_SCRIPT_URI_K3S="https://get.k3s.io"
INSTALL_SCRIPT_VER_K3S="v1.25.2+k3s1"
INSTALL_SCRIPT_URI_HELM="https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3"
DAPR_VERSION="1.8"
DAPR_HELM_CHART_DOWNLOAD_URI="https://github.com/dapr/helm-charts/raw/master/dapr-1.8.4.tgz"
DOCKER_CE_VERSION="5:20.10.23~3-0~ubuntu-focal"
DOCKER_COMPOSE_VERSION="v2.11.2"
INSTALL_SCRIPT_URI_ORAS="https://github.com/oras-project/oras/releases/download/v0.16.0/oras_0.16.0_linux_amd64.tar.gz"

install_az() {
    export DEBIAN_FRONTEND=noninteractive
    echo "Uninstalling previously installed versions..."
    sudo apt-get remove -y azure-cli
    sudo rm -rf ~/.azure
    # https://docs.microsoft.com/en-us/cli/azure/install-azure-cli-linux?pivots=apt#option-1-install-with-one-command
    echo "Installing Azure CLI..."
    sudo apt-get update -y
    sudo apt-get install -y ca-certificates curl apt-transport-https lsb-release gnupg
    curl -sL "$INSTALL_SCRIPT_URI_AZ" | sudo bash
}

install_k3s() {
    # https://rancher.com/docs/k3s/latest/en/installation/install-options/#options-for-installation-with-script
    echo "Installing K3S..."
    curl -sfL "$INSTALL_SCRIPT_URI_K3S" | INSTALL_K3S_VERSION="$INSTALL_SCRIPT_VER_K3S" sh -s - --write-kubeconfig-mode "0644"
    export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
    echo "export KUBECONFIG=/etc/rancher/k3s/k3s.yaml" >>~/.bashrc
}

install_helm() {
    # https://helm.sh/docs/intro/install/#from-script
    echo "Installing Helm..."
    curl "$INSTALL_SCRIPT_URI_HELM" | bash
}

install_dapr() {
    # https://docs.dapr.io/operations/hosting/kubernetes/kubernetes-deploy/#install-with-helm-advanced
    echo "Installing Dapr Helm Chart..."

    local_dapr_dir="${PWD}/dapr-helm-chart"

    if [ ! -d "$local_dapr_dir" ]; then
        mkdir -p "$local_dapr_dir"
        curl --output "$local_dapr_dir"/dapr-helm-charts.tgz -L $DAPR_HELM_CHART_DOWNLOAD_URI
        tar -xf "$local_dapr_dir/dapr-helm-charts.tgz" -C "$local_dapr_dir"
        rm "$local_dapr_dir/dapr-helm-charts.tgz"
    fi

    # Add the official Dapr Helm chart
    helm upgrade --install dapr "$local_dapr_dir/dapr" \
        --version=$DAPR_VERSION \
        --kubeconfig "/etc/rancher/k3s/k3s.yaml" \
        --namespace dapr-system \
        --create-namespace \
        --wait
}

install_docker() {
    # https://docs.docker.com/engine/install/ubuntu/#install-using-the-convenience-script
    echo "Installing Docker..."
    curl -fsSL "$INSTALL_SCRIPT_URI_DOCKER" | sudo bash
    sudo chmod 666 /var/run/docker.sock
}

install_docker_compose() {
    echo "Installing Docker Compose..."
    sudo curl \
        -L "https://github.com/docker/compose/releases/download/$DOCKER_COMPOSE_VERSION/docker-compose-$(uname -s)-$(uname -m)" \
        -o /usr/local/bin/docker-compose

    chmod +x /usr/local/bin/docker-compose
}

install_docker_ce() {
    echo "Installing docker-ce & docker-ce-cli ..."
    sudo apt install -y apt-transport-https ca-certificates curl software-properties-common
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
    sudo add-apt-repository -y "deb [arch=amd64] https://download.docker.com/linux/ubuntu focal stable"
    echo "Setting docker-ce version compatibilty..."
    sudo apt-get install -y docker-ce=$DOCKER_CE_VERSION docker-ce-cli=$DOCKER_CE_VERSION containerd.io docker-buildx-plugin docker-compose-plugin --allow-downgrades
}

install_jq() {
    echo "Installing jq..."
    sudo apt-get update
    sudo apt-get install -y jq
}

install_oras() {
    echo "Installing ORAS cli..."
    curl -LO $INSTALL_SCRIPT_URI_ORAS
    mkdir -p oras-install/
    tar -zxf oras_0.16.0_*.tar.gz -C oras-install/
    sudo mv oras-install/oras /usr/local/bin/
    rm -rf oras_0.16.0_*.tar.gz oras-install/
}

main() {
    install_az
    install_k3s
    install_helm
    install_dapr
    install_docker
    install_docker_compose
    install_docker_ce
    install_jq
    install_oras
}

main
