#!/bin/bash
# deploy-vm.sh
#
# A BASH script intended to be run from an instance of the Azure Cloud Shell for BASH.
#
# usage:
#   ./deploy-vm.sh <an optional five letter Azure resource naming prefix>
#
# This script will:
#   - create a private key pair for SSH in the executing user's $HOME directory
#   - create a virtual machine with a static IP that permits SSH over Port 2222
#   - create a .txt file that will contain a hosts entry for the new virtual machine
#   - copy $GHUsername and $CR_PAT to the /home/azureuser/.bashrc on the new machine
#   - clone a list of hardcoded repositories to the machine
#   - execute the install script from one of those repositories on the machine
#
# The script will output:
#   - the file path to the generated private key
#   - the file path to the generated hosts .txt file
#
# Prerequisites:
#   - git
#   - Azure CLI
#   - a GitHub Personal Access Token (classic) with the `repo` and `read:packages` scopes
#   - an environment variable, $CR_PAT, set to the value of that personal access token
#   - an environment variable, $GHUsername, set to the value of the user's GitHub username

set -e

SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
LOG_DIR="$HOME/logs"
LOG_FILE="$LOG_DIR/$SCRIPT_NAME.log"

REQUIRED_ENV_VARS="CR_PAT GHUsername"
REQUIRED_TOOLS="az git ssh-keygen"

# REQUIRED_REPOS="github.com/microsoft/Azure-Orbital-Space-SDK-QuickStarts github.com/microsoft/Azure-Orbital-Space-SDK-Host-Services github.com/microsoft/Azure-Orbital-Space-SDK-Client-Library-dotnet github.com/microsoft/Azure-Orbital-Space-SDK-Client-Library-python github.com/microsoft/Azure-Orbital-Space-SDK-Virtual-Test-Harness"
# INSTALL_SCRIPT_REPO="Azure-Orbital-Space-SDK-QuickStarts"

REQUIRED_REPOS="github.com/microsoft/Azure-Orbital-Space-SDK-QuickStarts github.com/microsoft/Azure-Orbital-Space-SDK-Host-Services github.com/microsoft/Azure-Orbital-Space-SDK-Client-Library-dotnet github.com/microsoft/Azure-Orbital-Space-SDK-Client-Library-python github.com/microsoft/Azure-Orbital-Space-SDK-Virtual-Test-Harness github.com/glennmusa/vm-from-cloud-shell"
INSTALL_SCRIPT_REPO="vm-from-cloud-shell"

PREFIX="space-sdk-demo"
REGION="eastus"
SUFFIX="$(date +%s)"

RG_NAME="$PREFIX-rg-$SUFFIX"
PIP_NAME="$PREFIX-pip-$SUFFIX"
VM_NAME="$PREFIX-vm-$SUFFIX"
SSH_KEY_NAME="$PREFIX-$SUFFIX-key"
SSH_KEY_PATH="$HOME/$SSH_KEY_NAME"
HOST_TXT_PATH="$HOME/$PREFIX-$SUFFIX-hosts-entry.txt"

info_log() {
  # log informational messages to stdout
  local TIMESTAMP
  TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")
  echo "[$SCRIPT_NAME] [INFO] $TIMESTAMP: $1"
  echo "[$SCRIPT_NAME] [INFO] $TIMESTAMP: $1" >>"$LOG_FILE"
}

error_log() {
  # log error messages to stderr
  local TIMESTAMP
  TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")
  echo "[$SCRIPT_NAME] [ERROR] $TIMESTAMP: $1" 1>&2
  echo "[$SCRIPT_NAME] [ERROR] $TIMESTAMP: $1" 1>&2 >>"$LOG_FILE"
}

exit_with_error() {
  # log a message to stderr and exit 1
  error_log "$1. Exiting."
  exit 1
}

check_prerequisites() {
  # checks for a value for each value in the $REQUIRED_ENV_VARS space separated list
  for var in $REQUIRED_ENV_VARS; do
    check_for_env_var "$var"
  done

  # checks for an exectuable for each value in the $REQUIRED_TOOLS space separated list
  for tool in $REQUIRED_TOOLS; do
    check_for_tool "$tool"
  done
}

check_for_env_var() {
  if [[ -n "$1" ]]; then
    info_log "\$$1 has a value"
  else
    exit_with_error "The environment variable $1 must be set. Set it with $1=\"your value\""
  fi
}

check_for_tool() {
  if command -v "$1" &>/dev/null; then
    info_log "$1 is installed"
  else
    exit_with_error "$1 could not be found. This script requires $1"
  fi
}

create_key_pair() {
  info_log "Creating SSH key pair at \"$SSH_KEY_PATH\"..."
  ssh-keygen -q -f "$SSH_KEY_PATH" -t rsa -b 4096 -N "" || exit_with_error "Unable to create SSH key pair at \"$SSH_KEY_PATH\"..."
}

