#!/bin/bash
source /opt/cloud-init-scripts/00-env-setter.sh
set -e # Exit immediately if a command exits with a non-zero status.
echo "--- Running OS and Architecture Check Script ---"
# Check OS Distribution, Version, and Architecture
OS_ID=$(lsb_release -is)
OS_VERSION=$(lsb_release -rs)
ARCH=$(uname -m)
echo "Detected OS: $OS_ID $OS_VERSION, Arch: $ARCH"
# Check 1: Must be Ubuntu and x86_64
if [ "$OS_ID" != "Ubuntu" ] || [ "$ARCH" != "x86_64" ]; then
  echo "Requirement Failure: OS must be Ubuntu and Architecture must be x86_64. Aborting subsequent setup."
  exit 1
fi
# Check 2: Ubuntu version must be 20.04 or higher
if ! dpkg --compare-versions "$OS_VERSION" ge "20.04"; then
  echo "Requirement Failure: Ubuntu version must be 20.04 or higher (found $OS_VERSION). Aborting subsequent setup."
  exit 1
fi
echo "OS/Arch/Version requirements met ($OS_ID $OS_VERSION on $ARCH). Proceeding..."
exit 0 # Explicitly indicate success