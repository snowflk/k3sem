import yaml
import sys
import os

with open("config.yaml") as config_f:
    config = yaml.load(config_f, yaml.FullLoader)


def get_script_path():
    return os.path.dirname(os.path.realpath(sys.argv[0]))


def fatal(s):
    print("[ERROR]", s)
    sys.exit(1)


def is_master_node(node):
    return node.get("role", "worker") == "master"


def use_raspi_gpio(node):
    return node.get("raspiGpio", False)


nodes = config["cluster"]["nodes"]
cluster_cfg = config["cluster"]
master = None
for node in nodes:
    if is_master_node(node):
        master = node
        break
if master is None:
    fatal("No master node is found in config")


def _generate_script(env, script_file, out):
    header = "#!/bin/bash\n"
    for env_var in env.items():
        header += f"{env_var[0]}='{env_var[1]}'\n"

    with open(os.path.join(get_script_path(), "scripts", script_file), "r") as f:
        script = header + f.read()
    out_path = os.path.join(root, out)
    with open(out_path, "w") as f:
        f.write(script)
    return out_path


def generate_prepare_script(filename, node):
    prepare_env = {
        "K3SEM_USERNAME": cluster_cfg["user"],
        "K3SEM_USERPASS": cluster_cfg["password"],
        "K3SEM_GROUPNAME": cluster_cfg["usergroup"],
        "K3SEM_NODE_HOSTNAME": node["hostname"],
        "K3SEM_GPIO": 1 if use_raspi_gpio(node) else 0,
    }
    if "authorizedKey" in node["ssh"]:
        file = node["ssh"]["authorizedKey"]
        with open(file, "r") as f:
            pubkey = f.read().strip()
        prepare_env["K3SEM_SSH_PUBKEY"] = pubkey
    return _generate_script(prepare_env, "prepare.sh", filename)


def generate_install_script(filename, node):
    no_deploy = ' '.join([f"--no-deploy {s}" for s in cluster_cfg["noDeploy"]])
    tls_san = f"--tls-san {config['domain']}"
    install_exec = ' '.join([no_deploy, tls_san])
    install_env = {
        "K3SEM_USERNAME": cluster_cfg["user"],
        "K3SEM_GROUPNAME": cluster_cfg["usergroup"],
        "K3SEM_TOKEN": cluster_cfg["token"],
        "K3SEM_INSTALL_EXEC": install_exec
    }
    if not is_master_node(node):
        install_env["K3SEM_MASTER_URL"] = f"https://{master['ip']}:6443"
    else:
        install_env["K3SEM_IS_MASTER"] = 1
    return _generate_script(install_env, "install.sh", filename)


def generate_node_install_code(node, prepare_script, install_script):
    identity_flag = ""
    ssh = node["ssh"]
    hostname = node["hostname"]
    if "authorizedKey" in ssh and "privateKey" in ssh:
        identity_flag = f"-i {ssh['privateKey']}"
    code = f"""
# ======== {hostname} ==========
info "Bringing {hostname} to our cluster"
set +e
info "Connecting to {hostname} at IP: {node['ip']}"
until nc -vzw 2 {node['ip']} 22 &>/dev/null; do sleep 2; done
ssh {identity_flag} -t {ssh['user']}@{node['ip']} "$(<{prepare_script})"
info "Waiting for {hostname} to be up again..."
sleep 3
until nc -vzw 2 {node['ip']} 22 &>/dev/null; do sleep 2; done
info "{hostname} is online!"
info "Now running cluster installation script"
info "Connecting to {hostname} at IP:{node['ip']}"
set -e
ssh {identity_flag} -t {ssh['user']}@{node['ip']} "$(<{install_script})"
"""
    if is_master_node(node):
        code += f"""
info "Getting kubeconfig"
mkdir -p ~/.kube
scp {identity_flag} {cluster_cfg['user']}@{node['ip']}:/etc/rancher/k3s/k3s.yaml ~/.kube/config.tmp
info "Modifying kubeconfig"
sed "s/127.0.0.1/{node['ip']}/g" ~/.kube/config.tmp > ~/.kube/config
info "kubeconfig is now available at ~/.kube/config"

"""
    return code


if __name__ == '__main__':
    root = sys.argv[1]

    with open(os.path.join(get_script_path(), "scripts", "main_header.sh")) as f:
        main_code = f.read()

    master_prepare_file = generate_prepare_script(f"prepare_{master['hostname']}.sh", master)
    master_install_file = generate_install_script(f"install_{master['hostname']}.sh", master)
    main_code += generate_node_install_code(master, master_prepare_file, master_install_file)
    for node in nodes:
        if node["hostname"] == master["hostname"]:
            continue
        prepare_file = generate_prepare_script(f"prepare_{node['hostname']}.sh", node)
        install_file = generate_install_script(f"install_{node['hostname']}.sh", node)
        main_code += generate_node_install_code(node, prepare_file, install_file)

    with open(os.path.join(root, "all.sh"), "w") as f:
        f.write(main_code)
