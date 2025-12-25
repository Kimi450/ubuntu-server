#!/bin/bash
set -e

FORMAT='+%F %T.%3NZ'
log() {
    echo [$(date --utc "${FORMAT}")] $@
}

err() {
    echo [$(date --utc "${FORMAT}")] ERROR: $@
    exit 1
}

ARCH=$(dpkg --print-architecture)
log "Env variable set: ARCH=${ARCH}" 

print_usage() {
  cat <<EOF
Usage: $0 [-t <controlplane|worker>] [-c <int>] [-hpus <string>]
    -v              Enable verbose logging
    -t  <string>    Type of node <controlplane|worker>
    -c  <int>       Count of nodes. Use 0 to run 'kubeadm reset' on the node
    -h  <string>    Hostname for the control plane node
    -p  <string>    Port for the control plane node
    -u  <string>    Username for the control plane node
    -s  <string>    Password for the control plane node

EOF
}

# defaults
type="controlplane"
count=1
host=
port=22
username=
password=

while getopts 'vt:c:h:p:u:s:' flag; do
  case "${flag}" in
    v) set -x ;;
    t) type="${OPTARG}" ;;
    c) count="${OPTARG}" ;;
    h) host="${OPTARG}" ;;
    p) port="${OPTARG}" ;;
    u) username="${OPTARG}" ;;
    s) password="${OPTARG}" ;;
    *) print_usage
       exit 1 ;;
  esac
done

if [[ "${type}" != "worker" ]] && [[ "${type}" != "controlplane" ]]; then
    print_usage
    err "incorrect type passed: ${type}" >&2
    exit 1
fi

if [[ "${type}" == "worker" ]]; then
    if [ -z "$host" ] || [ -z "$username" ] || [ -z "$password" ]; then
        print_usage
        echo 'initialising a worker node requires all of these must be present -h, -u, -s' >&2
        echo "  passed -h=${host}, -u=${username}, -s=${password}" >&2
        exit 1
    fi
fi

if [[ ${count} -ne 0 ]] && [[ ${count} -ne 1 ]]; then
    print_usage
    err "incorrect count passed: ${count} must be 0 or 1. More than 1 worker or control plane node is not supported" >&2
    exit 1
fi

#######################################
# Disable swapfile on the machine
# Arguments:
#   None
# Returns:
#   None
#######################################
disable_swap() {
    log "disabling swap"

    swapoff -a
    sed -i '/ swap / s/^/#/' /etc/fstab
    sed -i '/swap/ s/^/#/' /etc/fstab
}

#######################################
# Installs the latest version of yq
# Arguments:
#   None
# Returns:
#   None
#######################################
install_yq() {
    log "installing yq"

    # https://github.com/mikefarah/yq
    wget https://github.com/mikefarah/yq/releases/latest/download/yq_linux_${ARCH} -O /usr/local/bin/yq &&\
    chmod +x /usr/local/bin/yq
}

# ============= Setup Container Runtimes ===================

#######################################
# Downloads and installs the containerd binaries
# Arguments:
#   None
# Returns:
#   None
#######################################
install_containerd() {
    log "installing containerd"

    # TODO configurable
    containerd_url=${CONTAINERD_VERSION:?}

    tmp_dir=$(mktemp -d)
    wget -O ${tmp_dir}/containerd.tar.gz ${containerd_url}
    tar -xvzf ${tmp_dir}/containerd.tar.gz -C /usr/local
}

#######################################
# Sets up the systemd unit file for conatinerd and enables it
# Arguments:
#   None
# Returns:
#   None
#######################################
setup_containerd_systemd_unit() {
    log "setting up containerd systemd unit"

    # download systemd file
    wget -O /etc/systemd/system/containerd.service  https://raw.githubusercontent.com/containerd/containerd/main/containerd.service
    systemctl daemon-reload
    systemctl enable --now containerd
}

#######################################
# installs runc
# Arguments:
#   None
# Returns:
#   None
#######################################
install_runc() {
    log "installing runc"

    # TODO configurable
    wget -O ${tmp_dir}/runc https://github.com/opencontainers/runc/releases/download/v1.3.2/runc.${ARCH}
    install -m 755 ${tmp_dir}/runc /usr/local/sbin/runc
}

