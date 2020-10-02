# ====== Log helpers ======
info()
{
    echo '[INFO] ' "$@"
}
warn()
{
    echo '[WARN] ' "$@" >&2
}
fatal()
{
    echo '[ERROR] ' "$@" >&2
    exit 1
}
# ====== Variables =======
USERNAME=${K3SEM_USERNAME}
USERPASS=${K3SEM_USERPASS}
GROUPNAME=${K3SEM_GROUPNAME}
NODE_HOSTNAME=${K3SEM_NODE_HOSTNAME}
ENABLE_GPIO=${K3SEM_GPIO}
SSH_PUBKEY=${K3SEM_SSH_PUBKEY}
HOSTS_FILE=/etc/hosts
validate_env()
{
    if [[ -z "$2" ]]; then
          fatal "$1 can not be empty"
    fi
}
validate_env K3SEM_USERNAME ${USERNAME}
validate_env K3SEM_USERPASS ${USERPASS}
validate_env K3SEM_GROUPNAME ${GROUPNAME}
validate_env K3SEM_NODE_HOSTNAME ${NODE_HOSTNAME}
validate_env K3SEM_GPIO ${ENABLE_GPIO}

# ====== Check and set hostname if needed ======
set_hostname()
{
    CURRENT_HOSTNAME=$(hostname)
    if [[ "$CURRENT_HOSTNAME" != "$NODE_HOSTNAME" ]]; then
        info "Setting hostname to $NODE_HOSTNAME"
        sudo hostnamectl set-hostname ${NODE_HOSTNAME}
    else
        info "Hostname is already set -> Skip"
    fi
}
# ====== Modify hosts ======
modify_hosts()
{
    info "Modifying $HOSTS_FILE"
    if grep -q '^#k3s-cluster' ${HOSTS_FILE}; then
        info "IP Addresses are already set -> Skip"
    else
        info "Creating backup at $HOSTS_FILE.bak"
        sudo cp ${HOSTS_FILE} "$HOSTS_FILE.bak"
        info "Writing addresses to $HOSTS_FILE"
        echo "$HOSTS_BLOCK" >> ${HOSTS_FILE}
    fi
}
# ====== Create user / groups ======
create_user_groups()
{
    info "Configuring user & groups"
    if id "$USERNAME" &>/dev/null; then
        info "    User $USERNAME already exists -> Skip"
    else
        info "    Create user: $USERNAME"
        useradd -m -p $(openssl passwd -crypt ${USERPASS}) ${USERNAME}
    fi

    if grep -q ${GROUPNAME} /etc/group; then
        info "    Group $GROUPNAME already exists -> Skip"
    else
        info "    Create group: $GROUPNAME"
        sudo groupadd -f ${GROUPNAME}
    fi

    if [[ -n "${ENABLE_GPIO}" ]]; then
        info "    Create group: gpio"
        sudo groupadd -f --system gpio
    fi

    info "    Add user $USERNAME to group: sudo"
    sudo usermod -a -G sudo ${USERNAME}
    info "    Add user $USERNAME to group: $GROUPNAME"
    sudo usermod -a -G ${GROUPNAME} ${USERNAME}

    if [[ -n "${ENABLE_GPIO}" ]]; then
        info "    Add user $USERNAME to group: gpio"
        sudo usermod -a -G gpio ${USERNAME}
    fi
}
# ======= cgroup ========
setup_cgroup()
{
    if grep -q 'Raspbian' /etc/os-release; then
        CMDLINETXT="/boot/cmdline.txt"
    else
        CMDLINETXT="/boot/firmware/cmdline.txt"
    fi
    if grep -q 'cgroup' ${CMDLINETXT}; then
        info "cgroup is already enabled -> Skip"
    else
        info "Enabling cgroup"
        sudo sed -i ' 1 s/.*/& cgroup_enable=memory cgroup_memory=1/' ${CMDLINETXT}
    fi
}
# ======= com.rules =======
add_udev_rules()
{
    if [[ -z "${ENABLE_GPIO}" ]]; then
        return
    fi
    if grep -q 'Raspbian' /etc/os-release; then
        info "This node is running on RaspbianOS. There is no need to configure udev rules."
        return 0
    else

        COMRULESDEST="/etc/udev/rules.d/99-com.rules"
        sudo tee -a ${COMRULESDEST} > /dev/null <<EOL
SUBSYSTEM=="input", GROUP="input", MODE="0660"
SUBSYSTEM=="i2c-dev", GROUP="i2c", MODE="0660"
SUBSYSTEM=="spidev", GROUP="spi", MODE="0660"
SUBSYSTEM=="bcm2835-gpiomem", GROUP="gpio", MODE="0660"

SUBSYSTEM=="gpio", GROUP="gpio", MODE="0660"
SUBSYSTEM=="gpio*", PROGRAM="/bin/sh -c '\
        chown -R root:gpio /sys/class/gpio && chmod -R 770 /sys/class/gpio;\
        chown -R root:gpio /sys/devices/virtual/gpio && chmod -R 770 /sys/devices/virtual/gpio;\
        chown -R root:gpio /sys$devpath && chmod -R 770 /sys$devpath\
'"
EOL
    fi
}
# ======= legacy iptables ======
use_legacy_iptables()
{
    if grep -q 'Raspbian' /etc/os-release; then
        sudo iptables -F
        sudo update-alternatives --set iptables /usr/sbin/iptables-legacy
        sudo update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy
    fi
}
# ======= ssh =======
add_authorized_keys()
{
    mkdir -p "/home/$USERNAME/.ssh"
    if [[ -n "$SSH_PUBKEY" ]]; then
        touch "$SSH_PUBKEY" "/home/$USERNAME/.ssh/authorized_keys"
        if grep -q "$SSH_PUBKEY" "/home/$USERNAME/.ssh/authorized_keys"; then
            info "Public key exists in authorized_keys -> Skip"
            return
        fi
        info "Adding public key to authorized_keys"
        echo "$SSH_PUBKEY" >> "/home/$USERNAME/.ssh/authorized_keys"
    fi
}
# ======= reboot ========
reboot_after() {
    secs=$1
    while [[ ${secs} -gt 0 ]]; do
        info "Reboot in $((secs--))..."
        sleep 1
    done
    info "Reboot now"
    sudo reboot
}
# ====== Main script ======
set -e
{
    set_hostname
    create_user_groups
    setup_cgroup
    add_udev_rules
    use_legacy_iptables
    add_authorized_keys

    info "Preparation completed. Reboot to take effect..."
    reboot_after 5
}