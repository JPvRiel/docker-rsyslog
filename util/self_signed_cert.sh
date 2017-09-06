#!/bin/bash
set -e

if [ -z "$1" ]; then
  hostname="$HOSTNAME"
else
  hostname="$1"
fi

local_openssl_config="
[ req ]
prompt = no
distinguished_name = req_distinguished_name
x509_extensions = san_self_signed
[ req_distinguished_name ]
CN=$hostname
[ san_self_signed ]
subjectAltName = DNS:$hostname, DNS:localhost
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always, issuer
basicConstraints = CA:true
keyUsage = nonRepudiation, digitalSignature, keyEncipherment, dataEncipherment, keyCertSign, cRLSign
extendedKeyUsage = serverAuth, clientAuth, timeStamping
"

mkdir -p \
  etc/pki/tls/private \
  etc/pki/tls/certs \
  etc/pki/ca-trust/source/anchors/
openssl req \
  -newkey rsa:2048 -nodes \
  -keyout etc/pki/tls/private/default_self_signed.key.pem  \
  -x509 -sha256 -days 3650 \
  -config <(echo "$local_openssl_config") \
  -out etc/pki/tls/certs/default_self_signed.cert.pem
openssl x509 -noout -text -in etc/pki/tls/certs/default_self_signed.cert.pem

# Copy (don't symlink) as docker build context for a test image undestandably blocks access outside context
mkdir -p \
  test/tls_x509/private \
  test/tls_x509/certs
cp etc/pki/tls/private/default_self_signed.key.pem test/tls_x509/private/
cp etc/pki/tls/certs/default_self_signed.cert.pem test/tls_x509/certs/
