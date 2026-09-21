#!/bin/sh
# Creates a self-signed code-signing identity called "HandsFreeNotch Dev" in the login keychain.
# scripts/bundle.sh picks it up automatically, so the Accessibility grant survives rebuilds.
set -eu
if security find-identity -v -p codesigning | grep -q "HandsFreeNotch Dev"; then
  echo "identity already exists"; exit 0
fi
TMP="$(mktemp -d)"
cat > "$TMP/cs.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = HandsFreeNotch Dev
[ext]
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
basicConstraints = critical, CA:false
subjectKeyIdentifier = hash
CNF
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$TMP/cs.cnf" -keyout "$TMP/cs.key" -out "$TMP/cs.crt" 2>/dev/null
openssl pkcs12 -export -inkey "$TMP/cs.key" -in "$TMP/cs.crt" -out "$TMP/cs.p12" -passout pass:hfn -legacy 2>/dev/null \
  || openssl pkcs12 -export -inkey "$TMP/cs.key" -in "$TMP/cs.crt" -out "$TMP/cs.p12" -passout pass:hfn
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
security import "$TMP/cs.p12" -k "$KEYCHAIN" -P hfn -T /usr/bin/codesign -T /usr/bin/security
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$TMP/cs.crt"
rm -rf "$TMP"
security find-identity -v -p codesigning | grep "HandsFreeNotch Dev"
