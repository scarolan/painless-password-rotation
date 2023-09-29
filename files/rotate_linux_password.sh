#!/bin/bash
USAGE=$(cat << USAGE
Generates a random password or passphrase via vault, stores it there and changes the password for a user
REQUIRED OPTIONS:
-u USERNAME = User to change the password for
-t TYPE = Type of secret to create, this takes either password or passphrase
PASSWORD OPTIONS:
-l PW_LENGTH = Length (int)
-d PW_DIGITS = Amount of digits (int)
-s PW_SYMBOLS = Amount of symbols (int)
-c PW_ALLOW_UPPERCASE = Allow uppercase characters (bool)
-r PW_ALLOW_REPEAT = Allow repetition inside the password (bool)
PASSPHRASE OPTIONS:
-w PH_WORDS = Amount of words (int)
-p PH_SEPARATOR = Separator for the words (string)
USAGE
)

# define default values
PW_LENGTH=64
PW_DIGITS=10
PW_SYMBOLS=10
PW_ALLOW_UPPERCASE=true
PW_ALLOW_REPEAT=true
PH_WORDS=6
PH_SEPARATOR="-"

# read options per getopts
while getopts 'u:t:l:d:s:c:r:w:p:' OPTION
do
  case ${OPTION} in
    u)  USERNAME="${OPTARG}"
        ;;
    t)  TYPE="${OPTARG}"
        ;;
    l)  PW_LENGTH="${OPTARG}"
        ;;
    d)  PW_DIGITS="${OPTARG}"
        ;;
    s)  PW_SYMBOLS="${OPTARG}"
        ;;
    c)  PW_ALLOW_UPPERCASE="${OPTARG}"
        ;;
    r)  PW_ALLOW_REPEAT="${OPTARG}"
        ;;
    w)  PH_WORDS="${OPTARG}"
        ;;
    p)  PH_SEPARATOR="${OPTARG}"
        ;;
    \?) printf "%b" "${USAGE}"
        exit 1
        ;;
  esac
done
# check if there is at least one parameter set, otherwise print usage and exit
[ $OPTIND -eq 1 ] && { printf "%b" "${USAGE}"; exit 1 ; }
shift $((OPTIND -1))
# check if -u is specified, otherwise print usage and exit
[ -z ${USERNAME} ] && { printf "%b" "${USAGE}"; exit 1 ; }
# check if -t is specified, otherwise print usage and exit
[ -z ${TYPE} ] && { printf "%b" "${USAGE}"; exit 1 ; }
# check if -t is either password or passphrase, otherwise print usage and exit
[ "${TYPE}" != "password" ] && [ "${TYPE}" != "passphrase" ] && { printf "%b" "${USAGE}"; exit 1 ; }

# Functions
function output_error() {
  printf "%b" "ERROR $@\n" 1>&2;
}

function renew_token() {
  if [ -z {"$VAULT_NAMESPACE"+x} ]
  then
    curl -sS --fail -X POST -H "X-Vault-Token: ${VAULT_TOKEN}" ${VAULT_ADDR}/v1/auth/token/renew-self > /dev/null 2>&1
  else
    curl -sS --fail -X POST -H "X-Vault-Token: ${VAULT_TOKEN}" -H "X-Vault-Namespace: ${VAULT_NAMESPACE}" ${VAULT_ADDR}/v1/auth/token/renew-self > /dev/null 2>&1
  fi
  if [ $? -ne 0 ]; then
    return 1
  else
    return 0
  fi
}

function generate_password() {
  DATA=$(jq --null-input \
    --arg length "${PW_LENGTH}" \
    --arg digits "${PW_DIGITS}" \
    --arg symbols "${PW_SYMBOLS}" \
    --arg allow_uppercase "${PW_ALLOW_UPPERCASE}" \
    --arg allow_repeat "${PW_ALLOW_REPEAT}" \
    '{"length": $length, "digits": $digits, "symbols": $symbols, "allow_uppercase": $allow_uppercase, "allow_repeat": $allow_repeat}')
  if [ -z {"$VAULT_NAMESPACE"+x} ]
  then
    local REQUEST=$(curl -sS --fail -X POST -H "X-Vault-Token: ${VAULT_TOKEN}" -H "Content-Type: application/json" --data "${DATA}" ${VAULT_ADDR}/v1/gen/password 2> /dev/null)
  else
    local REQUEST=$(curl -sS --fail -X POST -H "X-Vault-Token: ${VAULT_TOKEN}" -H "X-Vault-Namespace: ${VAULT_NAMESPACE}" -H "Content-Type: application/json" --data "${DATA}" ${VAULT_ADDR}/v1/gen/password 2> /dev/null)
  fi
  if [ $? -ne 0 ]; then
    return 1
  else
    NEWPASS=$(echo "${REQUEST}" | jq -r '.data|.value')
    printf "%b" "${NEWPASS}"
    return 0
  fi
}

