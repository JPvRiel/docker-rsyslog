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
authorityKeyIdentifier = keyid:always,issuer
basicConstraints = CA:true
"

mkdir -p etc/pki/tls/private etc/pki/tls/certs
openssl req \
  -newkey rsa:2048 -nodes \
  -keyout etc/pki/tls/private/default_self_signed.key.pem  \
  -x509 -sha256 -days 3650 \
  -config <(echo "$local_openssl_config") \
  -out etc/pki/tls/certs/default_self_signed.cert.pem
openssl x509 -noout -text -in etc/pki/tls/certs/default_self_signed.cert.pem
