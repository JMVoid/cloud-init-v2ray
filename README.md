# Cloud-Init V2Ray + Hysteria Proxy Server

Automated cloud-init deployment for a secure dual-protocol proxy server featuring V2Ray (WebSocket over HTTPS) and Hysteria (QUIC-based) with automatic SSL certificate management and Cloudflare DNS integration.

## Features

- **Automated Ubuntu Setup**: Complete server provisioning on Ubuntu 20.04+ (x86_64 only)
- **Dual Proxy Protocols**: 
  - V2Ray with WebSocket transport over HTTPS (port 443, path `/tunnel`)
  - Hysteria with QUIC protocol (port 6080, TCP/UDP)
- **Automatic SSL Certificates**: Let's Encrypt certificates via Certbot and Hysteria's built-in ACME
- **Cloudflare DNS Auto-Update**: Automatically updates your A record with the server's public IP
- **Security Hardening**: 
  - SSH on non-standard port 326
  - UFW firewall with minimal open ports
  - Nginx security headers and TLS best practices
- **Network Optimization**: BBR congestion control enabled for better performance
- **Cloud-Native**: Designed for cloud providers supporting cloud-init (AWS, DigitalOcean, Linode, etc.)

## Prerequisites

### System Requirements
- Ubuntu 20.04 or higher (x86_64 architecture only)
- Minimum 1GB RAM recommended
- Public IPv4 address

### Account Requirements
- **Cloudflare Account**: With a domain managed through Cloudflare
- **Cloudflare API Token**: With DNS edit permissions for your domain
- **Cloud Provider**: Supporting cloud-init user data (most major providers do)

## Configuration Variables

Before deployment, you must customize the following variables in the `cloud-init.tpl` file:

| Variable | Description | Example |
|----------|-------------|---------|
| `instance_name` | Subdomain prefix for your server | `server01` |
| `domain` | Root domain managed by Cloudflare | `example.com` |
| `user_group_name` | Username to create on the server | `proxyuser` |
| `cf_dns_api_key` | Cloudflare API token with DNS edit permissions | `` |
| `user_email` | Email for SSL certificate registration (Let's Encrypt) | `your-email@example.com` |
| `hysteria_passwd` | Password for Hysteria client authentication | `your-hysteria-password` |

**Important**: The final hostname will be `${instance_name}.${domain}` (e.g., `server01.example.com`).


```
Client Connections:
├── V2Ray: wss://server01.example.com:443/tunnel
└── Hysteria: server01.example.com:6080 (QUIC)

Server Ports:
├── 326/tcp    → SSH daemon
├── 80/tcp     → HTTP (temporary for ACME challenges)
├── 443/tcp    → Nginx → V2Ray (127.0.0.1:37890)
└── 6080/tcp+udp → Hysteria direct
```

## Client Configuration

### V2Ray Client Configuration
(V2Ray core version used in deployment: v5.42.0)
```json
{
  "inbounds": [],
  "outbounds": [{
    "protocol": "vmess",
    "settings": {
      "vnext": [{
        "address": "server01.example.com",
        "port": 443,
        "users": [{"id": "e1dd3d78-daaf-*****-d257ff2ab2fb", "alterId": 0}]
      }]
    },
    "streamSettings": {
      "network": "ws",
      "security": "tls",
      "wsSettings": {"path": "/tunnel"}
    }
  }]
}
```
## Deployment Instructions

### Step 1: Customize Configuration
1. Edit `cloud-init.tpl` and replace all template variables (`${instance_name}`, `${domain}`, etc.)
2. **Customize Template Variables**: All sensitive credentials (Cloudflare API token, email addresses, Hysteria password, V2Ray UUID) are now configurable via template variables in `cloud-init.tpl`. Customize these variables directly in `cloud-init.tpl` before deployment.

### Step 2: Generate Cloud-Init User Data
```bash
# Substitute your actual values
export INSTANCE_NAME="your-instance"
export DOMAIN="your-domain.com" 
export USER_GROUP_NAME="your-username"
export CF_DNS_API_KEY="your-cloudflare-token"

# Generate the final cloud-init file
envsubst < cloud-init.tpl > cloud-init.yaml
```

### Step 3: Deploy to Cloud Provider
Upload the generated `cloud-init.yaml` as user data when creating your cloud instance.

### Step 4: Verify Deployment
After ~10-15 minutes, verify the setup:

```bash
# Check if all services are running
sudo systemctl status nginx
ps aux | grep -E "(v2ray|hysteria)"

# Check firewall rules
sudo ufw status verbose

# Test connectivity (replace with your actual domain)
curl -I https://your-instance.your-domain.com/tunnel
```

## Troubleshooting

### Common Issues

#### Certificate Issuance Failures
- **Symptom**: Nginx fails to start, SSL errors
- **Solution**: Check `/var/log/letsencrypt/letsencrypt.log` and ensure ports 80/443 are free during ACME challenges

#### DNS Propagation Delays
- **Symptom**: Cloudflare script completes but domain doesn't resolve
- **Solution**: Wait for DNS propagation (script includes 5-minute wait) or check Cloudflare dashboard

#### Service Startup Issues
- **Check logs**:
  - V2Ray: `~/v2ray/logs/error.log` and `~/v2ray/v2ray_run.log`
  - Hysteria: `~/hysteria/hysteria.log`
  - Nginx: `/var/log/nginx/your-domain-access.log`
  - Cloud-init: `/var/log/cloud-init-output.log`

#### Port Conflicts
- **Symptom**: Services fail to bind to ports
- **Solution**: Ensure no other web servers (Apache, Nginx) are running before deployment

### Verification Commands
```bash
# Check if V2Ray is listening
netstat -tuln | grep 37890

# Check if Hysteria is listening  
netstat -tuln | grep 6080

# Test Nginx configuration
sudo nginx -t

# Check BBR status
sysctl net.ipv4.tcp_congestion_control
```

## Known Issues & Limitations

### Current Issues
2. **Hardcoded Credentials**: While many credentials are now configurable via template variables, some might still be hardcoded in the scripts. Review all `.sh` scripts for any remaining hardcoded sensitive information.
3. **Process Management**: Services run via custom start scripts rather than systemd units

### Planned Improvements
- [ ] Fix environment variable file naming consistency
- [ ] Make all credentials configurable via template variables
- [ ] Add proper systemd service files for V2Ray and Hysteria
- [ ] Add monitoring and health check endpoints
- [ ] Support additional architectures (ARM64)

## Project Structure

```
├── cloud-init.tpl          # Main cloud-init template
├── 01-os-check.sh         # OS and architecture validation
├── 02-sshd-config.sh      # SSH daemon hardening
├── 03-cloudflare-dns.sh   # Cloudflare DNS auto-update
├── 04-hysteria-setup.sh   # Hysteria installation and ACME
├── 05-certbot-setup.sh    # Certbot installation and SSL certs
├── 06-nginx-v2ray.sh      # Nginx reverse proxy configuration
├── 07-system-tweaks.sh    # BBR congestion control setup
└── 08-v2ray-setup.sh      # V2Ray installation and configuration
```

## License

This project is provided as-is without warranty. Use at your own risk and ensure compliance with local laws and regulations regarding proxy services.

---

**Note**: This automation is designed for educational and legitimate privacy purposes. Always ensure you have proper authorization before deploying proxy services.
