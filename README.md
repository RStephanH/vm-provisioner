# VM Provisioner

Automated provisioning of Ubuntu virtual machines using **KVM/QEMU**, **libvirt**, **cloud-init** and **QCOW2** backing images.

The goal of this project is to make the creation of fresh Linux VMs reproducible, configurable and fast, while keeping a single Ubuntu cloud image shared between multiple virtual machines.

## Features

- Ubuntu 24.04 LTS cloud image
- KVM/QEMU virtualization
- libvirt VM management
- Automated VM creation with `virt-install`
- Cloud-init based configuration
- SSH key authentication
- No password-based SSH authentication
- QCOW2 backing images to avoid duplicating the base image
- Configurable:
  - VM name
  - RAM
  - vCPUs
  - disk size
  - storage location
  - network
  - username
  - provisioning profile
- Reusable Ubuntu provisioning profiles
- Docker development environment
- OWASP Juice Shop security laboratory

---

## Architecture

The project uses an Ubuntu cloud image as a common base for multiple VMs.

```text
                    Ubuntu Cloud Image
                 noble-server-cloudimg-amd64.img
                              │
                 ┌────────────┴────────────┐
                 │                         │
                 ▼                         ▼
          ubuntu-fresh                 docker-dev
          disk.qcow2                   disk.qcow2
                 │                         │
                 ▼                         ▼
             cloud-init                cloud-init
                 │                         │
                 ▼                         ▼
             Ubuntu VM                 Ubuntu VM
```

Each VM gets its own QCOW2 disk while sharing the same Ubuntu cloud image.

This avoids maintaining a complete independent base image for every VM.

---

## Repository Structure

```text
vm-provisioner/
├── README.md
├── LICENSE
├── .gitignore
│
├── scripts/
│   └── ubuntu/
│       └── create-vm.sh
│
└── profiles/
    └── ubuntu/
        ├── minimal.yaml
        ├── docker.yaml
        └── juice-shop.yaml
```

The provisioning script is responsible for VM creation, while profiles define the software and configuration installed inside the VM.

---

# Requirements

The host machine must have:

- Linux
- KVM/QEMU
- libvirt
- `virt-install`
- `virsh`
- `qemu-img`
- `cloud-localds`
- `wget`

For Arch-based systems:

```bash
sudo pacman -S qemu-desktop libvirt virt-install cloud-image-utils wget
```

Enable libvirt:

```bash
sudo systemctl enable --now libvirtd
```

Verify virtualization support:

```bash
ls /dev/kvm
```

Expected:

```text
/dev/kvm
```

Verify the required commands:

```bash
command -v wget
command -v cloud-localds
command -v qemu-img
command -v virt-install
command -v virsh
```

---

# Quick Start

Clone the repository:

```bash
git clone <repository-url>
cd vm-provisioner
```

Create a default Ubuntu VM:

```bash
./scripts/ubuntu/create-vm.sh
```

The default configuration is:

```text
VM name:       ubuntu-fresh
RAM:           2048 MB
vCPUs:         1
Disk:          20G
User:          ubuntu
Network:       default
Storage:       /mnt/vm-storage
Profile:       minimal
```

The script automatically downloads the Ubuntu cloud image if it is not already present.

---

# Storage Layout

By default, VM data is stored under:

```text
/mnt/vm-storage/
```

Example:

```text
/mnt/vm-storage/
├── images/
│   └── noble-server-cloudimg-amd64.img
│
└── vms/
    ├── ubuntu-fresh/
    │   ├── disk.qcow2
    │   ├── seed.iso
    │   └── user-data.yaml
    │
    ├── docker-dev/
    │   ├── disk.qcow2
    │   ├── seed.iso
    │   └── user-data.yaml
    │
    └── juice-shop/
        ├── disk.qcow2
        ├── seed.iso
        └── user-data.yaml
```

The Ubuntu cloud image is downloaded once and reused as the backing image for new VMs.

---

# Command-Line Options

The provisioning script supports:

```text
--name NAME
--ram MB
--vcpus COUNT
--disk SIZE
--username USER
--storage PATH
--network NAME
--profile NAME
-h, --help
```

## Examples

Create a default VM:

```bash
./scripts/ubuntu/create-vm.sh
```

Create a VM named `dev-box`:

```bash
./scripts/ubuntu/create-vm.sh \
  --name dev-box
```

Create a larger VM:

```bash
./scripts/ubuntu/create-vm.sh \
  --name dev-box \
  --ram 4096 \
  --vcpus 2 \
  --disk 40G
```

Create a VM with a custom username:

```bash
./scripts/ubuntu/create-vm.sh \
  --name dev-box \
  --username dev
```

Use a different storage location:

