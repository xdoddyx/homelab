#!/usr/bin/env bash
#
# install-xcpng-guest-agent.sh
# Installs and enables the XCP-NG Guest Agent on Ubuntu, Debian, Fedora, CentOS & AlmaLinux.
#
# Usage: sudo bash install-xcpng-guest-agent.sh

set -euo pipefail

# must run as root
if [[ $EUID -ne 0 ]]; then
  echo "❗ This script must be run as root. Try: sudo $0"
  exit 1
fi

# load OS info
. /etc/os-release

OS_ID="$ID"
OS_LIKE="$ID_LIKE"

# common: detect which service to use and start it
enable_and_start() {
  local svc
  if systemctl list-unit-files | grep -qw xe-daemon.service; then
    svc=xe-daemon.service
  elif systemctl list-unit-files | grep -qw xe-linux-distribution.service; then
    svc=xe-linux-distribution.service
  else
    echo "⚠️  Could not find xe-daemon.service or xe-linux-distribution.service. Please check the package."
    exit 2
  fi

  echo "Enabling & starting $svc …"
  systemctl enable "$svc"
  systemctl start  "$svc"
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

# CORRECTED FUNCTION FOR ALMALINUX/RHEL
install_rhel() {
  echo "→ RHEL-based distro detected ($OS_ID). Installing XCP-ng repo and tools…"

  # Install the XCP-ng repository which provides the guest utilities package
  if command -v dnf &>/dev/null; then
    dnf install -y https://repo.xcp-ng.org/xcp-ng-release-latest.rpm
  else
    yum install -y https://repo.xcp-ng.org/xcp-ng-release-latest.rpm
  fi

  # Install the latest guest utilities package
  if command -v dnf &>/dev/null; then
    dnf install -y xe-guest-utilities-latest
  else
    yum install -y xe-guest-utilities-latest
  fi
  
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
    # fallback on ID_LIKE 
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
