#!/bin/bash
set -e
echo "--- Running System Tweaks (BBR) Script ---"

# Use a dedicated config file in /etc/sysctl.d/ for modularity.
BBR_CONF_FILE="/etc/sysctl.d/99-bbr-tweaks.conf"

echo "Creating/updating BBR sysctl config at $BBR_CONF_FILE"
cat <<EOF > "$BBR_CONF_FILE"
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
EOF

echo "Applying new sysctl settings..."
# The -p flag will load settings from all .conf files in /etc/sysctl.d/
sysctl -p

echo "Verifying current settings..."
echo "Current congestion control: $(sysctl -n net.ipv4.tcp_congestion_control)"
echo "Current default qdisc: $(sysctl -n net.core.default_qdisc)"

# Check if BBR module is loaded. It should be after applying sysctl settings.
if lsmod | grep -q tcp_bbr; then
  echo "BBR module is loaded."
else
  echo "WARNING: BBR module (tcp_bbr) is not loaded. Attempting to modprobe..."
  if modprobe tcp_bbr; then
    echo "BBR module loaded successfully via modprobe."
  else
    echo "ERROR: Failed to load BBR module. BBR might not be active."
  fi
fi

echo "--- System Tweaks (BBR) Script Finished ---"
exit 0
