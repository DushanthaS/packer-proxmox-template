proxmox_host         = "10.10.0.10:8006"
proxmox_node         = "pve-01"
proxmox_api_user     = "root@pam!<token_id>"
proxmox_api_password = "my secret password"

iso_file             = "local:iso/debian-13.2.0-amd64-netinst.iso"

id = 999

ssh_authorized_keys = "ssh-ed25519 AAAA... user@host1"
http_ip              = <build host ip>