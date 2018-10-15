# Allows admins to read passwords.
path "systemcreds/*" {
  capabilities = ["list"]
}
path "systemcreds/data/windows/*" {
  capabilities = ["list", "read"]
}