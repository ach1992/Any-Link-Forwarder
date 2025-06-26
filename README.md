# Marzban Subscription Link Forwarder (PHP + SSL)

A lightweight reverse proxy for forwarding Marzban panel subscriptions through your custom domain with HTTPS — using only PHP, certbot, and socat.

## 🔧 One-liner installation

```
bash <(curl -sSL https://raw.githubusercontent.com/ach1992/Marzban-Sub-Forwarder/main/marzforwarder.sh) install
```

---

## 🚀 CLI Commands

After installing the script, you can manage the forwarder using the global command:

```
marzforwarder
```

### 🔧 Available Commands

| Command                                   | Description                                                                 |
|-------------------------------------------|-----------------------------------------------------------------------------|
| `marzforwarder install`                   | Installs all required dependencies and sets up the forwarder.              |
| `marzforwarder configure`                 | Prompts for Marzban panel domain and port, and saves them to config.       |
| `marzforwarder reconfigure`               | Updates domain, Marzban config, and reissues the SSL certificate.          |
| `marzforwarder start yourdomain.ir [port]`       | Starts the forwarder manually in your terminal session.                    |
| `marzforwarder systemd-setup yourdomain.ir [port]` | Creates a persistent systemd service for automatic background execution.   |
| `marzforwarder uninstall`                 | Completely removes the forwarder, SSL, config, and service.                |


## ⚙️ Requirements

To use this Marzban subscription forwarder, ensure your system meets the following requirements:

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

- `php` (>= 7.4)
- `php-curl`
- `curl`
- `certbot` (Let's Encrypt client)
- `socat`
- `unzip` (optional, for file management)

### 🌐 Networking Requirements

- Your domain (e.g. `forward.yourdomain.com`) must:
  - Point to the VPS IP (via A record)
  - Be managed via Cloudflare or other DNS (✅ works with orange-cloud OFF)

- Ports **80** and **443** must be:
  - Open and accessible from the public internet
  - Not used by nginx, apache, or any other web service

### 🔐 SSL/TLS

- The script uses Let's Encrypt (via `certbot`) to issue valid HTTPS certificates
- Certificates auto-renew via `cron` every 60 days

### 📦 Storage & Resources

- Minimum: 100MB free disk space
- Minimum: 512MB RAM (recommended)