#######################################
# Downloads and installs the CNI plugins
# Arguments:
#   Machine architecture
#   CNI Plugins version to download
# Returns:
#   None
#######################################
install_cni_plugins() {
    log "installing cni plugins"

    local ARCH=$1
    local CNI_PLUGINS_VERSION=$2
    local DEST="/opt/cni/bin"
    mkdir -p "$DEST"
    curl -L "https://github.com/containernetworking/plugins/releases/download/${CNI_PLUGINS_VERSION}/cni-plugins-linux-${ARCH}-${CNI_PLUGINS_VERSION}.tgz" | tar -C "$DEST" -xz
}

#######################################
# Generates a default containerd config and updates it
# restarts containerd for it to reflect the changes
# Arguments:
#   None
# Returns:
#   None
#######################################
build_containerd_config() {
    log "building containerd config"

    # Configuring the systemd cgroup driver
    # generate default toml
    mkdir -p /etc/containerd
    containerd config default > /etc/containerd/config.toml
   
    sed -i "/SystemdCgroup/d" /etc/containerd/config.toml
    sed -i "/plugins.'io.containerd.cri.v1.runtime'.containerd.runtimes.runc.options/a SystemdCgroup = true" /etc/containerd/config.toml
    systemctl restart containerd
}

#######################################
# Setup containerd
# Arguments:
#   None
# Returns:
#   None
#######################################
setup_containerd() {
    log "setting up containerd"
    # setup containerd
    # https://kubernetes.io/docs/setup/production-environment/container-runtimes/
    # https://github.com/containerd/containerd/blob/main/docs/getting-started.md
    setup_containerd_systemd_unit
    install_runc
    install_cni_plugins "${ARCH}" "v1.8.0"
    build_containerd_config
}

#######################################
# Set up networking presequities
# Like setting up IPv4 forwarding
# Arguments:
#   None
# Returns:
#   None
#######################################
network_prerequisites() {
    log "setting up networking prerequisites"

    # sysctl params required by setup, params persist across reboots
    cat <<EOF | tee /etc/sysctl.d/k8s.conf
net.ipv4.ip_forward = 1
EOF

    # Apply sysctl params without reboot
    sysctl --system || echo oops

    sysctl net.ipv4.ip_forward
}

#######################################
# Setup container runtime interface
# Arguments:
#   None
# Returns:
#   None
#######################################
setup_cri() {
    log "installing container runtime"

    network_prerequisites
    install_containerd
    setup_containerd
}

# ============= Setup tools ===================


#######################################
# Installs kubectl
# Arguments:
#   None
# Returns:
#   None
#######################################
install_kubectl() {
    log "installing kubectl"

    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/${ARCH}/kubectl"
    chmod +x kubectl
    mkdir -p ~/.local/bin
    mv ./kubectl /usr/local/bin/kubectl || true
}


#######################################
# Installs crictl for CRI compliant rooling for CRI backend
# Arguments:
#   None
# Returns:
#   None
#######################################
install_crictl() {
    log "installing crictl"
    
    DOWNLOAD_DIR="/usr/local/bin"
    local crictl_version=${CRICTL_VERSION:?}
    curl -L "https://github.com/kubernetes-sigs/cri-tools/releases/download/${crictl_version}/crictl-${crictl_version}-linux-${ARCH}.tar.gz" | tar -C $DOWNLOAD_DIR -xz
}

# ============= Setup kubeadm and kubelet ===================

