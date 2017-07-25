#!/bin/bash
set -e

mkdir -p etc/pki/tls/private etc/pki/tls/certs
openssl req \
  -newkey rsa:2048 -nodes \
  -keyout etc/pki/tls/private/default_self_signed.key.pem  \
  -x509 -days 365 \
  -out etc/pki/tls/certs/default_self_signed.cert.pem \
  -subj '/C=ZA/ST=Gauteng/L=Johannesburg/CN=docker-rsyslog'
