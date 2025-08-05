#!/bin/bash

# User details
USERNAME="a.jabbouli"
PASSWORD="tgf*jHezTPs8@4wq"

echo "Starting user creation script for user: $USERNAME"

# Check if the user already exists
if id "$USERNAME" &>/dev/null; then
    echo "User '$USERNAME' already exists. Exiting."
    exit 0
fi

# Load OS-release fields
. /etc/os-release
OS_ID="${ID,,}"
OS_ID_LIKE="${ID_LIKE,,}"

# Determine distribution family
if [[ "$OS_ID" == "ubuntu" ]]; then
    DISTRO="ubuntu"
elif [[ "$OS_ID" == "fedora" || \
        "$OS_ID" == "centos" || \
        "$OS_ID" == "almalinux" || \
        "$OS_ID_LIKE" =~ (rhel|fedora|xenenterprise) ]]; then
    DISTRO="rhel"
else
    echo "Unsupported distribution ($NAME). This script supports Ubuntu, Fedora, CentOS, AlmaLinux, XCP-ng, and other RHEL-based distros."
    exit 1
fi

echo "Detected distribution family: $DISTRO"

# Create the user
echo "Creating user '$USERNAME'..."
useradd -m "$USERNAME" || { echo "Failed to create user"; exit 1; }

echo "Setting password for '$USERNAME'..."
echo "$USERNAME:$PASSWORD" | chpasswd || { echo "Failed to set password"; exit 1; }

# Add to sudoers with NOPASSWD
echo "Configuring sudoers for user '$USERNAME'..."
case "$DISTRO" in
    ubuntu)
        usermod -aG sudo "$USERNAME"
        # Change default shell to bash for Ubuntu
        echo "Changing default shell for '$USERNAME' to bash..."
        chsh -s /bin/bash "$USERNAME" || { echo "Failed to change shell to bash"; exit 1; }
        ;;
    rhel)
        usermod -aG wheel "$USERNAME"
        ;;
esac

# Write sudoers snippet
sudo tee /etc/sudoers.d/"$USERNAME" > /dev/null <<EOF
$USERNAME ALL=(ALL) NOPASSWD: ALL
EOF
chmod 0440 /etc/sudoers.d/"$USERNAME"

echo "User '$USERNAME' created with sudo and NOPASSWD privileges successfully."
echo "Please remember to secure the password for user '$USERNAME'."
