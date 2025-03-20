set -e

VENV_DIR=".server-venv"

echo "creating python virtual env"
python3 -m venv ${VENV_DIR}

echo "activating python virtual env"
source ${VENV_DIR}/bin/activate

if ! command -v "ansible-playbook --version" 2>&1 >/dev/null; then
    echo "installing ansible..."
    pip install ansible
fi

echo "running playbook"
ansible-playbook setup.yaml -i hosts.yaml $@