```bash
./scripts/ubuntu/create-vm.sh \
  --name dev-box \
  --storage /path/to/storage
```

---

# SSH Authentication

The VMs use SSH public-key authentication.

By default, the script looks for:

```text
~/.ssh/id_ed25519.pub
```

If the key does not exist, the script can offer to generate one.

The public key is injected into the VM through cloud-init.

Password-based SSH authentication is disabled:

```yaml
ssh_pwauth: false
```

After the VM has started, connect with:

```bash
ssh ubuntu@<VM_IP>
```

For a custom username:

```bash
ssh <username>@<VM_IP>
```

---

# Cloud-Init

Cloud-init performs the initial configuration of the VM.

The generated configuration contains:

- the VM user
- sudo permissions
- the SSH public key
- disabled password authentication
- the selected provisioning profile

A simplified configuration looks like:

```yaml
#cloud-config

users:
  - name: ubuntu
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    ssh_authorized_keys:
      - <SSH_PUBLIC_KEY>

ssh_pwauth: false
```

The generated file is stored at:

```text
/mnt/vm-storage/vms/<VM_NAME>/user-data.yaml
```

It is converted into a NoCloud seed ISO using:

```bash
cloud-localds
```

---

# Provisioning Profiles

Profiles allow the same VM creation mechanism to produce different environments.

Available profiles:

```text
minimal
docker
juice-shop
```

---

## Minimal Profile

The `minimal` profile provides a basic Ubuntu environment with the QEMU guest agent.

It installs:

```text
qemu-guest-agent
```

and enables the service.

Use it as a clean starting point for infrastructure, development or experimentation.

Example:

```bash
./scripts/ubuntu/create-vm.sh \
  --name ubuntu-minimal \
  --profile minimal
```

---

# Docker Profile

The `docker` profile installs Docker Engine and Docker Compose.

It uses Docker's official Ubuntu repository and installs:

```text
docker-ce
docker-ce-cli
containerd.io
docker-buildx-plugin
docker-compose-plugin
```

The Docker service is enabled and started automatically.

The VM user is also added to the `docker` group.

After connecting to the VM, reconnect your SSH session before using Docker without `sudo`.

Check Docker:

```bash
docker version
```

Check Docker Compose:

```bash
docker compose version
```

Example:

```bash
./scripts/ubuntu/create-vm.sh \
  --name docker-dev \
  --profile docker
```

---

# OWASP Juice Shop Profile

The `juice-shop` profile creates a ready-to-use web security laboratory based on **OWASP Juice Shop**.

The profile installs Docker and runs Juice Shop as a container.

Architecture:

```text
Ubuntu VM
   │
   └── Docker
        │
        └── OWASP Juice Shop
             │
             └── TCP 3000
```

The Juice Shop container is configured to:

- use the official `bkimminich/juice-shop` image
- run in detached mode
- restart automatically
- expose port `3000`

Example:

```bash
./scripts/ubuntu/create-vm.sh \
  --name juice-shop \
  --profile juice-shop
```

After the VM starts, find its IP:

```bash
sudo virsh domifaddr juice-shop
```

Then access Juice Shop:

```text
http://<VM_IP>:3000
```

Check the container:

```bash
docker ps
```

Check its logs:

```bash
docker logs juice-shop
```

The Juice Shop profile is intended for **authorized local security testing and learning**.

---

# Profile Relationship

The current profiles are designed around different VM purposes:

```text
                    Ubuntu VM
                        │
          ┌─────────────┼─────────────┐
          │             │             │
          ▼             ▼             ▼
       minimal        docker      juice-shop
          │             │             │
          ▼             ▼             ▼
       Base VM     Docker host    Security Lab
```

The Juice Shop environment relies on Docker to run the application.

The long-term goal is to make these profiles explicitly composable so that dependencies can be represented directly:

```text
minimal
   │
   └── docker
         │
         └── juice-shop
```

This avoids duplicating Docker provisioning logic between profiles.

---

# QCOW2 Backing Images

The project uses QCOW2 backing files rather than copying the complete Ubuntu image for every VM.

Conceptually:

```text
                 Ubuntu Cloud Image
                        │
          ┌─────────────┴─────────────┐
          │                           │
          ▼                           ▼
      VM disk #1                  VM disk #2
      disk.qcow2                  disk.qcow2
          │                           │
          ▼                           ▼
      Ubuntu VM                   Ubuntu VM
```

A VM disk is created with:

```bash
qemu-img create \
  -f qcow2 \
  -F qcow2 \
  -b "$IMAGE_PATH" \
  "$VM_DISK" \
  "$DISK_SIZE"
```

This allows multiple VMs to share the same base image while keeping their writable state separate.

---

# Managing VMs

List all VMs:

```bash
sudo virsh list --all
```

