#!/usr/bin/env bash

set -Eeuo pipefail

# Configuration
LOG_FILE="/var/log/auto-apt-update.log"
LOCK_FILE="/run/lock/auto-apt-update.lock"
REBOOT_IF_REQUIRED=false

# Require root
if [[ $EUID -ne 0 ]]; then
    echo "This script must run as root."
    exit 1
fi

# Prevent overlapping executions
exec 9>"$LOCK_FILE"

if ! flock -n 9; then
    echo "Another APT update process is already running."
    exit 0
fi

# Log everything
exec >> "$LOG_FILE" 2>&1

echo "=================================================="
echo "APT maintenance started: $(date --iso-8601=seconds)"
echo "Hostname: $(hostname)"
echo "=================================================="

export DEBIAN_FRONTEND=noninteractive

APT_OPTIONS=(
    -o DPkg::Lock::Timeout=300
)

# Record failures
trap 'echo "ERROR: APT maintenance failed at $(date --iso-8601=seconds), line $LINENO."' ERR

# 1. Update package indexes
echo ""
echo "Updating package indexes..."

apt-get "${APT_OPTIONS[@]}" update

# 2. Install available upgrades
echo ""
echo "Installing available upgrades..."

apt-get "${APT_OPTIONS[@]}" upgrade -y

# 3. Remove unnecessary packages
echo ""
echo "Removing unnecessary packages..."

apt-get "${APT_OPTIONS[@]}" autoremove -y

# 4. Clean package cache
echo ""
echo "Cleaning package cache..."

apt-get clean

# 5. Check reboot requirement
echo ""
if [[ -f /var/run/reboot-required ]]; then
    echo "REBOOT_REQUIRED"
    if [[ -f /var/run/reboot-required.pkgs ]]; then
        echo "Packages requiring reboot:"
        cat /var/run/reboot-required.pkgs
    fi
    if [[ "$REBOOT_IF_REQUIRED" == "true" ]]; then
        echo "Scheduling system reboot in one minute..."
        /usr/sbin/shutdown -r +1 "Rebooting after scheduled OS updates"
    else
        echo "Automatic reboot disabled. Manual intervention may be required."
    fi
else
    echo "NO_REBOOT_REQUIRED"
    echo "System does not require a reboot."
fi

echo ""
echo "APT maintenance completed: $(date --iso-8601=seconds)"
echo "=================================================="
