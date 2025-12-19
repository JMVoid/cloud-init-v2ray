#cloud-config
# must set following variables: instance_name, domain, user_group_name, cf_dns_api_key,user_email,hysteri, v2ray_uuid

bootcmd:
  - mkdir -p /opt/cloud-init-scripts

# 1. Define required groups (This runs before user creation)
groups:
  - ${user_group_name}

# 2. Update package list
package_update: true

# 3. Install required packages
packages:
  - snapd
  - unzip    # Needed for V2Ray
  - ufw      # Install ufw before trying to configure it
  - curl     # Needed for getting public IP and downloads
  - jq       # Needed for parsing JSON responses
  - nginx    # Install Nginx web server
  - net-tools #Install netstat

# 4. Create user, assign groups, and configure password
users:
  - default
  - name: ${user_group_name}
    shell: /bin/bash
    home: /home/${user_group_name}
    primary_group: ${user_group_name}
    groups: [sudo]          # Add 'sudo' as a secondary group
    passwd: '$y$j9T$UwEBxmjZnsLKoRAZjGe4G1$BxMExdPDR92ia64xOCDzWkGG0BLCQudnc5el9igwiM7' # HASHED PASSWORD - USE SINGLE QUOTES!
    lock_passwd: false # Ensure password is usable

write_files:
  - path: /opt/cloud-init-scripts/00-env-setter.sh
    permissions: '0700'
    owner: root:root
    content: |
      #!/bin/bash
      # This file defines the domain name used across various setup scripts.
      # Modify this value to change the target domain for the entire setup.
      export INSTANCE_NAME=${instance_name}
      export DOMAIN=${domain}
      export HOST_DOMAIN=${instance_name}.${domain}
      export USER_GROUP_NAME=${user_group_name}
      export CF_DNS_API_KEY=${cf_dns_api_key}
      export USER_EMAIL=${user_email}
      export HYSTERIA_PASSWD=${hysteria_passwd}
      export V2RAY_PORT=37890
      export V2RAY_USER_UUID=${v2ray_uuid}

