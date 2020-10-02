#!/bin/bash
set -e
# ====== prepare ========
SCRIPTDIRPATH="$( cd "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
rm -rf "$SCRIPTDIRPATH/generated"
mkdir "$SCRIPTDIRPATH/generated"

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

greeting()
{
    echo "
 _  __ ____    _____  ______  __  __
| |/ /|___ \  / ____||  ____||  \/  |
| ' /   __) || (___  | |__   | \  / |
|  <   |__ <  \___ \ |  __|  | |\/| |
| . \  ___) | ____) || |____ | |  | |
|_|\_\|____/ |_____/ |______||_|  |_|

               v1.0
"
}
# ======= main =======0
{
    greeting
    info "Generating installation scripts"
    python "$SCRIPTDIRPATH/generate.py" "$SCRIPTDIRPATH/generated"
    info "Cluster installation process started"
    sh "$SCRIPTDIRPATH/generated/all.sh"
    info "Cluster installation completed. Enjoy!"
}