function generate_passphrase() {
  DATA=$(jq --null-input \
    --arg words "${PH_WORDS}" \
    --arg separator "${PH_SEPARATOR}" \
    '{"words": $words, "separator": $separator}')
  if [ -z {"$VAULT_NAMESPACE"+x} ]
  then
    local REQUEST=$(curl -sS --fail -X POST -H "X-Vault-Token: ${VAULT_TOKEN}" -H "Content-Type: application/json" --data "${DATA}" ${VAULT_ADDR}/v1/gen/passphrase 2> /dev/null)
  else
    local REQUEST=$(curl -sS --fail -X POST -H "X-Vault-Token: ${VAULT_TOKEN}" -H "X-Vault-Namespace: ${VAULT_NAMESPACE}" -H "Content-Type: application/json" --data "${DATA}" ${VAULT_ADDR}/v1/gen/passphrase 2> /dev/null)
  fi
  if [ $? -ne 0 ]; then
    return 1
  else
    NEWPASS=$(echo "${REQUEST}" | jq -r '.data|.value')
    printf "%b" "${NEWPASS}"
    return 0
  fi
}

function store_credentials_vault() {
  # Create the JSON payload to write to vault
  local JSON=$(jq --null-input \
    --arg username "${USERNAME}" \
    --arg password "${NEWPASS}" \
    '{"options": {"max_versions": 12}, "data": {($username): ($password)}}')
  # Commit the credentials to vault
  if [ -z {"$VAULT_NAMESPACE"+x} ]
  then
    curl -sS --fail -X POST -H "X-Vault-Token: ${VAULT_TOKEN}" --data "${JSON}" ${VAULT_ADDR}/v1/systemcreds/data/linux/$(hostname)/${USERNAME}_creds > /dev/null 2>&1
  else
    curl -sS --fail -X POST -H "X-Vault-Token: ${VAULT_TOKEN}" -H "X-Vault-Namespace: ${VAULT_NAMESPACE}" --data "${JSON}" ${VAULT_ADDR}/v1/systemcreds/data/linux/$(hostname)/${USERNAME}_creds > /dev/null 2>&1
  fi
  if [ $? -ne 0 ]; then
    return 1
  else
    return 0
  fi
}

function update_password() {
  printf "%b" "${USERNAME}:${NEWPASS}" | sudo chpasswd > /dev/null 2>&1
  if [ $? -ne 0 ]; then
    return 1
  else
    return 0
  fi
}

# Main

# Make sure the user exists on the local system.
if ! [[ $(id "${USERNAME}") ]]; then
  output_error "${USERNAME} does not exist!"
  exit 2
fi

# Renew our token before we do anything else.
renew_token \
  || { output_error "Token renewal failed" ; exit 1 ; } \
  && { printf "%b" "Token renewed\n" ; }

if [ "${TYPE}" == "password" ]
then
  # Generate new password via vault
  NEWPASS=$(generate_password) \
  || { output_error "Failed to create new random password via vault" ; exit 1 ; } \
  && { printf "%b" "New random password generated\n" ; }
else
  # Generate new passphrase via vault
  NEWPASS=$(generate_passphrase) \
    || { output_error "Failed to create new random passphrase via vault" ; exit 1 ; } \
    && { printf "%b" "New random passphrase generated\n" ; }
fi

# Store password inside vault
store_credentials_vault \
  || { output_error "Failed to store the credentials for ${USERNAME} inside vault. Not updating the local password" ; exit 1 ; } \
  && { printf "%b" "New credentials for ${USERNAME} stored\n" ; }

# Update local password
update_password \
  || { output_error "Failed to update the password for ${USERNAME}" ; exit 1 ; } \
  && { printf "%b" "Password for ${USERNAME} changed\n" ; NEWPASS="" ; exit 0 ; }