deploy_vm() {
  info_log "Creating resource group \"$RG_NAME\"..."
  az group create \
    --location "$REGION" \
    --name "$RG_NAME"

  info_log "Creating public IP address \"$PIP_NAME\"..."
  az network public-ip create \
    --resource-group "$RG_NAME" \
    --name "$PIP_NAME" \
    --version "IPv4" \
    --sku "Standard" \
    --zone 1 2 3

  info_log "Creating virtual machine \"$VM_NAME\"..."
  az vm create \
    --resource-group "$RG_NAME" \
    --name "$VM_NAME" \
    --image "Canonical:0001-com-ubuntu-server-focal:20_04-lts:20.04.202302090" \
    --admin-username "azureuser" \
    --ssh-key-values "$SSH_KEY_PATH.pub" \
    --public-ip-address "$PIP_NAME" \
    --os-disk-size-gb "80" \
    --size "Standard_E4s_v5"

  info_log "Opening port 2222 on virtual machine \"$VM_NAME\"..."
  az vm open-port \
    --resource-group "$RG_NAME" \
    --name "$VM_NAME" \
    --port "2222"

  info_log "Setting port 2222 as the SSH port on virtual machine \"$VM_NAME\"..."
  az vm run-command invoke \
    --resource-group "$RG_NAME" \
    --name "$VM_NAME" \
    --command-id "RunShellScript" \
    --scripts "echo 'Port 2222' | sudo tee -a /etc/ssh/sshd_config && sudo service sshd restart"
}

create_hosts_entry() {
  info_log "Retrieving IP Address virtual machine \"$VM_NAME\"..."
  public_ip=$(az vm list-ip-addresses \
    --resource-group "$RG_NAME" \
    --name "$VM_NAME" \
    --query "[].virtualMachine.network.publicIpAddresses[0].ipAddress" \
    --output "tsv")
  if [[ -n "$public_ip" ]]; then
    info_log "Retrieved IP Address \"$public_ip\" from virtual machine \"$VM_NAME\""
  else
    exit_with_error "The IP Address from could not be retrieved from virtual machine \"$VM_NAME\""
  fi

  info_log "Creating a hosts entry for the new virtual machine at \"$HOST_TXT_PATH\"..."
  cat <<EOF >>"$HOST_TXT_PATH"
Host $VM_NAME
  Hostname $public_ip
  User azureuser
  Port 2222
  IdentityFile ~/Downloads/$SSH_KEY_NAME
EOF
}

copy_github_credentials() {
  info_log "Copying GitHub username and PAT to virtual machine \"$VM_NAME\"..."
  az vm run-command invoke \
    --resource-group "$RG_NAME" \
    --name "$VM_NAME" \
    --command-id "RunShellScript" \
    --scripts "echo export GHUsername=\"$GHUsername\" >> /home/azureuser/.bashrc && echo export CR_PAT=\"$CR_PAT\" >> /home/azureuser/.bashrc"
}

clone_repositories() {
  info_log "Cloning repositories on virtual machine \"$VM_NAME\"..."
  az vm run-command invoke \
    --resource-group "$RG_NAME" \
    --name "$VM_NAME" \
    --command-id "RunShellScript" \
    --scripts "cd /home/azureuser && for repo in $REQUIRED_REPOS; do git clone "https://$GHUsername:$CR_PAT@\$repo.git"; done"
}

run_prereqs_install() {
  info_log "Running Space SDK prerequisites installation script on virtual machine \"$VM_NAME\"..."
  info_log "This may take a few minutes..."
  az vm run-command invoke \
    --resource-group "$RG_NAME" \
    --name "$VM_NAME" \
    --command-id "RunShellScript" \
    --scripts "cd /home/azureuser/$INSTALL_SCRIPT_REPO && ./demo-vm/install.sh" \
    --only-show-errors
  # --scripts "cd /home/azureuser/$INSTALL_SCRIPT_REPO && ./demo-vm/install-azure-space-sdk-prereqs.sh" \
  # --only-show-errors
}

output_paths_to_user() {
  info_log "Success! You'll need to download two files to your Downloads directory:"
  info_log "The private key at: \"$SSH_KEY_PATH\""
  info_log "The host file entry at: \"$HOST_TXT_PATH\""
}

reset_log() {
  # removes any log from previous runs
  if [[ -f "$LOG_FILE" ]]; then
    rm "$LOG_FILE"
  fi

  # creates a new log for this run
  mkdir -p "$LOG_DIR"
  chmod -R 777 "$LOG_DIR"
  touch "$LOG_FILE"
  chmod 777 "$LOG_FILE"
}

main() {
  reset_log
  info_log "Start"
  check_prerequisites
  create_key_pair
  deploy_vm
  create_hosts_entry
  copy_github_credentials
  clone_repositories
  # run_prereqs_install
  info_log "Finished"
  output_paths_to_user
}

main
