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

# ====== Variables ======
USERNAME=${K3SEM_USERNAME}
GROUPNAME=${K3SEM_GROUPNAME}
IS_MASTER=${K3SEM_IS_MASTER}
INSTALL_EXEC=${K3SEM_INSTALL_EXEC}
TOKEN=${K3SEM_TOKEN}
MASTER_URL=${K3SEM_MASTER_URL}
validate_env()
{
    if [[ -z "$2" ]]; then
          fatal "$1 can not be empty"
    fi
}
validate_env K3SEM_USERNAME ${USERNAME}
validate_env K3SEM_GROUPNAME ${GROUPNAME}
validate_env K3SEM_TOKEN ${TOKEN}

# ====== Install dependencies ======
install_k3s()
{
    if [[ -n "$IS_MASTER" ]]; then
        info "Installing k3s for master"
        curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="$INSTALL_EXEC" K3S_TOKEN="$TOKEN" sh -
        sudo chown ${USERNAME}:${GROUPNAME} /etc/rancher/k3s/k3s.yaml
        sudo -u ${USERNAME} echo "alias kubectl='k3s kubectl'" >> "/home/$USERNAME/.bashrc"
    else
        info "Installing k3s for worker"
        info "Master URL: $MASTER_URL"
        info "Token: $TOKEN"
        curl -sfL https://get.k3s.io | K3S_URL="$MASTER_URL" K3S_TOKEN="$TOKEN" sh -
    fi
}
# ====== Main script ======
set -e
{
    install_k3s
}