#!/bin/bash
set -ex

# disable swap
disable_swap() {
    sed -i '/ swap / s/^/#/' /etc/fstab
    sed -i '/swap/ s/^/#/' /etc/fstab
}

fetch_containerd() {
    # TODO configurable
    containerd_url="https://github.com/containerd/containerd/releases/download/v2.1.4/containerd-2.1.4-linux-amd64.tar.gz"

    tmp_dir=$(mktemp -d)
    wget -O ${tmp_dir}/containerd.tar.gz ${containerd_url}
    tar -xvzf ${tmp_dir}/containerd.tar.gz -C /usr/local
}

setup_containerd_systemd_unit() {
    # download systemd file
    wget -O /etc/systemd/system/containerd.service  https://raw.githubusercontent.com/containerd/containerd/main/containerd.service
    systemctl daemon-reload
    systemctl enable --now containerd
}

install_runc() {
    # TODO configurable
    wget -O ${tmp_dir}/runc https://github.com/opencontainers/runc/releases/download/v1.3.2/runc.amd64
    install -m 755 ${tmp_dir}/runc /usr/local/sbin/runc
}

install_cni_plugins() {
    local ARCH=$1
    local CNI_PLUGINS_VERSION=$2
    local DEST="/opt/cni/bin"
    mkdir -p "$DEST"
    curl -L "https://github.com/containernetworking/plugins/releases/download/${CNI_PLUGINS_VERSION}/cni-plugins-linux-${ARCH}-${CNI_PLUGINS_VERSION}.tgz" | tar -C "$DEST" -xz
}


build_containerd_config() {
    # Configuring the systemd cgroup driver
    # generate default toml
    mkdir -p /etc/containerd
    containerd config default > /etc/containerd/config.toml
   
    sed -i "/plugins.'io.containerd.cri.v1.runtime'.containerd.runtimes.runc.options/a SystemdCgroup = true" /etc/containerd/config.toml
    systemctl restart containerd
}


install_containerd() {
    # setup containerd
    # https://kubernetes.io/docs/setup/production-environment/container-runtimes/
    # https://github.com/containerd/containerd/blob/main/docs/getting-started.md
    setup_containerd_systemd_unit
    fetch_containerd
    install_runc
    install_cni_plugins "amd64" "v1.8.0"
    build_containerd_config
}


network_prerequisites() {
    # sysctl params required by setup, params persist across reboots
    cat <<EOF | tee /etc/sysctl.d/k8s.conf
net.ipv4.ip_forward = 1
EOF

    # Apply sysctl params without reboot
    sysctl --system

    sysctl net.ipv4.ip_forward
}

setup_cri() {
    network_prerequisites
    install_containerd
}

install_kubectl() {
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
}





install_crictl() {
    CRICTL_VERSION="v1.31.0"
    ARCH="amd64"
    curl -L "https://github.com/kubernetes-sigs/cri-tools/releases/download/${CRICTL_VERSION}/crictl-${CRICTL_VERSION}-linux-${ARCH}.tar.gz" | tar -C $DOWNLOAD_DIR -xz
}

create_download_dir() {
    DOWNLOAD_DIR="/usr/local/bin"
    mkdir -p "$DOWNLOAD_DIR"
}


install_kubeadm_kubelet_as_systemd_service() {
    RELEASE="$(curl -sSL https://dl.k8s.io/release/stable.txt)"
    ARCH="amd64"
    cd $DOWNLOAD_DIR
    curl -L --remote-name-all https://dl.k8s.io/release/${RELEASE}/bin/linux/${ARCH}/{kubeadm,kubelet}
    chmod +x {kubeadm,kubelet}

    RELEASE_VERSION="v0.16.2"
    curl -sSL "https://raw.githubusercontent.com/kubernetes/release/${RELEASE_VERSION}/cmd/krel/templates/latest/kubelet/kubelet.service" | sed "s:/usr/bin:${DOWNLOAD_DIR}:g" | tee /usr/lib/systemd/system/kubelet.service
    mkdir -p /usr/lib/systemd/system/kubelet.service.d
    curl -sSL "https://raw.githubusercontent.com/kubernetes/release/${RELEASE_VERSION}/cmd/krel/templates/latest/kubeadm/10-kubeadm.conf" | sed "s:/usr/bin:${DOWNLOAD_DIR}:g" | tee /usr/lib/systemd/system/kubelet.service.d/10-kubeadm.conf

    systemctl enable --now kubelet
}

setup_kubelet_and_kubeadm() {
    install_cni_plugins "amd64" "v1.3.0"
    create_download_dir
    install_crictl
    install_kubeadm_kubelet_as_systemd_service
}

# ```
# # kubeadm-config.yaml
# kind: ClusterConfiguration
# apiVersion: kubeadm.k8s.io/v1beta4
# kubernetesVersion: v1.21.0
# ---
# kind: KubeletConfiguration
# apiVersion: kubelet.config.k8s.io/v1beta1
# cgroupDriver: systemd
# ```


setup_kubeconfig() {
    mkdir -p $HOME/.kube
    sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
    sudo chown $(id -u):$(id -g) $HOME/.kube/config
}

kubeadm_init() {
    kubeadm init
}


install_cilium_cli() {
    CILIUM_CLI_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/cilium-cli/main/stable.txt)
    CLI_ARCH=amd64
    if [ "$(uname -m)" = "aarch64" ]; then CLI_ARCH=arm64; fi
    curl -L --fail --remote-name-all https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}/cilium-linux-${CLI_ARCH}.tar.gz{,.sha256sum}
    sha256sum --check cilium-linux-${CLI_ARCH}.tar.gz.sha256sum
    sudo tar xzvfC cilium-linux-${CLI_ARCH}.tar.gz /usr/local/bin
    rm cilium-linux-${CLI_ARCH}.tar.gz{,.sha256sum}
}

install_cilium() {
    cilium install --version 1.18.2
}

setup_cilium() {
    install_cilium_cli
    install_cilium
}

setup_cni() {
    # https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/create-cluster-kubeadm/#pod-network
    setup_cilium
}

untaint_control_plane() {
    kubectl taint nodes --all node-role.kubernetes.io/control-plane-
}

# kubeadm bootstrap
# https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/

disable_swap

setup_cilium

setup_kubelet_and_kubeadm

kubeadm_init
setup_kubeconfig
setup_cilium

# TODO if 1 node, then run
untaint_control_plane

# TODO readme note https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/#installing-kubeadm-kubelet-and-kubectl