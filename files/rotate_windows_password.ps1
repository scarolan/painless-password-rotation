# Script for rotating passwords on local accounts.
# Make sure and set VAULT_TOKEN and VAULT_ADDR as environment variables.
# You may run this script as a scheduled task for regular rotation.

# Check for correct usage
Param(
    [Parameter(Mandatory=$True,Position=1)]
    [string]$USERNAME
)

# Make sure the user exists on the local system.
if (-not (Get-LocalUser $USERNAME)) {
    throw '$USERNAME does not exist!'
}

# Use TLS
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Import some environment variables.
$VAULT_ADDR = $env:VAULT_ADDR
$VAULT_TOKEN = $env:VAULT_TOKEN
$HOSTNAME = $env:computername

# Renew our token before we do anything else.
Invoke-RestMethod -Headers @{"X-Vault-Token" = ${VAULT_TOKEN}} -Method POST -Uri ${VAULT_ADDR}/v1/auth/token/renew-self
if(-Not $?)
{
   Write-Output "Error renewing Vault token lease."
}

# Fetch a new passphrase from Vault. Adjust the options to fit your requirements.
#$NEWPASS = (Invoke-RestMethod -Headers @{"X-Vault-Token" = ${VAULT_TOKEN}} -Method POST -Body "{`"words`":`"4`",`"separator`":`"-`"}" -Uri ${VAULT_ADDR}/v1/gen/passphrase).data.value

# Fetch a new password from Vault. Adjust the options to fit your requirements.
$NEWPASS = (Invoke-RestMethod -Headers @{"X-Vault-Token" = ${VAULT_TOKEN}} -Method POST -Body "{`"length`":`"36`",`"symbols`":`"0`"}" -Uri ${VAULT_ADDR}/v1/gen/password).data.value

# Convert into a SecureString
$SECUREPASS = ConvertTo-SecureString $NEWPASS -AsPlainText -Force

# Create the JSON payload to write to Vault's K/V store. Keep the last 12 versions of this credential.
$JSON="{ `"options`": { `"max_versions`": 12 }, `"data`": { `"$USERNAME`": `"$NEWPASS`" } }"

# First commit the new password to vault, then change it locally.
Invoke-RestMethod -Headers @{"X-Vault-Token" = ${VAULT_TOKEN}} -Method POST -Body $JSON -Uri ${VAULT_ADDR}/v1/systemcreds/data/windows/${HOSTNAME}/${USERNAME}_creds
if($?) {
   Write-Output "Vault updated with new password."
   $UserAccount = Get-LocalUser -name $USERNAME
   $UserAccount | Set-LocalUser -Password $SECUREPASS
   if($?) {
       Write-Output "${USERNAME}'s password was stored in Vault and updated locally."
   }
   else {
       Write-Output "Error: ${USERNAME}'s password was stored in Vault but *not* updated locally."
   }
}
else {
    Write-Output "Error saving new password to Vault. Local password will remain unchanged."
}