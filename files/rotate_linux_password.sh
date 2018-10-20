#!/bin/bash
# Script for rotating passwords on the local machine.
# Make sure and store VAULT_TOKEN and VAULT_ADDR as environment variables.

# Check for usage
if [[ $# -ne 1 ]]; then
  echo "Please provide a username.  Usage:"
  echo "$0 root"
  exit 1
fi

USERNAME=$1

# Make sure the user exists on the local system.
if ! [[ $(id $USERNAME) ]]; then
  echo "$USERNAME does not exist!"
  exit 1
fi

# Renew our token before we do anything else.
curl -sS --fail -X POST -H "X-Vault-Token: $VAULT_TOKEN" ${VAULT_ADDR}/v1/auth/token/renew-self | grep -q 'lease_duration'
retval=$?
if [[ $retval -ne 0 ]]; then
  echo "Error renewing Vault token lease."
fi

# If you have the jq package installed, this is a lot cleaner...
NEWPASS=$(curl -sS --fail -X POST -H "X-Vault-Token: $VAULT_TOKEN" -H "Content-Type: application/json" --data '{"words":"4","separator":"-"}'  ${VAULT_ADDR}/v1/gen/passphrase | jq -r '.data|.value')

# Otherwise you can use grep and awk:

# Fetch a new passphrase from Vault
# NEWPASS=$(curl -sS --fail -X POST -H "X-Vault-Token: $VAULT_TOKEN" -H "Content-Type: application/json" --data '{"words":"4","separator":"-"}'  ${VAULT_ADDR}/v1/gen/passphrase | grep -Po '"value":.*?[^\\]"' | awk -F ':' '{print $2}' | tr -d '"')

# Fetch a new password from Vault
#NEWPASS=$(curl -sS --fail -X POST -H "X-Vault-Token: $VAULT_TOKEN" -H "Content-Type: application/json" --data '{"length":"36","symbols":"0"}'  ${VAULT_ADDR}/v1/gen/password | grep -Po '"value":.*?[^\\]"' | awk -F ':' '{print $2}' | tr -d '"')

# Create the JSON payload to write to vault
JSON="{ \"options\": { \"max_versions\": 12 }, \"data\": { \"${USERNAME}\": \"$NEWPASS\" } }"

# First commit the new password to vault, then capture the exit status
curl -sS --fail -X POST -H "X-Vault-Token: $VAULT_TOKEN" --data "$JSON" ${VAULT_ADDR}/v1/systemcreds/data/linux/$(hostname)/${USERNAME}_creds | grep -q 'request_id'
retval=$?
if [[ $retval -eq 0 ]]; then
  # After we save the password to vault, update it on the instance
  echo "$USERNAME:$NEWPASS" | sudo chpasswd
  retval=$?
    if [[ $retval -eq 0 ]]; then
      echo -e "${USERNAME}'s password was stored in Vault and updated locally."
    else
      echo "Error: ${USERNAME}'s password was stored in Vault but *not* updated locally."
    fi
else
  echo "Error saving new password to Vault. Local password will remain unchanged."
  exit 1
fi
