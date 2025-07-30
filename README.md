<p align="center">
 <a href="./README.fa.md">
 فارسی
 </a>
</p>

# Any Link Forwarder (Nginx + PHP + SSL)

A lightweight reverse proxy for link forwarding through your custom domain with HTTPS — using Nginx, PHP, and Certbot.

## 🔧 One-liner installation

```bash
bash <(curl -sSL https://raw.githubusercontent.com/ach1992/Any-Link-Forwarder/main/anyforwarder.sh) install
```

---

## 🚀 CLI Commands

After installing the script, you can manage the forwarder using the global command:

```bash
anyforwarder
```

## 🧩 CLI Command Reference

| Command | Description |
|---------|-------------|
| `anyforwarder add` | Adds a new forwarder. Prompts for domain, target panel, and listen port. Issues SSL certificate and sets up Nginx configuration. **Requires `sudo` to run.** |
| `anyforwarder list` | Lists all currently active domains (instances) managed by MarzForwarder. |
| `anyforwarder remove <domain>` | Removes the forwarder for the specified domain, including its Nginx configuration, certificate, and instance files. |
| `anyforwarder renew-cert` | Manually renews all SSL certificates via Certbot and reloads Nginx. |
| `anyforwarder uninstall` | Completely removes all domains, certificates, the CLI command, and auto-renew systemd services. Does NOT remove Nginx, PHP, or Certbot packages. |
| `anyforwarder install` | 📌 *(Used only during initial setup)* Installs dependencies, sets up auto-renew, and prompts you to add your first domain. |
| `anyforwarder status` | Displays the status of Nginx, PHP-FPM, Certbot renewal timer, and active forwarders. |

## ⚙️ Requirements

To use this Link forwarder, ensure your system meets the following requirements:

### ✅ System Compatibility

- Debian-based Linux system (recommended):
  - **Ubuntu** 20.04 / 22.04 / 24.04
  - **Debian** 10 (Buster), 11 (Bullseye), 12 (Bookworm)

- Works on most server environments:
  - ✅ Virtual Private Servers (VPS)
  - ✅ KVM / QEMU instances
  - ✅ LXC containers (with full networking)
  - ✅ Cloud-based instances (e.g. Hetzner, Contabo, DigitalOcean)
  - ✅ Proxmox VMs & containers
  - ✅ Works on **WSL2** (for testing purposes only)

### 📦 Required Packages (automatically installed)

- `nginx`
- `php` (>= 7.4)
- `php-fpm`
- `php-curl`
- `curl`
- `certbot` (Let's Encrypt client)
- `python3-certbot-nginx`
- `unzip` (optional, for file management)

### 🌐 Networking Requirements

- Your domain (e.g. `forward.yourdomain.com`) must:
  - Point to the VPS IP (via A record)
  - Be managed via Cloudflare or other DNS (✅ works with orange-cloud OFF)

- Ports **80** (for Certbot HTTP-01 challenge) and your chosen **listen port** (e.g., 443, 8443) must be:
  - Open and accessible from the public internet
  - Not used by any other web service on the chosen listen port

### 🔐 SSL/TLS

- The script uses Let's Encrypt (via `certbot`) to issue valid HTTPS certificates.
- Certificates auto-renew via `systemd timer` every 60 days.

### 📦 Storage & Resources

- Minimum: 1000MB free disk space
- Minimum: 512MB RAM (recommended)
