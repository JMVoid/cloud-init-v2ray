#!/bin/bash
source /opt/cloud-init-scripts/00-env-setter.sh
set -e
echo "--- Running V2Ray Setup Script ---"
V2RAY_USER=${USER_GROUP_NAME} # Define user here for clarity
# Validate required environment variables
if [ -z "$V2RAY_USER_UUID" ]; then echo "ERROR: V2RAY_USER_UUID not set."; exit 1; fi
if [ -z "$V2RAY_PORT" ]; then echo "ERROR: V2RAY_PORT not set."; exit 1; fi
# Ensure the user exists before trying to sudo to them
if ! id -u "$V2RAY_USER" >/dev/null 2>&1; then
  echo "ERROR: User $V2RAY_USER does not exist. Cannot setup V2Ray."
  exit 1
fi
V2RAY_USER_HOME=$(getent passwd "$V2RAY_USER" | cut -d: -f6)
if [ -z "$V2RAY_USER_HOME" ]; then echo "ERROR: Could not find home directory for user $V2RAY_USER."; exit 1; fi
# Run the core setup as the target user, passing required variables
sudo -u "$V2RAY_USER" \
    V2RAY_USER_UUID="$V2RAY_USER_UUID" \
    V2RAY_PORT="$V2RAY_PORT" \
    bash -c '
set -e # Critical to have this inside the subshell as well
V2RAY_USER_WHOAMI=$(whoami)
echo "V2Ray setup as user: $V2RAY_USER_WHOAMI..."
# Get home directory reliably inside the subshell
MY_HOME=$(eval echo ~$V2RAY_USER_WHOAMI)
V2RAY_DIR="$MY_HOME/v2ray"
V2RAY_JSON_CONFIG="config.json"
V2RAY_LOG_DIR="$V2RAY_DIR/logs"
V2RAY_ZIP_URL="https://github.com/v2fly/v2ray-core/releases/download/v5.42.0/v2ray-linux-64.zip"
V2RAY_ZIP_NAME="v2ray-linux-64.zip"
V2RAY_CONFIG_FILE="$V2RAY_DIR/$V2RAY_JSON_CONFIG"
V2RAY_START_SCRIPT="$V2RAY_DIR/start_v2ray.sh"
V2RAY_CORE_BINARY="v2ray" # Binary name inside the zip
# Stop existing V2Ray instance if any from this user
# Using pkill with full path to be more specific if possible, or just by name
# if pgrep -u "$V2RAY_USER_WHOAMI" -f "$V2RAY_CORE_BINARY.*config.json" > /dev/null; then
    # echo "Attempting to stop existing V2Ray process for user $V2RAY_USER_WHOAMI..."
    # pkill -u "$V2RAY_USER_WHOAMI" -f "$V2RAY_CORE_BINARY.*config.json"
    # sleep 3
# fi
mkdir -p "$V2RAY_DIR" && mkdir -p "$V2RAY_LOG_DIR"
# cd into the directory to ensure files are extracted there
cd "$V2RAY_DIR" || { echo "Failed to cd into $V2RAY_DIR"; exit 1; }
echo "Downloading V2Ray..."
# Use curl with -f to fail silently on server errors, makes scripting easier
if ! curl -L -f -o "$V2RAY_ZIP_NAME" "$V2RAY_ZIP_URL"; then
  echo "ERROR: Failed to download V2Ray from $V2RAY_ZIP_URL"
  exit 1
fi
echo "Unzipping V2Ray..."
# -o for overwrite without prompting
if ! unzip -o "$V2RAY_ZIP_NAME" -d "$V2RAY_DIR"; then
  echo "ERROR: Failed to unzip $V2RAY_ZIP_NAME"
  exit 1
fi
rm "$V2RAY_ZIP_NAME" # Clean up zip file
# Ensure the binary is executable
if [ ! -f "$V2RAY_DIR/$V2RAY_CORE_BINARY" ]; then
  echo "ERROR: V2Ray binary $V2RAY_DIR/$V2RAY_CORE_BINARY not found after unzip."
  ls -la "$V2RAY_DIR" # List contents for debugging
  exit 1
