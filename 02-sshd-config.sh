 #!/bin/bash
source /opt/cloud-init-scripts/00-env-setter.sh
set -e # Exit immediately if a command exits with a non-zero status.
echo "--- Running SSHD Configuration Script ---"
SSHD_CONFIG="/etc/ssh/sshd_config"
# Change Port
if grep -qE '^#?Port\s+' "$SSHD_CONFIG"; then
  sed -i -E 's/^#?Port\s+[0-9]+/Port 326/' "$SSHD_CONFIG"
else
  echo "Port 326" >> "$SSHD_CONFIG"
fi
echo "Set Port to 326."
# Change ClientAliveInterval
if grep -qE '^#?ClientAliveInterval\s+' "$SSHD_CONFIG"; then
  sed -i -E 's/^#?ClientAliveInterval\s+[0-9]+/ClientAliveInterval 600/' "$SSHD_CONFIG"
else
  echo "ClientAliveInterval 600" >> "$SSHD_CONFIG"
fi
echo "Set ClientAliveInterval to 600."
# Change ClientAliveCountMax
if grep -qE '^#?ClientAliveCountMax\s+' "$SSHD_CONFIG"; then
  sed -i -E 's/^#?ClientAliveCountMax\s+[0-9]+/ClientAliveCountMax 6/' "$SSHD_CONFIG"
else
  echo "ClientAliveCountMax 6" >> "$SSHD_CONFIG"
fi
echo "Set ClientAliveCountMax to 6."
echo "--- SSHD Configuration Script Finished ---"
exit 0