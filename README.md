# Painless Password Rotation with HashiCorp Vault
This guide demonstrates an automated password rotation workflow using HashiCorp Vault and a simple Bash or Powershell script. These scripts could be run in a cron job or scheduled task to dynamically update local system passwords on a regular basis.

NOTE: This is *not* the be-all and end-all of password rotation. It is also not a PAM tool. It can do the following:

* Rotate local system passwords on a regular basis
* Allow systems to rotate their own passwords
* Store login credentials securely in Vault
* Ensure that passwords meet complexity requirements
* Require users to check credentials out of Vault

In this guide you'll have three terminal windows open. One for running Vault, a second for entering Vault CLI commands, and one for your remote Linux server. The scripts run from the remote GCP instance and connect to Vault to update their stored credentials.

## Prerequisites
* HashiCorp Vault cluster that is reachable from your server instances. (Inbound TCP port 8200 to Vault)
* Seth Vargo's most excellent [vault-secrets-gen plugin](https://github.com/sethvargo/vault-secrets-gen)
* Vault command line configured for your Vault cluster. (Hint: You need to set VAULT_ADDR and VAULT_TOKEN environment variables.)
* A version 2 K/V secrets backend mounted at `systemcreds`

### Step 1: Configure Your Policies
The following policies allow 'create' and 'update' rights. This essentially creates a one way door, whereby systems can update their passwords but not read them from Vault.
```
vault policy write rotate-linux policies/rotate-linux.hcl
vault policy write rotate-windows policies/rotate-windows.hcl
```

### Step 2: Generate a token for each server
```
vault token create -period 24h -policy rotate-linux
vault token create -period 24h -policy rotate-windows
```

### Step 3: Put the token onto each instance
Append the following lines to /etc/environment.
```
export VAULT_ADDR=https://your_vault.server.com:8200
export VAULT_TOKEN=4ebeb7f9-d691-c53f-d8d0-3c3d500ddda8
```
Windows users should set these as system environment variables.

### Step 4: Run the script
```bash
./rotate-linux-password.sh root
```

```powershell
.\rotate-windows-password.sh Administrator
```

### Step 5: Log onto the Vault UI and verify that the password was saved successfully


## Extras

### Attempt to read creds from a system.  (this won't work from a client machine)
curl -sS --fail -X GET -H  "X-Vault-Token: $VAULT_TOKEN" https://sean-vault0.hashidemos.io:8200/v1/systemcreds/data/linux/heritagebox/root_creds

### Show older versions of the credentials
```
curl -X GET -H "X-Vault-Token: $VAULT_TOKEN" ${VAULT_ADDR}/v1/systemcreds/data/linux/heritagebox/root_creds?version=5 | jq .
curl -X GET -H "X-Vault-Token: $VAULT_TOKEN" ${VAULT_ADDR}/v1/systemcreds/data/linux/heritagebox/root_creds?version=1 | jq .
```