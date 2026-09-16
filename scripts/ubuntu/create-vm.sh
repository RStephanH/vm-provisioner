#!/usr/bin/env bash

set -euo pipefail

# ============================================================
# Ubuntu VM Provisioner
# ============================================================

# ---------- Defaults ----------
STORAGE_DIR="/mnt/vm-storage"
VM_NAME="ubuntu-fresh"
VM_USER="ubuntu"
RAM_MB=2048
VCPUS=1
DISK_SIZE="20G"
NETWORK="default"

IMAGE_NAME="noble-server-cloudimg-amd64.img"

PROFILE="minimal"

# ---------- Runtime paths ----------
IMAGE_DIR=""
IMAGE_PATH=""
VM_DIR=""
VM_DISK=""
SEED_ISO=""
USER_DATA=""

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"

PROFILE_DIR="$PROJECT_ROOT/profiles/ubuntu"
PROFILE_FILE=""

# ============================================================
# Helpers
# ============================================================

usage() {
    cat <<EOF
Usage:
  $0 [options]

Options:
  --name NAME          VM name (default: $VM_NAME)
  --profile NAME       Provisioning profile (default: minimal)
  --ram MB             RAM in MB (default: $RAM_MB)
  --vcpus COUNT        Number of vCPUs (default: $VCPUS)
  --disk SIZE          Disk size (default: $DISK_SIZE)
  --username USER      VM username (default: $VM_USER)
  --storage PATH       VM storage directory (default: $STORAGE_DIR)
  --network NAME       Libvirt network (default: $NETWORK)
  -h, --help           Show this help

Example:
  $0 --name ubuntu-dev --ram 4096 --vcpus 2 --disk 30G

EOF
}

