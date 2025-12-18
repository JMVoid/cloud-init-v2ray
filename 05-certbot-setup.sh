 #!/bin/bash
source /opt/cloud-init-scripts/00-env-setter.sh
set -e
echo "--- Running Certbot Setup Script ---"
# Validate required environment variables
if [ -z "$HOST_DOMAIN" ]; then echo "ERROR: HOST_DOMAIN not set."; exit 1; fi
if [ -z "$USER_EMAIL" ]; then echo "ERROR: USER_EMAIL not set."; exit 1; fi
echo "Using HOST_DOMAIN=${HOST_DOMAIN} for Certbot"
if ! command -v snap > /dev/null; then
  echo "Snapd not found, attempting to install..."
  apt-get update && apt-get install -y snapd
  # Wait for snapd to be ready
  sleep 15
  # Retry snap command after install
  if ! command -v snap > /dev/null; then
    echo "ERROR: Snapd installation failed or snap command still not available."
    exit 1
  fi
fi
# Ensure snapd is fully seeded, can take a moment on fresh installs
for i in {1..5}; do
  if snap list core >/dev/null 2>&1; then
    echo "Snapd seeded."
    break
  else
    echo "Waiting for snapd to seed... (attempt $i/5)"
    sleep 10
  fi
done
if ! snap list core >/dev/null 2>&1; then
    echo "ERROR: snapd did not seed properly. Try 'snap wait system seed.loaded'"
    # snap wait system seed.loaded # This can hang if there are issues
    # exit 1
fi
if snap list certbot >/dev/null 2>&1; then
  echo "Certbot snap already installed. Ensuring it's up-to-date."
  snap refresh certbot
else
  echo "Installing Certbot snap..."
  snap install --classic certbot
fi
# Wait for certbot command to become available via snap
# Sometimes the link /snap/bin/certbot is not immediately available or PATH not updated
certbot_path=""
for i in {1..5}; do
  if [ -x "/snap/bin/certbot" ]; then
      certbot_path="/snap/bin/certbot"
      break
  elif command -v certbot > /dev/null; then
      certbot_path=$(command -v certbot)
      break
  fi
  echo "Waiting for certbot command to be available (attempt $i/5)..."
  sleep 5
done
if [ -z "$certbot_path" ]; then
  echo "ERROR: certbot command not found after installation."
  exit 1
fi
# Explicitly create symlink if it doesn't exist or is broken
if [ ! -L /usr/bin/certbot ] || [ ! -e /usr/bin/certbot ]; then
  ln -sf "$certbot_path" /usr/bin/certbot
fi
echo "Certbot installed/updated and linked using $certbot_path."
echo "Obtaining Let's Encrypt certificate for ${HOST_DOMAIN} via Certbot standalone..."
certbot_attempt=1
certbot_max_attempts=3 # Increased from 3 in original to handle transient issues
certbot_success=false
while [ $certbot_attempt -le $certbot_max_attempts ]; do
  echo "Certbot attempt $certbot_attempt of $certbot_max_attempts..."
  # Ensure port 80 (and 443 if used by standalone) is free
  # Nginx should be stopped by runcmd before this. Hysteria (ACME part) should also be stopped.
  # Check for listeners on port 80
  if netstat -tulnp | grep -q ':80 '; then
      echo "Port 80 is in use. Attempting to stop conflicting services..."
      systemctl stop nginx || echo "Nginx stop failed/not running (ok)."
      systemctl stop apache2 || echo "Apache2 stop failed/not running (ok)."
      # Add other potential services if necessary
      fuser -k 80/tcp || echo "fuser failed to kill processes on port 80 (ok if none)."
      sleep 5 # Give services time to stop
      if netstat -tulnp | grep -q ':80 '; then
          echo "ERROR: Port 80 is still in use after attempts to free it. Certbot standalone will likely fail."
          netstat -tulnp | grep ':80 '
      fi
  else
      echo "Port 80 appears to be free."
  fi
  # Using --preferred-challenges http for standalone to ensure port 80 is used.
  if certbot certonly --standalone --preferred-challenges http --non-interactive --agree-tos --email "${USER_EMAIL}" -d "${HOST_DOMAIN}" --debug --verbose; then
    echo "Certbot certificate obtained successfully for ${HOST_DOMAIN}."
    certbot_success=true
    break
  else
    echo "Certbot attempt $certbot_attempt failed for ${HOST_DOMAIN}."
    # Show last part of letsencrypt log
    if [ -d "/var/log/letsencrypt/" ]; then
       LATEST_LOG=$(ls -t /var/log/letsencrypt/letsencrypt.log* 2>/dev/null | head -n 1)
       if [ -n "$LATEST_LOG" ]; then
          echo "--- Last 20 lines of $LATEST_LOG ---"
          tail -n 20 "$LATEST_LOG"
          echo "--- End of log excerpt ---"
       fi
    fi
    if [ $certbot_attempt -lt $certbot_max_attempts ]; then
      echo "Waiting 60s before retry..."; # Increased wait time
      sleep 60;
    fi
  fi
  certbot_attempt=$((certbot_attempt + 1))
done
if [ "$certbot_success" = false ]; then
  echo "ERROR: Certbot failed for ${HOST_DOMAIN} after $certbot_max_attempts attempts. Nginx will likely fail."
  # This is a fatal error because subsequent steps depend on the certificate.
  exit 1
fi
echo "--- Certbot Setup Script Finished ---"
exit 0
