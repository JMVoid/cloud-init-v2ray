 #!/bin/bash
 
source /opt/cloud-init-scripts/00-env-setter.sh
set -e
echo "--- Running Full Hysteria Setup Script (ACME and Final Config) ---"
# Validate required environment variables
if [ -z "$HOST_DOMAIN" ]; then echo "ERROR: HOST_DOMAIN not set."; exit 1; fi
if [ -z "$USER_EMAIL" ]; then echo "ERROR: USER_EMAIL not set."; exit 1; fi
if [ -z "$HYSTERIA_PASSWD" ]; then echo "ERROR: HYSTERIA_PASSWD not set."; exit 1; fi
echo "Using HOST_DOMAIN=${HOST_DOMAIN} for Hysteria setup"
HYSTERIA_USER=${USER_GROUP_NAME}
HYSTERIA_USER_HOME=$(getent passwd "$HYSTERIA_USER" | cut -d: -f6)
if [ -z "$HYSTERIA_USER_HOME" ]; then echo "ERROR: Could not find home directory for user $HYSTERIA_USER."; exit 1; fi
HYSTERIA_DIR="$HYSTERIA_USER_HOME/hysteria"
HYSTERIA_VERSION="v2.6.1"
HYSTERIA_BIN_URL="https://github.com/apernet/hysteria/releases/download/app%2F${HYSTERIA_VERSION}/hysteria-linux-amd64"
HYSTERIA_BIN_NAME="hysteria-linux-amd64"
HYSTERIA_CONFIG_FILE="$HYSTERIA_DIR/config.yaml"
HYSTERIA_ACME_LOG="$HYSTERIA_DIR/hysteria_acme.log"
HYSTERIA_START_SCRIPT="$HYSTERIA_DIR/start_hy.sh"
mkdir -p "$HYSTERIA_DIR"
cd "$HYSTERIA_DIR"
echo "Downloading Hysteria binary..."
curl -L -o "$HYSTERIA_DIR/$HYSTERIA_BIN_NAME" "$HYSTERIA_BIN_URL"
chmod +x "$HYSTERIA_DIR/$HYSTERIA_BIN_NAME"
cat <<EOF > "$HYSTERIA_CONFIG_FILE"
listen: :443
acme:
  domains:
    - ${HOST_DOMAIN}
  email: ${USER_EMAIL}
  # Optional: Add disable ανθ and http challenge if only using tls-alpn-01 on 443
  # disableHttpChallenge: true
  # disableTlsAlpnChallenge: false # This is what Hysteria uses by default on 443
auth:
  type: password
  password: ${HYSTERIA_PASSWD}
masquerade:
  type: proxy
  proxy:
    url: https://bing.com/
    rewriteHost: true
# For ACME, it's better to remove or comment out bandwidth settings temporarily
# upMbps: 100
# downMbps: 100
EOF
echo "Running Hysteria as root for ACME (port 443 binding)..."
# Run as root to bind to port 443, but drop privileges if Hysteria supports it (it doesn't directly)
# We will chown the certs later if needed
nohup "$HYSTERIA_DIR/$HYSTERIA_BIN_NAME" server -c "$HYSTERIA_CONFIG_FILE" &> "$HYSTERIA_ACME_LOG" &
HYSTERIA_PID=$!
echo "Hysteria (PID: $HYSTERIA_PID) started for ACME. Waiting up to 90s for certificate..."
# Wait for success message or timeout
timeout_seconds=90
elapsed_seconds=0
acme_success=false
while [ $elapsed_seconds -lt $timeout_seconds ]; do
  if [ -f "$HYSTERIA_ACME_LOG" ] && grep -q 'certificate obtained successfully' "$HYSTERIA_ACME_LOG"; then
    echo "ACME certificate obtained successfully by Hysteria for ${HOST_DOMAIN}."
    acme_success=true
    break
  fi
  sleep 5
  elapsed_seconds=$((elapsed_seconds + 5))
  echo "Waited ${elapsed_seconds}s for Hysteria ACME..."
done
echo "Stopping temporary Hysteria (PID: $HYSTERIA_PID)..."
if ps -p $HYSTERIA_PID > /dev/null; then
  kill $HYSTERIA_PID || echo "Kill Hysteria PID $HYSTERIA_PID failed (may have already exited)."
  sleep 5 # Give it time to shut down
  # Ensure it's gone
  if ps -p $HYSTERIA_PID > /dev/null; then kill -9 $HYSTERIA_PID || echo "Force kill Hysteria PID $HYSTERIA_PID failed."; fi
