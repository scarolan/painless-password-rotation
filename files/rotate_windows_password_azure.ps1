# Script for rotating passwords on local accounts.
# Set VAULT_ADDR as an environment variable. Do not set VAULT_TOKEN.
# Enable an Azure Managed Identity for this machine.
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
$HOSTNAME = $env:computername

# Get token from Azure metadata service
$JWT = (Invoke-RestMethod -Uri 'http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https%3A%2F%2Fmanagement.azure.com%2F' -Headers @{Metadata="true"}).access_token

# Get subsciption ID
$SUBSCRIPTION = (Invoke-RestMethod -Uri 'http://169.254.169.254/metadata/instance?api-version=2017-08-01' -Headers @{Metadata="true"}).compute.subscriptionId
Write-Output $SUBSCRIPTION

# Get resource group
$RG = (Invoke-RestMethod -Uri 'http://169.254.169.254/metadata/instance?api-version=2017-08-01' -Headers @{Metadata="true"}).compute.resourceGroupName
Write-Output $RG

# Get VM name
$VMNAME = (Invoke-RestMethod -Uri 'http://169.254.169.254/metadata/instance?api-version=2017-08-01' -Headers @{Metadata="true"}).compute.name
Write-Output $VMNAME

# Login to Vault with Azure managed identity JWT, to get a Vault token
Write-Output "Logging in to Vault with JWT"
Write-Output "POST ${VAULT_ADDR}/v1/auth/azure/login"
$VAULT_TOKEN = (Invoke-RestMethod -Method POST -Body "{`"role`":`"rotate-windows`",
                                                       `"subscription_id`":`"${SUBSCRIPTION}`",
                                                       `"resource_group_name`":`"${RG}`",
                                                       `"vm_name`":`"${VMNAME}`",
                                                       `"jwt`":`"${JWT}`"}" -Uri ${VAULT_ADDR}/v1/auth/azure/login).auth.client_token

# Fetch a new password from Vault. Adjust the options to fit your requirements.
$NEWPASS = (Invoke-RestMethod -Headers @{"X-Vault-Token" = ${VAULT_TOKEN}} -Method POST -Body "{`"length`":`"12`",`"symbols`":`"0`"}" -Uri ${VAULT_ADDR}/v1/gen/password).data.value

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
