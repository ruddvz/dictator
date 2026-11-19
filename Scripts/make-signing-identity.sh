#!/usr/bin/env bash
# Creates a self-signed "Dictator Local Signing" code-signing identity in the login keychain, so
# local builds keep their Accessibility permission across rebuilds. Run once per Mac.
set -euo pipefail

name="Dictator Local Signing"
if security find-identity -v -p codesigning | grep -q "\"$name\""; then
  echo "$name already exists."
  exit 0
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
cat > "$work/cfg" <<EOF
[req]
distinguished_name = dn
prompt = no
[dn]
CN = $name
[ext]
basicConstraints = critical,CA:true
keyUsage = critical,digitalSignature,keyCertSign,cRLSign
extendedKeyUsage = critical,codeSigning
EOF
password="$(/usr/bin/openssl rand -hex 12)"
/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$work/cfg" -extensions ext \
  -keyout "$work/key.pem" -out "$work/cert.pem" 2>/dev/null
/usr/bin/openssl pkcs12 -export -inkey "$work/key.pem" -in "$work/cert.pem" -name "$name" \
  -out "$work/id.p12" -passout "pass:$password"
security import "$work/id.p12" -k "$HOME/Library/Keychains/login.keychain-db" -P "$password" -T /usr/bin/codesign
security add-trusted-cert -r trustRoot -p codeSign -k "$HOME/Library/Keychains/login.keychain-db" "$work/cert.pem"
if ! security find-identity -v -p codesigning | grep -q "\"$name\""; then
  echo "Could not validate $name for local code signing." >&2
  exit 1
fi
echo "Created $name. Package Dictator, then allow it once more in Privacy & Security → Accessibility."
