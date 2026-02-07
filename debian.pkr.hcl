packer {
  required_plugins {
    proxmox = {
      version = ">= 1.1.3"
      source  = "github.com/hashicorp/proxmox"
    }
  }
}

variable "iso_file" {
  type = string
}

variable "id" {
  type = string
}

variable "tags" {
  type    = string
  default = ""
}

variable "cloudinit_storage_pool" {
  type    = string
  default = "local"
}

variable "cores" {
  type    = string
  default = "2"
}

variable "disk_format" {
  type    = string
  default = "raw"
}

variable "disk_size" {
  type    = string
  default = "20G"
}

variable "disk_storage_pool" {
  type    = string
  default = "local-zfs"
}

variable "cpu_type" {
  type    = string
  default = "kvm64"
}

variable "memory" {
  type    = string
  default = "2048"
}

variable "network_vlan" {
  type    = string
  default = ""
}

variable "machine_type" {
  type    = string
  default = ""
}

variable "proxmox_api_password" {
  type      = string
  sensitive = true
}

variable "proxmox_api_user" {
  type = string
}

variable "proxmox_host" {
  type = string
}

variable "proxmox_node" {
  type = string
}

variable "http_ip" {
  type = string
}

variable "ssh_authorized_keys" {
  type    = string
  default = ""
}

source "proxmox-iso" "debian" {
  proxmox_url              = "https://${var.proxmox_host}/api2/json"
  insecure_skip_tls_verify = true
  username                 = var.proxmox_api_user
  token                    = var.proxmox_api_password

  template_description = "Built from ${basename(var.iso_file)} on ${formatdate("YYYY-MM-DD hh:mm:ss ZZZ", timestamp())}"
  node                 = var.proxmox_node
  network_adapters {
    bridge   = "vmbr0"
    firewall = true
    model    = "virtio"
    vlan_tag = var.network_vlan
  }
  disks {
    disk_size    = var.disk_size
    format       = var.disk_format
    io_thread    = true
    storage_pool = var.disk_storage_pool
    type         = "scsi"
  }
  scsi_controller = "virtio-scsi-single"

  http_directory = "${path.root}/"
  boot_wait      = "10s"
  boot_command   = ["<esc><wait>auto url=http://${var.http_ip}:{{ .HTTPPort }}/preseed.cfg<enter>"]
  boot_iso {
    type = "scsi"
    iso_file = var.iso_file
    unmount = true
  }

  cloud_init              = true
  cloud_init_storage_pool = var.cloudinit_storage_pool

  vm_name  = trimsuffix(basename(var.iso_file), ".iso")
  vm_id    = var.id
  tags     = var.tags
  cpu_type = var.cpu_type
  os       = "l26"
  memory   = var.memory
  cores    = var.cores
  sockets  = "1"
  machine  = var.machine_type

  # Note: this password is needed by packer to run the file provisioner, but
  # once that is done - the password will be set to random one by cloud init.
  ssh_password = "packer"
  ssh_username = "root"
  ssh_timeout  = "25m"
}

build {
  sources = ["source.proxmox-iso.debian"]

  provisioner "shell" {
    inline = [
      "apt-get update -y",
      "apt-get install -y qemu-guest-agent ca-certificates curl gnupg lsb-release sudo vim htop rsync chrony",
      "systemctl enable qemu-guest-agent",
      "systemctl enable fstrim.timer"
    ]
  }

  provisioner "shell" {
    inline = [
      # Clean cloud-init for template hygiene
      "cloud-init clean",
      "truncate -s 0 /etc/machine-id",
      
      # Performance tuning
      "echo 'vm.swappiness=10' > /etc/sysctl.d/99-swappiness.conf",
      
      # Container-friendly settings
      "cat <<EOF > /etc/sysctl.d/99-inotify.conf",
      "fs.inotify.max_user_watches=524288",
      "fs.inotify.max_user_instances=512",
      "EOF",
      
      # Docker-ready kernel modules (don't load yet)
      "cat <<EOF > /etc/modules-load.d/containers.conf",
      "overlay",
      "br_netfilter",
      "EOF",
      
      # Container networking prep
      "cat <<EOF > /etc/sysctl.d/99-containers.conf",
      "net.bridge.bridge-nf-call-iptables=1",
      "net.bridge.bridge-nf-call-ip6tables=1",
      "net.ipv4.ip_forward=1",
      "EOF",
      
      # Configure custom DNS
      "cat <<EOF > /etc/systemd/resolved.conf.d/99-custom-dns.conf",
      "[Resolve]",
      "DNS=10.0.99.10",
      "FallbackDNS=10.0.99.11",
      "Domains=~.",
      "DNSSEC=no",
      "EOF",
      
      # Disable IPv6 (more carefully to avoid DNS issues)
      "cat <<EOF > /etc/sysctl.d/99-disable-ipv6.conf",
      "net.ipv6.conf.all.disable_ipv6=1",
      "net.ipv6.conf.default.disable_ipv6=1",
      "net.ipv6.conf.lo.disable_ipv6=0",
      "EOF",
      
      # Ensure resolv.conf points to systemd-resolved
      "ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf"
    ]
  }

  provisioner "shell" {
    inline = [
      # SSH hardening
      "mkdir -p /etc/ssh/sshd_config.d",
      "cat <<EOF > /etc/ssh/sshd_config.d/99-hardening.conf",
      "PasswordAuthentication no",
      "PermitRootLogin no",
      "ChallengeResponseAuthentication no",
      "UseDNS no",
      "EOF"
    ]
  }

  provisioner "file" {
    destination = "/etc/cloud/cloud.cfg"
    content     = templatefile("${path.root}/cloud.cfg", {
      ssh_authorized_keys = var.ssh_authorized_keys
    })
  }
}


