#!/bin/bash

source /opt/cloud-init-scripts/00-env-setter.sh
set -e
echo "--- Running Nginx Configuration for V2Ray Script ---"
# Validate required environment variables
if [ -z "$HOST_DOMAIN" ]; then echo "ERROR: HOST_DOMAIN not set."; exit 1; fi
# V2RAY_PORT should be defined in 00-env-setter.sh, e.g., export V2RAY_PORT=37890
if [ -z "$V2RAY_PORT" ]; then echo "ERROR: V2RAY_PORT not set."; exit 1; fi
echo "Nginx will be configured for domain: ${HOST_DOMAIN}"
NGINX_CONF_DIR="/etc/nginx/conf.d"
TIMESTAMP=$(date +%Y%m%d%H%M)
V2RAY_NGINX_CONF="$NGINX_CONF_DIR/v2ray-${TIMESTAMP}.conf"
CERT_DIR="/etc/letsencrypt/live/${HOST_DOMAIN}"
if [ ! -f "${CERT_DIR}/fullchain.pem" ] || [ ! -f "${CERT_DIR}/privkey.pem" ]; then
  echo "ERROR: SSL certificates for Nginx domain ${HOST_DOMAIN} not found in ${CERT_DIR}."
  echo "This could be because Certbot (script 05) failed."
  echo "Listing contents of /etc/letsencrypt/live/ (if it exists):"
  ls -l /etc/letsencrypt/live/ || echo "/etc/letsencrypt/live/ not found."
  exit 1
else
  echo "SSL certificates for Nginx domain ${HOST_DOMAIN} appear to exist."
fi
# Remove default Nginx configurations if they exist
rm -f /etc/nginx/sites-enabled/default
rm -f /etc/nginx/sites-available/default
echo "Removed default Nginx site if present."
echo "Creating Nginx vhost for V2Ray: $V2RAY_NGINX_CONF"
cat <<EOF > "$V2RAY_NGINX_CONF"
server {
    listen 443 ssl http2;
    server_name ${HOST_DOMAIN};
    ssl_certificate            ${CERT_DIR}/fullchain.pem;
    ssl_certificate_key        ${CERT_DIR}/privkey.pem;
    ssl_session_timeout 1d;
    ssl_session_cache shared:MozSSL:10m; # roughly 40000 sessions
    ssl_session_tickets off;
    # Modern Mozilla TLS Intermediate configuration
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers on;
    # HSTS (optional, but recommended)
    # add_header Strict-Transport-Security "max-age=63072000" always;
    # OCSP Stapling
    # ssl_stapling on;
    # ssl_stapling_verify on;
    resolver 8.8.8.8 8.8.4.4 valid=300s; # Google DNS, or local resolver
    resolver_timeout 5s;
    # Security headers
    add_header X-Frame-Options DENY;
    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";
    add_header Referrer-Policy "strict-origin-when-cross-origin";
    location /tunnel {
        proxy_redirect           off;
        proxy_pass               http://127.0.0.1:${V2RAY_PORT}; # V2Ray's listening port
        proxy_http_version       1.1;
        proxy_set_header         Upgrade \$http_upgrade;
        proxy_set_header         Connection "upgrade";
        proxy_set_header         Host \$http_host;
        proxy_set_header         X-Real-IP \$remote_addr;
        proxy_set_header         X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header         X-Forwarded-Proto \$scheme;
    }
    access_log /var/log/nginx/${HOST_DOMAIN}-access.log;
    error_log /var/log/nginx/${HOST_DOMAIN}-error.log;
}
EOF
# Create dummy webroot for ACME if not exists (though standalone is used by certbot script)
mkdir -p /var/www/html
echo "Testing Nginx configuration..."
if ! nginx -t; then
  echo "Nginx configuration test failed!"
  cat "$V2RAY_NGINX_CONF" # Show the generated config on error
  exit 1
fi
echo "Restarting Nginx service..."
if systemctl is-active --quiet nginx; then
  systemctl restart nginx
else
  systemctl start nginx
fi
# Verify Nginx status
sleep 3 # Give Nginx a moment to start/restart
if systemctl is-active --quiet nginx; then
  echo "Nginx service is active."
else
  echo "ERROR: Nginx service failed to start/restart."
  journalctl -u nginx --no-pager -n 50 # Show last 50 Nginx log lines
  exit 1
fi
echo "Nginx configured and (re)started."
echo "--- Nginx Configuration for V2Ray Script Finished ---"
exit 0