#######################################
# Installs kubeadm and kubelet as systemd services
# Arguments:
#   None
# Returns:
#   None
#######################################
install_kubeadm_kubelet_as_systemd_service() {
    log "installing kubeadm and kubelet as systemd services"

    DOWNLOAD_DIR="/usr/local/bin"
    mkdir -p "$DOWNLOAD_DIR"

    log "installing kubeadm and kubelet"
    cd $DOWNLOAD_DIR
    
    kubernetes_version=${KUBERNETES_VERSION:?}
    curl -L --remote-name-all https://dl.k8s.io/release/${kubernetes_version}/bin/linux/${ARCH}/{kubeadm,kubelet}
    chmod +x {kubeadm,kubelet}

    log "setting up kubeadm and kubelet systemd service"
    local kubernetes_release_version=${KUBERNETES_RELEASE_VERSION:?}
    curl -sSL "https://raw.githubusercontent.com/kubernetes/release/${kubernetes_release_version}/cmd/krel/templates/latest/kubelet/kubelet.service" | sed "s:/usr/bin:${DOWNLOAD_DIR}:g" | tee /usr/lib/systemd/system/kubelet.service
    mkdir -p /usr/lib/systemd/system/kubelet.service.d
    curl -sSL "https://raw.githubusercontent.com/kubernetes/release/${kubernetes_release_version}/cmd/krel/templates/latest/kubeadm/10-kubeadm.conf" | sed "s:/usr/bin:${DOWNLOAD_DIR}:g" | tee /usr/lib/systemd/system/kubelet.service.d/10-kubeadm.conf

    systemctl enable --now kubelet
}

#######################################
# Setup kubelet and kubeadm
# Arguments:
#   None
# Returns:
#   None
#######################################
setup_kubelet_and_kubeadm() {
    log "setting up kubeadm and kubelet"
    install_cni_plugins "${ARCH}" "v1.3.0"
    install_crictl
    install_kubeadm_kubelet_as_systemd_service
}

#######################################
# Setup kubeconfig for consumption
# Arguments:
#   None
# Returns:
#   None
#######################################
setup_kubeconfig() {
    log "setup kubeconfig for anyone to access"

    mkdir -p /root/.kube
    cp -f -i /etc/kubernetes/admin.conf /root/.kube/config
    chown $(id -u):$(id -g) /root/.kube/config

    while read username; do
        mkdir -p /home/$username/.kube
        cp -f -i /etc/kubernetes/admin.conf /home/$username/.kube/config
        chmod 755 /home/$username/.kube/config
    done<<<$(ls /home)
}

# ==================== Setup Container networking Interface ========================

#######################################
# Install cillium CLI tool
# Arguments:
#   None
# Returns:
#   None
#######################################
install_cilium_cli() {
    log "installing cilliumcli"

    CILIUM_CLI_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/cilium-cli/main/stable.txt)
    if [ "$(uname -m)" = "aarch64" ]; then ARCH=arm64; fi
    curl -L --fail --remote-name-all https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}/cilium-linux-${ARCH}.tar.gz{,.sha256sum}
    sha256sum --check cilium-linux-${ARCH}.tar.gz.sha256sum
    tar xzvfC cilium-linux-${ARCH}.tar.gz /usr/local/bin
    rm cilium-linux-${ARCH}.tar.gz{,.sha256sum}
}

#######################################
# Install cillium
# Arguments:
#   None
# Returns:
#   None
#######################################
install_cilium() {
    log "installing cillium"
    cilium install --version 1.18.2
}

#######################################
# Setup cillium
# Arguments:
#   None
# Returns:
#   None
#######################################
setup_cilium() {
    log "setting up cillium"
    install_cilium_cli
    install_cilium
}

#######################################
# Setup cillium
# Arguments:
#   None
# Returns:
#   None
#######################################
setup_cni() {
    log "setting up container networking interface"
    # https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/create-cluster-kubeadm/#pod-network
    setup_cilium
}

# ====================== Miscelllaneous =======================

#######################################
# Remove taint from control plane node
# Arguments:
#   None
# Returns:
#   None
#######################################
untaint_control_plane() {
    log "removing taint from control plane node"
    local hostname=$(hostname)
    kubectl taint nodes $(hostname) node-role.kubernetes.io/control-plane-
}

# ==================== Setup kubeadm commands ========================

#######################################
# Kubeadm initialise control plane node
# Arguments:
#   None
# Returns:
#   None
#######################################
kubeadm_init() {
    log "running kubeadm init on node"
    kubeadm init
}

#######################################
# Kubeadm setup control plane node
# Arguments:
#   None
# Returns:
#   None
#######################################
kubeadm_setup_cp() {
    log "setting up control plane node"
    kubeadm_init
    install_kubectl
    setup_kubeconfig
    setup_cilium

    untaint_control_plane
}

