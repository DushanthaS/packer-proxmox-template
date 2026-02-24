# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Repo Does

Automates the creation of Debian VM templates for Proxmox VE using Packer. The workflow is:
1. Packer boots a Debian ISO using the `preseed.cfg` for unattended installation
2. Shell provisioners configure the system (packages, sysctl, SSH hardening, DNS)
3. `cloud.cfg` is uploaded as a template file — it uses HCL `templatefile()` to inject `ssh_authorized_keys` at build time
4. The VM is converted into a Proxmox template, ready for cloud-init-based cloning

## Build Commands

```sh
# With an explicit var file
packer build -var-file variables.pkrvars.hcl .

# With auto-loaded var file (rename example file first)
cp example-variables.pkrvars.hcl variables.auto.pkrvars.hcl
packer build .

# Initialize required plugins (run once)
packer init .

# Validate config without building
packer validate -var-file variables.pkrvars.hcl .
```

## Variable File Setup

Copy `example-variables.pkrvars.hcl` to `variables.pkrvars.hcl` (gitignored) and fill in:
- `proxmox_host` — Proxmox IP and port (e.g. `10.10.0.10:8006`)
- `proxmox_node` — Proxmox node name
- `proxmox_api_user` — API token user in format `root@pam!<token_id>`
- `proxmox_api_password` — API token secret
- `iso_file` — Path to Debian ISO on Proxmox storage (e.g. `local:iso/debian-13.2.0-amd64-netinst.iso`)
- `id` — VM ID for the template
- `http_ip` — IP of the machine running Packer (serves `preseed.cfg` over HTTP during install)
- `ssh_authorized_keys` — Your SSH public key(s); injected into `cloud.cfg` via `templatefile()`

## Architecture

### File Roles

| File | Purpose |
|------|---------|
| `debian.pkr.hcl` | Main Packer config: source block (VM hardware, network, boot), build block (shell provisioners + file provisioner) |
| `preseed.cfg` | Debian Installer automation — served over HTTP by Packer during boot; sets locale, partitioning (LVM), DNS, root password (`packer`), and enables SSH for root |
| `cloud.cfg` | Cloud-init configuration uploaded to the template; uses HCL template syntax (`%{ for key in ... }`) for SSH key injection; creates an `ansible` user with passwordless sudo |

### Boot & Provisioning Flow

1. Packer starts an HTTP server serving the repo root, boot command loads `preseed.cfg` from it
2. Debian installer runs unattended; root password is set to `packer` temporarily
3. Packer SSH connects as root (password `packer`) to run provisioners
4. Shell provisioner 1: installs packages (`qemu-guest-agent`, `ca-certificates`, `sudo`, `vim`, `chrony`, etc.), enables services
5. Shell provisioner 2: cloud-init hygiene, sysctl tuning (swappiness, inotify), container/Docker kernel module prep, DNS config (custom DNS `10.0.99.10/10.0.99.11`), IPv6 disable
6. Shell provisioner 3: SSH hardening (drops `PasswordAuthentication`, `PermitRootLogin`)
7. File provisioner: renders `cloud.cfg` with `templatefile()` and uploads to `/etc/cloud/cloud.cfg`
8. VM is converted to template; cloud-init will set root password to random on first clone boot

### Storage Defaults

- Boot disk: `vmdata` storage pool, SCSI, `raw` format, 20G
- Cloud-init drive: `local-zfs` storage pool
- Network: `vmbr0` bridge, VirtIO, firewall enabled

### DNS Assumptions

The config hardcodes internal DNS servers (`10.0.99.10`, `10.0.99.11`) in multiple places: `preseed.cfg` early command, `dhclient.conf`, and `systemd-resolved` drop-in. Update these if deploying in a different network environment.