# 6. Run commands
runcmd:

  - echo "--- Running Cloud-init runcmd Phase ---"
  # No need to mkdir /opt/cloud-init-scripts here, write_files handles its creation.

  # Download execution scripts from GitHub repository
  - echo "Downloading execution scripts from GitHub..."
  - mkdir -p /opt/cloud-init-scripts
  - curl -L -o /opt/cloud-init-scripts/01-os-check.sh https://raw.githubusercontent.com/JMVoid/cloud-init-v2ray/refs/heads/master/01-os-check.sh
  - curl -L -o /opt/cloud-init-scripts/02-sshd-config.sh https://raw.githubusercontent.com/JMVoid/cloud-init-v2ray/refs/heads/master/02-sshd-config.sh
  - curl -L -o /opt/cloud-init-scripts/03-cloudflare-dns.sh https://raw.githubusercontent.com/JMVoid/cloud-init-v2ray/refs/heads/master/03-cloudflare-dns.sh
  - curl -L -o /opt/cloud-init-scripts/04-hysteria-setup.sh https://raw.githubusercontent.com/JMVoid/cloud-init-v2ray/refs/heads/master/04-hysteria-setup.sh
  - curl -L -o /opt/cloud-init-scripts/05-certbot-setup.sh https://raw.githubusercontent.com/JMVoid/cloud-init-v2ray/refs/heads/master/05-certbot-setup.sh
  - curl -L -o /opt/cloud-init-scripts/06-nginx-v2ray.sh https://raw.githubusercontent.com/JMVoid/cloud-init-v2ray/refs/heads/master/06-nginx-v2ray.sh
  - curl -L -o /opt/cloud-init-scripts/07-system-tweaks.sh https://raw.githubusercontent.com/JMVoid/cloud-init-v2ray/refs/heads/master/07-system-tweaks.sh
  - curl -L -o /opt/cloud-init-scripts/08-v2ray-setup.sh https://raw.githubusercontent.com/JMVoid/cloud-init-v2ray/refs/heads/master/08-v2ray-setup.sh
  
  # Set executable permissions for downloaded scripts
  - chmod +x /opt/cloud-init-scripts/01-os-check.sh /opt/cloud-init-scripts/02-sshd-config.sh /opt/cloud-init-scripts/03-cloudflare-dns.sh /opt/cloud-init-scripts/04-hysteria-setup.sh /opt/cloud-init-scripts/05-certbot-setup.sh /opt/cloud-init-scripts/06-nginx-v2ray.sh /opt/cloud-init-scripts/07-system-tweaks.sh /opt/cloud-init-scripts/08-v2ray-setup.sh
  
  # Verify scripts were downloaded successfully
  - if [ ! -f /opt/cloud-init-scripts/01-os-check.sh ]; then echo "Failed to download 01-os-check.sh"; fi
  - if [ ! -f /opt/cloud-init-scripts/02-sshd-config.sh ]; then echo "Failed to download 02-sshd-config.sh"; fi
  - if [ ! -f /opt/cloud-init-scripts/03-cloudflare-dns.sh ]; then echo "Failed to download 03-cloudflare-dns.sh"; fi
  - if [ ! -f /opt/cloud-init-scripts/04-hysteria-setup.sh ]; then echo "Failed to download 04-hysteria-setup.sh"; fi
  - if [ ! -f /opt/cloud-init-scripts/05-certbot-setup.sh ]; then echo "Failed to download 05-certbot-setup.sh"; fi
  - if [ ! -f /opt/cloud-init-scripts/06-nginx-v2ray.sh ]; then echo "Failed to download 06-nginx-v2ray.sh"; fi
  - if [ ! -f /opt/cloud-init-scripts/07-system-tweaks.sh ]; then echo "Failed to download 07-system-tweaks.sh"; fi
  - if [ ! -f /opt/cloud-init-scripts/08-v2ray-setup.sh ]; then echo "Failed to download 08-v2ray-setup.sh"; fi

  - echo "Executing OS Check script (01-os-check.sh)..."
  - bash /opt/cloud-init-scripts/01-os-check.sh || { echo "OS Check Script failed, halting runcmd execution."; exit 1; }

  - echo "Configuring UFW firewall..."
  - ufw allow 22/tcp comment 'SSH Custom Port'
  - ufw allow 22/udp comment 'SSH Custom Port (e.g. for mosh)' # Uncomment if mosh is used
  - ufw allow 326/tcp comment 'SSH Custom Port'
  - ufw allow 326/udp comment 'SSH Custom Port (e.g. for mosh)' # Uncomment if mosh is used
  - ufw allow 80/tcp comment 'HTTP for Certbot ACME & Nginx HTTP redirect'
  - ufw allow 443/tcp comment 'HTTPS for Nginx / Hysteria ACME (temporary)'
  - ufw allow 6080/tcp comment 'Hysteria Final Port TCP'
  - ufw allow 6080/udp comment 'Hysteria Final Port UDP'
  - ufw --force enable # Use --force to enable without prompt, good for automation
  - ufw status verbose
  - echo "UFW firewall configured and enabled."

  - |
    {
      set -e
      echo "Executing SSHD Configuration script (02-sshd-config.sh)..."
      bash /opt/cloud-init-scripts/02-sshd-config.sh
      sleep 1
      echo "Restarting SSH service..."
      # systemctl restart ssh might fail if the service name is sshd on some systems
      if systemctl list-units --full --all | grep -q 'ssh.service'; then
          systemctl restart ssh
      elif systemctl list-units --full --all | grep -q 'sshd.service'; then
          systemctl restart sshd
      else
          echo "Failed to find ssh or sshd service to restart." >&2
          exit 1
      fi
      echo "SSH service restarted."
    } || echo "SSHD configuration block failed, but continuing with next commands."


  - echo "Executing Cloudflare DNS Update script (03-cloudflare-dns.sh)..."
  - bash /opt/cloud-init-scripts/03-cloudflare-dns.sh || { echo "Cloudflare DNS script failed."; }
  - echo "Cloudflare DNS script completed."
  - echo "Waiting 5 minutes (300 seconds) for DNS propagation..."
  - sleep 300
  - echo "DNS propagation wait finished."

  # Nginx should be stopped before ACME challenges that might use port 80/443
  # Hysteria ACME (script 04) runs first, then Certbot (script 05)
  - echo "Ensuring Nginx/Apache (if any) services are stopped before ACME challenges..."
  - systemctl stop nginx || echo "Nginx was not running or failed to stop (may be ok)."
 #  - systemctl stop apache2 || echo "Apache2 was not running or failed to stop (may be ok)."
  - sleep 5 # Give services a moment to release ports

  - echo "Executing Hysteria Setup script (04-hysteria-setup.sh)..."
  - bash /opt/cloud-init-scripts/04-hysteria-setup.sh || { echo "Hysteria Setup script failed."; }

  # Stop Nginx/Apache again before Certbot, just in case Hysteria somehow started them (unlikely)
  # or if Hysteria ACME didn't use port 80 and something else grabbed it.
  - echo "Ensuring Nginx/Apache (if any) services are stopped before Certbot ACME challenge..."
  - systemctl stop nginx || echo "Nginx was not running or failed to stop (may be ok)."
  - systemctl stop apache2 || echo "Apache2 was not running or failed to stop (may be ok)."
  - sleep 5

  - echo "Executing Certbot Setup script (05-certbot-setup.sh)..."
  - bash /opt/cloud-init-scripts/05-certbot-setup.sh || { echo "Certbot Setup script failed. Nginx might not start correctly."; exit 1; } # Made this fatal

  - echo "Executing Nginx Configuration script (06-nginx-v2ray.sh)..."
  - bash /opt/cloud-init-scripts/06-nginx-v2ray.sh || { echo "Nginx Configuration script failed."; exit 1; }

  - echo "Executing System Tweaks script (07-system-tweaks.sh)..."
  - bash /opt/cloud-init-scripts/07-system-tweaks.sh || { echo "System Tweaks script failed (BBR setup)."; exit 1; } # BBR failure might not be fatal, but good to know

  - echo "Executing V2Ray Setup script (08-v2ray-setup.sh)..."
  - bash /opt/cloud-init-scripts/08-v2ray-setup.sh || { echo "V2Ray Setup script failed."; exit 1; }

  - echo "--- Cloud-init runcmd Phase Finished Successfully ---"

# 7. Final Message (Optional)
final_message: "System setup finished. SSH: 326. User: $${USER_GROUP_NAME}. Nginx (port 443) proxying V2Ray (ws path /tunnel). Hysteria running on port 6080. Check logs in /var/log/cloud-init-output.log and service-specific logs for details."