fi
chmod +x "$V2RAY_DIR/$V2RAY_CORE_BINARY"
echo "Creating V2Ray config file: $V2RAY_CONFIG_FILE"
# Ensure log paths are absolute or correctly relative for the user
cat <<EOF_V2RAY > "$V2RAY_CONFIG_FILE"
{
  "log": {
    "access": "$V2RAY_LOG_DIR/access.log",
    "error": "$V2RAY_LOG_DIR/error.log",
    "loglevel": "warning"
  },
  "inbounds": [{
      "listen": "127.0.0.1",
      "port": ${V2RAY_PORT},
      "protocol": "vmess",
      "settings": {
          "clients": [{"id": "${V2RAY_USER_UUID}", "alterId": 0}]
      },
      "streamSettings": {
          "network": "ws",
          "wsSettings": {"path": "/tunnel"}
      }
  }],
  "outbounds": [{"protocol": "freedom", "settings": {}}]
}
EOF_V2RAY
echo "Creating V2Ray start script: $V2RAY_START_SCRIPT"
cat <<EOF_START > "$V2RAY_START_SCRIPT"
#!/bin/bash
V2RAY_APP_DIR="\$(cd "\$(dirname "\$0")" && pwd)"
cd "\$V2RAY_APP_DIR" || { echo "Failed to cd to \$V2RAY_APP_DIR"; exit 1; }
V2RAY_EXE="./$V2RAY_CORE_BINARY" # Use variable for binary name
V2RAY_CONF="config.json"
V2RAY_RUN_LOG="v2ray_run.log" # Log for nohup output
if [ ! -x "\$V2RAY_EXE" ]; then
  echo "Error: V2Ray binary \$V2RAY_EXE is not found or not executable in \$V2RAY_APP_DIR";
  exit 1;
fi
if [ ! -f "\$V2RAY_CONF" ]; then
  echo "Error: V2Ray config \$V2RAY_CONF not found in \$V2RAY_APP_DIR";
  exit 1;
fi
# Ensure log files can be written to
touch "\$V2RAY_RUN_LOG"
mkdir -p "$V2RAY_LOG_DIR" # Ensure log dir from config exists
touch "$V2RAY_LOG_DIR/access.log" "$V2RAY_LOG_DIR/error.log"
echo "Starting V2Ray..."
# Using "run" command for v2ray v5+
nohup "\$V2RAY_EXE" run -c "\$V2RAY_CONF" &> "\$V2RAY_RUN_LOG" &
echo "V2Ray started. Runtime Log: \$V2RAY_APP_DIR/\$V2RAY_RUN_LOG. Config Logs: $V2RAY_LOG_DIR"
EOF_START
chmod +x "$V2RAY_START_SCRIPT"
echo "Executing V2Ray start script..."
bash "$V2RAY_START_SCRIPT"
sleep 5 # Give it a moment to start
# Check if V2Ray process is running
if pgrep -u "$V2RAY_USER_WHOAMI" -f "$V2RAY_CORE_BINARY.*$V2RAY_JSON_CONFIG" > /dev/null; then
    echo "V2Ray appears to be running as $V2RAY_USER_WHOAMI."
else
    echo "ERROR: V2Ray does not seem to be running as $V2RAY_USER_WHOAMI. Check logs in $V2RAY_DIR and $V2RAY_LOG_DIR."
    echo "--- Content of $V2RAY_START_SCRIPT ---"
    cat "$V2RAY_START_SCRIPT"
    echo "--- Content of $V2RAY_DIR/v2ray_run.log (if exists) ---"
    cat "$V2RAY_DIR/v2ray_run.log" || echo "v2ray_run.log not found."
    echo "--- Content of $V2RAY_LOG_DIR/error.log (if exists) ---"
    cat "$V2RAY_LOG_DIR/error.log" || echo "$V2RAY_LOG_DIR/error.log not found."
    exit 1 # Fail the parent script
fi
echo "V2Ray setup as user $V2RAY_USER_WHOAMI completed."
' || { echo "V2Ray setup script (as $V2RAY_USER) failed."; exit 1; } # End of sudo -u block
echo "--- V2Ray Setup Script Finished ---"
exit 0
