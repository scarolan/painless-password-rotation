#!/bin/bash
# Script for rotating passwords on the local machine.
# Make sure and set VAULT_TOKEN and VAULT_ADDR as environment variables.
# Cron jobs can read these env vars from /etc/environment

# Check for usage
if [[ $# -ne 1 ]]; then
  echo "You must include the username of the user you wish to update"
  echo "$0 root"
  exit 1
fi

USERNAME=$1

# Renew our token before we do anything else.
curl -sS --fail -X POST -H "X-Vault-Token: $VAULT_TOKEN" ${VAULT_ADDR}/v1/auth/token/renew-self | grep -q 'lease_duration'
retval=$?
if [[ $retval -ne 0 ]]; then
  echo "Error renewing Vault token lease."
fi

# Fetch a new passphrase from Vault. Adjust the options to fit your requirements.
NEWPASS=$(curl -sS --fail -X POST -H "X-Vault-Token: $VAULT_TOKEN" -H "Content-Type: application/json" --data '{"words":"5","separator":"-"}'  ${VAULT_ADDR}/v1/gen/passphrase | grep -Po '"value":.*?[^\\]"' | awk -F ':' '{print $2}' | tr -d '"')
# Fetch a new password from Vault. Adjust the options to fit your requirements.
#NEWPASS=$(curl -sS --fail -X POST -H "X-Vault-Token: $VAULT_TOKEN" -H "Content-Type: application/json" --data '{"length":"36","symbols":"0"}'  ${VAULT_ADDR}/v1/gen/password | grep -Po '"value":.*?[^\\]"' | awk -F ':' '{print $2}' | tr -d '"')

# Create the JSON payload to write to Vault's K/V store. Keep the last 12 versions of this credential.
JSON="{ \"options\": { \"max_versions\": 12 }, \"data\": { \"$USERNAME\": \"$NEWPASS\" } }"

# First commit the new password to vault, then capture the exit status.
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