Start a VM:

```bash
sudo virsh start ubuntu-fresh
```

Stop a VM:

```bash
sudo virsh shutdown ubuntu-fresh
```

Force stop a VM if necessary:

```bash
sudo virsh destroy ubuntu-fresh
```

Remove a VM definition:

```bash
sudo virsh undefine ubuntu-fresh
```

---

# Finding the VM IP

Use:

```bash
sudo virsh domifaddr ubuntu-fresh
```

Or:

```bash
sudo virsh net-dhcp-leases default
```

Then connect through SSH:

```bash
ssh ubuntu@<VM_IP>
```

---

# Inspecting a VM

Display VM information:

```bash
sudo virsh dominfo ubuntu-fresh
```

Display network interfaces:

```bash
sudo virsh domiflist ubuntu-fresh
```

Open the VM console:

```bash
sudo virsh console ubuntu-fresh
```

Exit the console with:

```text
Ctrl + ]
```

---

# Recreating a VM

Each VM has its own directory:

```text
/mnt/vm-storage/vms/<VM_NAME>/
```

To recreate a VM:

```bash
sudo virsh destroy <VM_NAME>
sudo virsh undefine <VM_NAME>
```

Remove its VM storage:

```bash
rm -rf /mnt/vm-storage/vms/<VM_NAME>
```

Then provision it again:

```bash
./scripts/ubuntu/create-vm.sh \
  --name <VM_NAME>
```

The shared Ubuntu cloud image remains untouched.

---

# Security Considerations

This project is primarily intended for local development, infrastructure experimentation and security laboratories.

## SSH

The provisioning process:

- uses SSH public-key authentication
- disables password-based SSH authentication
- creates a sudo-enabled VM user
- never copies the SSH private key into the VM

## Docker

Membership in the `docker` group provides highly privileged access inside the VM.

Only trusted users should be added to this group.

## OWASP Juice Shop

OWASP Juice Shop is intentionally vulnerable and is designed for security education and authorized testing.

Keep the Juice Shop VM on a controlled network and do not expose the vulnerable application beyond the environment where it is intended to be used.

---

# Design Goals

## Reproducibility

The same provisioning command should create the same type of environment.

## Minimal Manual Configuration

A newly created VM should require as little manual setup as possible.

## Reusability

The Ubuntu cloud image is downloaded once and reused by multiple VMs.

## Separation of Concerns

```text
VM Provisioning
      │
      ├── Virtualization
      ├── Storage
      ├── Networking
      └── Cloud-init
             │
             └── Profiles
                    │
                    ├── Minimal
                    ├── Docker
                    └── Juice Shop
```

The main script handles VM creation, while profiles describe the environment installed inside the VM.

## Extensibility

New environments should be addable without rewriting the core VM provisioning logic.

---

# Roadmap

- [x] Ubuntu 24.04 cloud image provisioning
- [x] KVM/QEMU support
- [x] libvirt integration
- [x] QCOW2 backing images
- [x] Cloud-init configuration
- [x] SSH key authentication
- [x] Configurable VM resources
- [x] Minimal Ubuntu profile
- [x] Docker profile
- [x] OWASP Juice Shop profile
- [ ] Composable profile architecture
- [ ] Profile dependency handling
- [ ] VM deletion helper
- [ ] VM listing/status helper
- [ ] Automated IP discovery
- [ ] Additional development profiles
- [ ] Security lab profiles
- [ ] Profile validation
- [ ] Automated provisioning tests

---

# Example Environments

| Profile      | Purpose                 |
| ------------ | ------------------------ |
| `minimal`    | Clean Ubuntu VM         |
| `docker`     | Container development   |
| `juice-shop` | Web security laboratory |

Future profiles could include:

| Profile        | Purpose                         |
| -------------- | -------------------------------- |
| `development`  | General development environment |
| `security-lab` | Security testing environment    |
| `monitoring`   | Monitoring and observability    |
| `database`     | Database experimentation        |

---

# Why Cloud Images?

A traditional VM workflow usually looks like:

```text
Ubuntu ISO
    │
    ▼
Manual installation
    │
    ▼
System configuration
    │
    ▼
Package installation
    │
    ▼
Ready VM
```

This project uses an Ubuntu cloud image instead:

```text
Ubuntu Cloud Image
       │
       ▼
   cloud-init
       │
       ▼
    profile
       │
       ▼
   Ready VM
```

This makes VM provisioning faster, reproducible and easier to automate.

---

# License

This project is licensed under the terms of the license included in this repository.

---

# Disclaimer

This project is intended for **development, infrastructure experimentation and authorized security laboratories**.

When using security-oriented profiles such as OWASP Juice Shop, only test systems and applications that you own or have explicit permission to test.