else
  echo "Hysteria PID $HYSTERIA_PID was not running (or exited quickly)."
fi
if [ -f "$HYSTERIA_ACME_LOG" ]; then
  echo "--- Hysteria ACME Log ---"
  cat "$HYSTERIA_ACME_LOG"
  echo "--- End Hysteria ACME Log ---"
else
  echo "WARNING: Hysteria ACME log not found: $HYSTERIA_ACME_LOG."
fi
if [ "$acme_success" = false ]; then
  echo "ERROR: Hysteria failed to obtain ACME certificate for ${HOST_DOMAIN} within $timeout_seconds seconds."
  # Attempt to find certs dir to ensure cleanup for next try if this is part of a retry loop
  LEGO_CERT_DIR_GUESS1="/root/.local/share/certmagic" # If run as root
  LEGO_CERT_DIR_GUESS2="/root/.lego" # Older Hysteria versions
  if [ -d "$LEGO_CERT_DIR_GUESS1" ]; then echo "ACME failed, consider clearing $LEGO_CERT_DIR_GUESS1 before retry."; fi
  if [ -d "$LEGO_CERT_DIR_GUESS2" ]; then echo "ACME failed, consider clearing $LEGO_CERT_DIR_GUESS2 before retry."; fi
  exit 1
fi
echo "Hysteria ACME run finished."
# Hysteria (via certmagic/lego) stores certs usually in /root/.local/share/certmagic or similar when run as root.
# Or if Hysteria has its own storage path, it would be relative to its config/data dir.
# For Hysteria 2.x, it's often in $XDG_DATA_HOME/certmagic or ~/.local/share/certmagic
# Since we ran as root, it's likely /root/.local/share/certmagic
# We need to ensure the user can access these if Hysteria will run as user later WITH these certs.
# However, Hysteria's config.yaml doesn't specify cert paths, it manages them internally.
# If Hysteria runs as user later, it will try to get certs into user's home.
# For simplicity, this script has Hysteria always manage its own certs.
sed -i 's/^listen: :443$/listen: :6080/' "$HYSTERIA_CONFIG_FILE"
# Add bandwidth settings back if they were commented out
# sed -i '/^# upMbps:/s/^# //;/^# downMbps:/s/^# //' "$HYSTERIA_CONFIG_FILE"
if ! grep -q "listen: :6080" "$HYSTERIA_CONFIG_FILE"; then echo "ERROR: Failed to set Hysteria listen port to :6080."; exit 1; fi
echo "Hysteria config updated for port 6080."
cat <<EOF_START_HY > "$HYSTERIA_START_SCRIPT"
#!/bin/bash
HYSTERIA_APP_DIR="\$(cd "\$(dirname "\$0")" && pwd)"
cd "\$HYSTERIA_APP_DIR" || { echo "Failed to cd to \$HYSTERIA_APP_DIR"; exit 1; }
if [ ! -x "./$HYSTERIA_BIN_NAME" ]; then echo "Error: Hysteria binary ./$HYSTERIA_BIN_NAME not exec."; exit 1; fi
# Ensure log file is writable by the user
touch hysteria.log
nohup "./$HYSTERIA_BIN_NAME" server -c config.yaml &> hysteria.log &
echo "Hysteria (port 6080) started. Log: \$HYSTERIA_APP_DIR/hysteria.log"
EOF_START_HY
chmod +x "$HYSTERIA_START_SCRIPT"
chown -R "${HYSTERIA_USER}:${HYSTERIA_USER}" "$HYSTERIA_DIR" # Chown everything in the dir
echo "Starting Hysteria on port 6080 as user $HYSTERIA_USER..."
if ! sudo -u "$HYSTERIA_USER" bash "$HYSTERIA_START_SCRIPT"; then echo "Failed to start Hysteria as $HYSTERIA_USER."; exit 1; fi
sleep 5 # Give it a moment to start
# Check if Hysteria process is running
if pgrep -u "$HYSTERIA_USER" -f "$HYSTERIA_BIN_NAME.*config.yaml" > /dev/null; then
    echo "Hysteria appears to be running as $HYSTERIA_USER."
else
    echo "ERROR: Hysteria does not seem to be running as $HYSTERIA_USER. Check logs in $HYSTERIA_DIR."
    exit 1
fi
echo "Hysteria setup on port 6080 finished."
echo "--- Full Hysteria Setup Script Finished ---"
exit 0
