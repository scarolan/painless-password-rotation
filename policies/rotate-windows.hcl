path "systemcreds/data/windows/*" {
  capabilities = ["create", "update"]
}

# Allow hosts to generate new passphrases
path "gen/passphrase" {
  capabilities = ["create", "update"]
}

# Allow hosts to generate new passwords
path "gen/password" {
  capabilities = ["create", "update"]
}