#!/usr/bin/env bash

set -euo pipefail

# ============================================================
# Configuration
# ============================================================

STORAGE_DIR="/mnt/vm-storage"
VM_NAME="ubuntu-fresh"
VM_USER="ubuntu"

RAM_MB=2048
VCPUS=1
DISK_SIZE="20G"
NETWORK="default"
PROFILE="minimal"

IMAGE_NAME="noble-server-cloudimg-amd64.img"

# ============================================================
# Paths
# ============================================================

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"

PROFILE_DIR="$PROJECT_ROOT/profiles/ubuntu"

IMAGE_DIR="$STORAGE_DIR/images"
VM_DIR="$STORAGE_DIR/vms/$VM_NAME"

IMAGE_PATH="$IMAGE_DIR/$IMAGE_NAME"
VM_DISK="$VM_DIR/disk.qcow2"
SEED_ISO="$VM_DIR/seed.iso"
USER_DATA="$VM_DIR/user-data.yaml"

# ============================================================
# Help
# ============================================================

usage() {
    cat <<EOF
Usage:
    $0 [options]

Options:
    --name NAME          VM name
    --ram MB             RAM in MB
    --vcpus COUNT        Number of virtual CPUs
    --disk SIZE          Disk size (example: 20G)
    --username USER      Default VM username
    --storage PATH       VM storage directory
    --network NAME       Libvirt network
    --profile NAME       Provisioning profile
    -h, --help           Show this help

Profiles:
    minimal              Ubuntu + QEMU Guest Agent
    docker               Ubuntu + Docker
    juice-shop           Ubuntu + Docker + OWASP Juice Shop

Examples:
    $0
    $0 --name ubuntu-dev --profile minimal
    $0 --name docker-dev --profile docker
    $0 --name juice-shop --profile juice-shop
    $0 --ram 4096 --vcpus 2 --disk 30G --profile docker
    $0 --storage /mnt/vm-storage --profile docker
EOF
}

# ============================================================
# Argument parsing
# ============================================================

while [[ $# -gt 0 ]]; do
    case "$1" in
        --name)
            VM_NAME="$2"
            shift 2
            ;;

        --ram)
            RAM_MB="$2"
            shift 2
            ;;

        --vcpus)
            VCPUS="$2"
            shift 2
            ;;

        --disk)
            DISK_SIZE="$2"
            shift 2
            ;;

        --username)
            VM_USER="$2"
            shift 2
            ;;

        --storage)
            STORAGE_DIR="$2"
            shift 2
            ;;

        --network)
            NETWORK="$2"
            shift 2
            ;;

        --profile)
            PROFILE="$2"
            shift 2
            ;;

        -h|--help)
            usage
            exit 0
            ;;

        *)
            echo "Error: unknown option: $1"
            echo
            usage
            exit 1
            ;;
    esac
done

# ============================================================
# Recalculate paths after argument parsing
# ============================================================

IMAGE_DIR="$STORAGE_DIR/images"
VM_DIR="$STORAGE_DIR/vms/$VM_NAME"

IMAGE_PATH="$IMAGE_DIR/$IMAGE_NAME"
VM_DISK="$VM_DIR/disk.qcow2"
SEED_ISO="$VM_DIR/seed.iso"
USER_DATA="$VM_DIR/user-data.yaml"

# ============================================================
# Validate profile
# ============================================================

case "$PROFILE" in
    minimal)
        PROFILES=("minimal")
        ;;

    docker)
        PROFILES=("minimal" "docker")
        ;;

    juice-shop)
        PROFILES=("minimal" "docker" "juice-shop")
        ;;

    *)
        echo "Error: unknown profile: $PROFILE"
        echo
        echo "Available profiles:"
        echo "  minimal"
        echo "  docker"
        echo "  juice-shop"
        exit 1
        ;;
esac

# ============================================================
# Check dependencies
# ============================================================

check_dependencies() {
    local dependencies=(
        wget
        cloud-localds
        qemu-img
        virt-install
        virsh
    )

    for command in "${dependencies[@]}"; do
        if ! command -v "$command" &>/dev/null; then
            echo "Error: required command not found: $command"
            exit 1
        fi
    done
}

# ============================================================
# Check profile files
# ============================================================

check_profiles() {
    local profile

    for profile in "${PROFILES[@]}"; do
        local profile_file="$PROFILE_DIR/$profile/setup.sh"

        if [[ ! -f "$profile_file" ]]; then
            echo "Error: profile file not found:"
            echo "  $profile_file"
            exit 1
        fi
    done
}

# ============================================================
# Download Ubuntu cloud image
# ============================================================