error() {
    echo "Error: $*" >&2
    exit 1
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# ============================================================
# Argument parsing
# ============================================================

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --name)
                [[ $# -ge 2 ]] || error "--name requires a value"
                VM_NAME="$2"
                shift 2
                ;;

            --profile)
                [[ $# -ge 2 ]] || error "--profile requires a value"
                PROFILE="$2"
                shift 2
                ;;

            --ram)
                [[ $# -ge 2 ]] || error "--ram requires a value"
                RAM_MB="$2"
                shift 2
                ;;

            --vcpus)
                [[ $# -ge 2 ]] || error "--vcpus requires a value"
                VCPUS="$2"
                shift 2
                ;;

            --disk)
                [[ $# -ge 2 ]] || error "--disk requires a value"
                DISK_SIZE="$2"
                shift 2
                ;;

            --username)
                [[ $# -ge 2 ]] || error "--username requires a value"
                VM_USER="$2"
                shift 2
                ;;

            --storage)
                [[ $# -ge 2 ]] || error "--storage requires a value"
                STORAGE_DIR="$2"
                shift 2
                ;;

            --network)
                [[ $# -ge 2 ]] || error "--network requires a value"
                NETWORK="$2"
                shift 2
                ;;

            -h|--help)
                usage
                exit 0
                ;;

            *)
                error "Unknown option: $1"
                ;;
        esac
    done
}

# ============================================================
# Dependency checks
# ============================================================

check_dependencies() {
    local dependencies=(
        wget
        cloud-localds
        qemu-img
        virt-install
        virsh
        sudo
    )

    echo "=== Checking dependencies ==="

    for command in "${dependencies[@]}"; do
        if command_exists "$command"; then
            echo "✓ $command"
        else
            error "$command is not installed"
        fi
    done

    if ! sudo -v; then
        error "sudo access is required to create and manage the VM"
    fi
}

# ============================================================
# Storage
# ============================================================

prepare_storage() {
    IMAGE_DIR="$STORAGE_DIR/images"
    VM_DIR="$STORAGE_DIR/vms/$VM_NAME"

    IMAGE_PATH="$IMAGE_DIR/$IMAGE_NAME"
    VM_DISK="$VM_DIR/disk.qcow2"
    SEED_ISO="$VM_DIR/seed.iso"
    USER_DATA="$VM_DIR/user-data.yaml"

    echo
    echo "=== Preparing storage ==="
    echo "Storage : $STORAGE_DIR"
    echo "VM      : $VM_NAME"
    echo "VM dir  : $VM_DIR"

    mkdir -p "$IMAGE_DIR"
    mkdir -p "$VM_DIR"
}

# ============================================================
# Ubuntu cloud image
# ============================================================

download_base_image() {
    echo
    echo "=== Ubuntu 24.04 cloud image ==="

    if [[ -f "$IMAGE_PATH" ]]; then
        echo "✓ Base image already exists:"
        echo "  $IMAGE_PATH"
        return
    fi

    echo "Downloading Ubuntu 24.04 cloud image..."

    wget \
        --show-progress \
        -O "$IMAGE_PATH" \
        "https://cloud-images.ubuntu.com/noble/current/$IMAGE_NAME"

    echo "✓ Ubuntu cloud image downloaded"
}

# ============================================================
# SSH configuration
# ============================================================

get_ssh_key() {
    local ssh_key_path="$HOME/.ssh/id_ed25519.pub"

    if [[ ! -f "$ssh_key_path" ]]; then
        echo
        echo "SSH public key not found:"
        echo "  $ssh_key_path"
        echo

        read -rp "Generate an Ed25519 SSH key now? [y/N] " answer

        case "$answer" in
            y|Y|yes|YES|Yes)
                mkdir -p "$HOME/.ssh"

                ssh-keygen \
                    -t ed25519 \
                    -f "$HOME/.ssh/id_ed25519" \
                    -N ""
                ;;

            *)
                error "SSH public key is required"
                ;;
        esac
    fi

    cat "$ssh_key_path"
}

# ============================================================
# Validate Profile
# ============================================================

validate_profile(){
  PROFILE_FILE="$PROFILE_DIR/$PROFILE.yaml"

  if [[ ! -f "$PROFILE_FILE" ]]; then
    error"Unknown profile '$PROFILE'. Expected:
    $PROFILE_DIR/$PROFILE_FILE.yaml"
  fi

  echo "✓ Profile: $PROFILE"
}

# ============================================================
# Cloud-init
# ============================================================

generate_cloud_init() {
    local ssh_key

    ssh_key="$(get_ssh_key)"

    echo
    echo "=== Generating cloud-init configuration ==="

    cat > "$USER_DATA" <<EOF
#cloud-config

users:
  - name: $VM_USER
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    ssh_authorized_keys:
      - $ssh_key

ssh_pwauth: false

EOF

    cat "$PROFILE_FILE" >> "$USER_DATA"
    
    sed -i "s/__VM_USER__/$VM_USER/g" "$USER_DATA"

    echo "✓ Created:"
    echo "  $USER_DATA"
}

# ============================================================
# NoCloud ISO
# ============================================================

create_seed_iso() {
    echo
    echo "=== Creating cloud-init seed ISO ==="

    rm -f "$SEED_ISO"

    cloud-localds \
        "$SEED_ISO" \
        "$USER_DATA"

    echo "✓ Created:"
    echo "  $SEED_ISO"
}

# ============================================================
# VM disk
# ============================================================

create_vm_disk() {
    echo
    echo "=== Creating VM disk ==="

    if [[ -f "$VM_DISK" ]]; then
        echo "✓ VM disk already exists:"
        echo "  $VM_DISK"
        return
    fi

    qemu-img create \
        -f qcow2 \
        -F qcow2 \
        -b "$IMAGE_PATH" \
        "$VM_DISK" \
        "$DISK_SIZE"

    echo "✓ Created:"
    echo "  $VM_DISK"
}

# ============================================================
# VM creation
# ============================================================

create_vm() {
    echo
    echo "=== Creating VM with libvirt ==="

    if sudo virsh dominfo "$VM_NAME" >/dev/null 2>&1; then
        error "A VM named '$VM_NAME' already exists"
    fi

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
    echo "✓ VM created successfully"
}

# ============================================================
# Information
# ============================================================

show_info() {
    echo
    echo "============================================================"
    echo " Ubuntu VM created successfully"
    echo "============================================================"
    echo
    echo "Name       : $VM_NAME"
    echo "Username   : $VM_USER"
    echo "RAM        : ${RAM_MB} MB"
    echo "vCPUs      : $VCPUS"
    echo "Disk       : $DISK_SIZE"
    echo "Network    : $NETWORK"
    echo
    echo "Storage:"
    echo "  $VM_DIR"
    echo
    echo "To find the VM IP:"
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
    parse_args "$@"

    echo "=== Ubuntu VM Provisioner ==="
    echo
    echo "VM name : $VM_NAME"
    echo "Profile : $PROFILE"
    echo "RAM     : ${RAM_MB} MB"
    echo "vCPUs   : $VCPUS"
    echo "Disk    : $DISK_SIZE"
    echo "User    : $VM_USER"
    echo "Storage : $STORAGE_DIR"
    echo "Network : $NETWORK"

    check_dependencies
    validate_profile
    prepare_storage
    download_base_image
    generate_cloud_init
    create_seed_iso
    create_vm_disk
    create_vm
    show_info
}

main "$@"
