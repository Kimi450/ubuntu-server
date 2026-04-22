#!/usr/bin/env bash
# Bootstraps a Python virtualenv, installs Ansible and required Galaxy
# collections, and runs the site playbook. Any arguments are forwarded
# to ansible-playbook (e.g. -vvv, --check, --limit home-throwaway).
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
cd "${SCRIPT_DIR}"

VENV_DIR="${VENV_DIR:-.server-venv}"
PLAYBOOK="${PLAYBOOK:-site.yaml}"
INVENTORY="${INVENTORY:-hosts.yaml}"

if [[ ! -d "${VENV_DIR}" ]]; then
    echo "creating python virtual env in ${VENV_DIR}"
    python3 -m venv "${VENV_DIR}"
fi

echo "activating python virtual env"
# shellcheck disable=SC1091
source "${VENV_DIR}/bin/activate"

if ! command -v ansible-playbook >/dev/null 2>&1; then
    echo "installing ansible..."
    pip install --upgrade pip
    pip install ansible
fi

if [[ -f requirements.yml ]]; then
    echo "installing ansible collections"
    ansible-galaxy collection install -r requirements.yml
fi

echo "running playbook ${PLAYBOOK}"
exec ansible-playbook "${PLAYBOOK}" -i "${INVENTORY}" "$@"
