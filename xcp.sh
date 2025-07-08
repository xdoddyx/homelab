#!/usr/bin/env bash
#
# install-xcpng-guest-agent.sh
# Installs and enables the XCP-NG Guest Agent on Ubuntu, Debian, Fedora, CentOS, and AlmaLinux.
#
# Usage: sudo bash install-xcpng-guest-agent.sh

set -e

# Ensure script is run as root
if [[ $EUID -ne 0 ]]; then
  echo "This script must be run with root privileges. Try: sudo $0"
  exit 1
fi

# Detect OS
. /etc/os-release

OS_ID="$ID"
OS_LIKE="$ID_LIKE"

# Function to install on Debian/Ubuntu
install_debian() {
  echo "Detected Debian/Ubuntu. Installing via apt..."
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y xe-guest-utilities
  systemctl enable xe-linux-distribution
  systemctl start xe-linux-distribution
}

# Function to install on Fedora
install_fedora() {
  echo "Detected Fedora. Installing via dnf..."
  dnf install -y xe-guest-utilities
  systemctl enable xe-linux-distribution
  systemctl start xe-linux-distribution
}

# Function to install on RHEL-based (CentOS, AlmaLinux)
install_rhel() {
  echo "Detected RHEL-based distro (${OS_ID}). Installing EPEL & xe-guest-utilities..."
  # Enable EPEL if not already
  if ! rpm -qa | grep -qw epel-release; then
    yum install -y epel-release || dnf install -y epel-release
  fi
  # Install guest agent
  yum install -y xe-guest-utilities || dnf install -y xe-guest-utilities
  systemctl enable xe-linux-distribution
  systemctl start xe-linux-distribution
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
    # Try using ID_LIKE
    if [[ "${OS_LIKE,,}" =~ (debian) ]]; then
      install_debian
    elif [[ "${OS_LIKE,,}" =~ (rhel fedora) ]]; then
      install_rhel
    else
      echo "Unsupported distribution: $OS_ID"
      exit 2
    fi
    ;;
esac

echo "XCP-NG Guest Agent installation complete."