download_image() {
    mkdir -p "$IMAGE_DIR"

    if [[ -f "$IMAGE_PATH" ]]; then
        echo "Ubuntu cloud image already exists:"
        echo "  $IMAGE_PATH"
        return
    fi

    echo "Downloading Ubuntu cloud image..."

    wget \
        -O "$IMAGE_PATH" \
        "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"

    echo "Ubuntu cloud image downloaded."
}

# ============================================================
# SSH key
# ============================================================

get_ssh_key() {
    local ssh_key="$HOME/.ssh/id_ed25519.pub"

    if [[ ! -f "$ssh_key" ]]; then
        echo "SSH key not found: $ssh_key"
        echo
        read -r -p "Generate an Ed25519 SSH key? [y/N] " answer

        if [[ "$answer" =~ ^[Yy]$ ]]; then
            mkdir -p "$HOME/.ssh"

            ssh-keygen \
                -t ed25519 \
                -f "$HOME/.ssh/id_ed25519"

        else
            echo "Error: an SSH public key is required."
            exit 1
        fi
    fi

    cat "$ssh_key"
}

# ============================================================
# Generate cloud-init configuration
# ============================================================

generate_cloud_init() {
    local ssh_key="$1"

    echo "Generating cloud-init configuration..."

    mkdir -p "$VM_DIR"

    cat > "$USER_DATA" <<EOF
#cloud-config

users:
  - name: $VM_USER
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    ssh_authorized_keys:
      - $ssh_key

ssh_pwauth: false

runcmd:
EOF

    for profile in "${PROFILES[@]}"; do
        local profile_file="$PROFILE_DIR/$profile/setup.sh"

        echo "  Adding profile: $profile"

        echo "  - |" >> "$USER_DATA"

        sed \
            "s/__VM_USER__/$VM_USER/g; s/^/      /" \
            "$profile_file" \
            >> "$USER_DATA"
    done

    echo "Cloud-init configuration generated:"
    echo "  $USER_DATA"
}

# ============================================================
# Create cloud-init ISO
# ============================================================

create_seed_iso() {
    echo "Creating cloud-init seed ISO..."

    cloud-localds \
        "$SEED_ISO" \
        "$USER_DATA"

    echo "Seed ISO created:"
    echo "  $SEED_ISO"
}

# ============================================================
# Create VM disk
# ============================================================

create_vm_disk() {
    if [[ -f "$VM_DISK" ]]; then
        echo "VM disk already exists:"
        echo "  $VM_DISK"
        return
    fi

    echo "Creating VM disk..."

    qemu-img create \
        -f qcow2 \
        -F qcow2 \
        -b "$IMAGE_PATH" \
        "$VM_DISK" \
        "$DISK_SIZE"

    echo "VM disk created:"
    echo "  $VM_DISK"
}

# ============================================================
# Create VM
# ============================================================

create_vm() {
    if sudo virsh dominfo "$VM_NAME" &>/dev/null; then
        echo "Error: VM '$VM_NAME' already exists."
        exit 1
    fi

    echo "Creating VM '$VM_NAME'..."

    sudo virt-install \
        --name "$VM_NAME" \
        --memory "$RAM_MB" \
        --vcpus "$VCPUS" \
        --disk "path=$VM_DISK,format=qcow2" \
        --disk "path=$SEED_ISO,device=cdrom" \
        --os-variant ubuntu24.04 \
        --network "network=$NETWORK" \
        --graphics none \
        --noautoconsole \
        --import

    echo
    echo "VM created successfully."
}

# ============================================================
# Information
# ============================================================

show_info() {
    echo
    echo "============================================================"
    echo "VM provisioning completed"
    echo "============================================================"
    echo
    echo "VM name:       $VM_NAME"
    echo "Username:      $VM_USER"
    echo "Profile:       $PROFILE"
    echo "RAM:           ${RAM_MB} MB"
    echo "vCPUs:         $VCPUS"
    echo "Disk:          $DISK_SIZE"
    echo "Network:       $NETWORK"
    echo
    echo "Storage:"
    echo "  $VM_DIR"
    echo
    echo "Find VM IP:"
    echo "  sudo virsh domifaddr $VM_NAME"
    echo
    echo "Or:"
    echo "  sudo virsh net-dhcp-leases $NETWORK"
    echo
    echo "SSH:"
    echo "  ssh $VM_USER@<VM_IP>"
    echo
}

# ============================================================
# Main
# ============================================================

main() {
    echo "Starting Ubuntu VM provisioning..."
    echo
    echo "VM:      $VM_NAME"
    echo "Profile: $PROFILE"
    echo

    check_dependencies
    check_profiles

    local ssh_key
    ssh_key="$(get_ssh_key)"

    download_image
    generate_cloud_init "$ssh_key"
    create_seed_iso
    create_vm_disk
    create_vm

    show_info
}

main "$@"
