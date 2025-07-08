#!/bin/bash
# Domain join script for Linux (Ubuntu/CentOS/XCP-ng) with test mode

# === CONFIGURATION ===
DOMAIN="corp.rstnusa.com"
REALM="CORP.RSTNUSA.COM"
AD_USER="doddy.s"
AD_GROUPS=("linuxadmin")
USE_FQN="False"
LOGFILE="/var/log/ad_join.log"
FALLBACK_DNS1="192.168.153.120"
FALLBACK_DNS2="192.168.153.44"
LOCAL_USER="inspire"
RETRY=3
TEST_MODE="false"

# === START LOGGING ===
exec > >(tee -a "$LOGFILE") 2>&1
echo "===== Starting AD Join Process: $(date) ====="

# === CHECK FOR TEST MODE ===
if [ "$1" == "--test" ]; then
    TEST_MODE="true"
    echo "Running in TEST MODE — no changes will be made."
fi

run_or_echo() {
    if [ "$TEST_MODE" == "true" ]; then
        echo "+ $1"
    else
        eval "$1"
    fi
}

# === DETECT OS FAMILY ===
OS_FAMILY=""
if [ -f /etc/os-release ]; then
    . /etc/os-release
    case "$ID" in
        ubuntu)
            OS_FAMILY="ubuntu"
            INSTALL_CMD="apt-get install -y"
            ;;
        almalinux|centos|rhel|xenenterprise)
            OS_FAMILY="rhel"
            INSTALL_CMD="yum install -y"

            # === SET SELinux to permissive ===
            echo "Setting SELinux to permissive..."
            run_or_echo "setenforce 0"
            run_or_echo "sed -i 's/^SELINUX=.*/SELINUX=permissive/' /etc/selinux/config"
            ;;
        *)
            echo "Unsupported OS: $ID"
            exit 1
            ;;
    esac
else
    echo "Cannot determine OS type."
    exit 1
fi

# === NETWORK CHECK ===
echo "Checking network connectivity..."
ping -c 2 8.8.8.8 >/dev/null || { echo "No network. Exiting."; exit 1; }
echo "Network OK."

# === SET PERSISTENT DNS ===
echo "Setting persistent DNS..."
run_or_echo "echo -e 'nameserver $FALLBACK_DNS1\nnameserver $FALLBACK_DNS2' > /etc/resolv.conf"
if [ "$OS_FAMILY" = "rhel" ]; then
    for conf in /etc/sysconfig/network-scripts/ifcfg-*; do
        grep -q "^DNS1" "$conf" || echo "DNS1=$FALLBACK_DNS1" >> "$conf"
        grep -q "^DNS2" "$conf" || echo "DNS2=$FALLBACK_DNS2" >> "$conf"
        grep -q "^PEERDNS" "$conf" || echo "PEERDNS=no" >> "$conf"
    done
fi

# === ENSURE DNS UTILITIES INSTALLED ===
if ! command -v host >/dev/null 2>&1; then
    echo "host command not found; installing DNS utilities..."
    if [ "$OS_FAMILY" = "ubuntu" ]; then
        run_or_echo "\$INSTALL_CMD dnsutils"
    else
        run_or_echo "\$INSTALL_CMD bind-utils"
    fi
fi

# === DNS RESOLUTION CHECK WITH RETRIES ===
echo "Checking DNS for $DOMAIN with $RETRY retries..."
for i in $(seq 1 $RETRY); do
    host "$DOMAIN" && break
    echo "Retrying DNS resolution ($i/$RETRY)..."
    sleep 2
    if [ $i -eq $RETRY ]; then
        echo "DNS resolution failed after $RETRY attempts. Exiting."
        exit 1
    fi
done
echo "DNS resolution OK."

# === SET HOSTNAME ===
HOSTNAME_BASE=$(hostname -s)
NEW_HOSTNAME="$HOSTNAME_BASE.$DOMAIN"
echo "Setting hostname to $NEW_HOSTNAME"
run_or_echo "hostnamectl set-hostname $NEW_HOSTNAME"

# === INSTALL REQUIRED PACKAGES ===
echo "Installing required packages..."
if [ "$OS_FAMILY" = "ubuntu" ]; then
    run_or_echo "apt-get update"
    run_or_echo "\$INSTALL_CMD realmd sssd sssd-tools oddjob oddjob-mkhomedir adcli samba-common krb5-user packagekit"
else
    run_or_echo "\$INSTALL_CMD epel-release"
    run_or_echo "\$INSTALL_CMD realmd sssd sssd-tools oddjob oddjob-mkhomedir adcli samba-common samba-common-tools krb5-workstation bind-utils"
fi

# === ENABLE ODDJOBD ===
echo "Enabling oddjobd..."
run_or_echo "systemctl enable oddjobd"
run_or_echo "systemctl start oddjobd"

# === JOIN DOMAIN ===
echo "Joining AD domain $REALM as $AD_USER..."
if [ "$TEST_MODE" == "true" ]; then
    echo "+ realm join --user=\"$AD_USER\" \"$REALM\""
else
    echo "Enter password for $AD_USER:"
    realm join --user="$AD_USER" "$REALM"
    [ $? -ne 0 ] && { echo "Domain join failed."; exit 1; }
fi

# === CONFIGURE SSSD ===
SSSD_CONF="/etc/sssd/sssd.conf"
echo "Configuring SSSD: $SSSD_CONF"
if [ -f "$SSSD_CONF" ]; then
    run_or_echo "chmod 600 $SSSD_CONF"

    run_or_echo "grep -q '^use_fully_qualified_names' $SSSD_CONF && \
        sed -i 's/^use_fully_qualified_names.*/use_fully_qualified_names = $USE_FQN/' $SSSD_CONF || \
        sed -i '/^\[sssd\]/a use_fully_qualified_names = $USE_FQN' $SSSD_CONF"

    run_or_echo "grep -q '^pam_mkhomedir' $SSSD_CONF && \
        sed -i 's/^pam_mkhomedir.*/pam_mkhomedir = yes/' $SSSD_CONF || \
        sed -i '/^\[pam\]/a pam_mkhomedir = yes' $SSSD_CONF"

    # use sssctl for config validation
    run_or_echo "sssctl config-check --config-file $SSSD_CONF"
    run_or_echo "systemctl restart sssd"
else
    echo "$SSSD_CONF not found!"
fi

# === GRANT SUDOERS TO AD GROUPS ===
for group in "${AD_GROUPS[@]}"; do
    run_or_echo "echo '%$group ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/$group"
    run_or_echo "chmod 440 /etc/sudoers.d/$group"
done

# === RESTRICT LOGIN ACCESS ===
for group in "${AD_GROUPS[@]}"; do
    run_or_echo "realm permit --groups $group"
done
run_or_echo "realm permit $LOCAL_USER"

echo
echo "===== Domain Join Completed: $(date) ====="
echo "Login as AD user or '$LOCAL_USER' allowed"
echo "Log file: $LOGFILE"
if [ "$TEST_MODE" == "true" ]; then
    echo "TEST MODE: No actual changes were made."
fi
