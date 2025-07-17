#!/usr/bin/env bash
#
# install-xcpng-guest-agent.sh
# Installs and enables the XCP-NG Guest Agent on Ubuntu, Debian, Fedora, CentOS & AlmaLinux.
#
# Usage: sudo bash install-xcpng-guest-agent.sh

set -euo pipefail

# Must run as root
if [[ $EUID -ne 0 ]]; then
  echo "❗ This script must be run as root. Try: sudo $0"
  exit 1
fi

# Load OS info
. /etc/os-release

OS_ID="$ID"
OS_LIKE="$ID_LIKE"

# Common function to enable and start the service
enable_and_start() {
  local svc
  # The service name can vary, so we check for the most common ones.
  if systemctl list-unit-files | grep -qw xe-linux-distribution.service; then
    svc=xe-linux-distribution.service
  elif systemctl list-unit-files | grep -qw xe-daemon.service; then
    svc=xe-daemon.service
  else
    echo "⚠️  Could not find the XCP-ng guest agent service. Please check the package installation."
    exit 2
  fi

  echo "Enabling & starting $svc …"
  # Use 'enable --now' to perform both actions in one command.
  systemctl enable --now "$svc"
  systemctl status "$svc" --no-pager
}

install_debian() {
  echo "→ Debian/Ubuntu detected. Installing via apt…"
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y xe-guest-utilities
  enable_and_start
}

install_fedora() {
  echo "→ Fedora detected. Installing via dnf…"
  dnf install -y xe-guest-utilities
  enable_and_start
}

# UPDATED FUNCTION FOR ALMALINUX/RHEL
install_rhel() {
  echo "→ RHEL-based distro detected ($OS_ID). Installing XCP-ng repo and tools…"

  # 1. Install the XCP-ng repository. This is required to find the guest utilities.
  if command -v dnf &>/dev/null; then
    dnf install -y https://repo.xcp-ng.org/xcp-ng-release-latest.rpm
  else
    yum install -y https://repo.xcp-ng.org/xcp-ng-release-latest.rpm
  fi

  # 2. Install the latest guest utilities package from the newly added repo.
  if command -v dnf &>/dev/null; then
    dnf install -y xe-guest-utilities-latest
  else
    yum install -y xe-guest-utilities-latest
  fi
  
  # 3. Enable and start the service.
  enable_and_start
}

case "${OS_ID,,}" in
  ubuntu|debian)
    install_debian
    ;;
  fedora)
    install_fedora
    ;;
  centos|almalinux|rhel)
    install_rhel
    ;;
  *)
    # Fallback on ID_LIKE 
    if [[ "${OS_LIKE,,}" =~ debian ]]; then
      install_debian
    elif [[ "${OS_LIKE,,}" =~ (rhel|fedora) ]]; then
      install_rhel
    else
      echo "❌ Unsupported distribution: $OS_ID"
      exit 3
    fi
    ;;
esac

echo "✅ XCP-NG Guest Agent installation complete."