#######################################
# Kubeadm fetch join command
# Arguments:
#   Control Plane Node IP
#   Control Plane Node username
#   Control Plane Node password
# Returns:
#   The join command to run on a worker node
#######################################
kubeadm_cp_get_join_command() {
    local cp_node_ip=${1}
    local cp_node_username=${2}
    local cp_node_password=${3}

    # https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/adding-linux-nodes/
    # expires after 24hr
    echo $(sshpass -p ${cp_node_password} ssh -o stricthostkeychecking=no ${cp_node_username}@${cp_node_ip} kubeadm token create --print-join-command)
}

#######################################
# Kubeadm join a worker node
# Arguments:
#   None
# Returns:
#   None
#######################################
kubeadm_worker_join() {
    local cp_node_ip=${1}
    local cp_node_username=${2}
    local cp_node_password=${3}

    log "running kubeadm join on node"
    
    cmd="$(kubeadm_cp_get_join_command ${cp_node_ip} ${cp_node_username} ${cp_node_password})"
    eval ${cmd}

    log "add taint back to control plane node"
    local remote_hostname=$(sshpass -p ${cp_node_password} ssh -o stricthostkeychecking=no ${cp_node_username}@${cp_node_ip} hostname)
    sshpass -p ${cp_node_password} ssh -o stricthostkeychecking=no ${cp_node_username}@${cp_node_ip} kubectl taint nodes ${remote_hostname} node-role.kubernetes.io/control-plane:NoSchedule --overwrite
}

#######################################
# Removes the worker node from apiserver on control plane
# Arguments:
#   Control Plane Node IP
#   Control Plane Node username
#   Control Plane Node password
# Returns:
#   None
#######################################
remove_node() {
    log "removing node"

    local cp_node_ip=${1}
    local cp_node_username=${2}
    local cp_node_password=${3}
    local host=$(hostname)

    sshpass -p ${cp_node_password} ssh -o stricthostkeychecking=no ${cp_node_username}@${cp_node_ip} kubectl delete node --ignore-not-found ${host}

    local remote_hostname=$(sshpass -p ${cp_node_password} ssh -o stricthostkeychecking=no ${cp_node_username}@${cp_node_ip} hostname)
    sshpass -p ${cp_node_password} ssh -o stricthostkeychecking=no ${cp_node_username}@${cp_node_ip} kubectl taint nodes ${remote_hostname} node-role.kubernetes.io/control-plane-
}

#######################################
# Runs kubeadm reset, deletes the CNI config and other config
# Arguments:
#   None
# Returns:
#   None
#######################################
kubeadm_reset() {
    log "running kubeadm reset"
    # https://kubernetes.io/docs/reference/setup-tools/kubeadm/kubeadm-reset/
    kubeadm reset -f

    rm -rf /etc/cni/net.d
    rm -rf /root/.kube

    while read line; do
        rm -rf $line
    done<<<$(find /home -name ".kube")
}

# ========================= main ======================

# kubeadm bootstrap
# https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/
# TODO readme note https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/#installing-kubeadm-kubelet-and-kubectl

install_yq

if [[ ${count} -ne 0 ]]; then
    disable_swap

    setup_cri

    setup_kubelet_and_kubeadm
fi

log "manipulating nodes"

if [[ ${type} == "controlplane" ]]; then
    if [[ ${count} -eq 0 ]]; then
        log "removing control plane node"
        kubeadm_reset
    elif [[ ${count} -eq 1 ]]; then
        log "setting up control plane node"
        kubeadm_setup_cp
    else
        print_usage
        err "unexpected count: $count"
    fi
elif [[ ${type} == "worker" ]]; then
    if [[ ${count} -eq 0 ]]; then
        log "removing worker node"
        kubeadm_reset
        remove_node ${host} ${username} ${password}
    elif [[ ${count} -eq 1 ]]; then
        log "setting up worker node"
        kubeadm_worker_join ${host} ${username} ${password}
    else
        print_usage
        err "unexpected count: $count"
    fi
else
    print_usage
    err "unknown type: $type"
fi

log "done!"