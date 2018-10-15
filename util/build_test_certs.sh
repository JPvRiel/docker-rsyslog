#!/bin/bash
set -e

function local_openssl_config {
echo -n "\
[ req ]
prompt = no
distinguished_name = req_distinguished_name
[ req_distinguished_name ]
CN=$hostname
[ usr ]
subjectAltName = DNS:$hostname, DNS:localhost
basicConstraints = CA:FALSE
keyUsage = nonRepudiation, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth, clientAuth, codeSigning, emailProtection
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid
[ ca_self_signed ]
subjectAltName = DNS:$hostname
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always, issuer
basicConstraints = CA:true
keyUsage = nonRepudiation, digitalSignature, keyEncipherment, dataEncipherment, keyCertSign, cRLSign
extendedKeyUsage = serverAuth, clientAuth, timeStamping
[ ca ]
default_ca = minimal_ca
[ minimal_ca ]
private_key = util/ca/test_ca.key.pem
certificate = util/ca/test_ca.cert.pem
serial = util/ca/index.txt
database = util/ca/serial.txt
new_certs_dir = util/ca/certs
default_md = default
x509_extensions = usr
policy = policy_anything
default_days = 3650
[ policy_anything ]
countryName             = optional
stateOrProvinceName     = optional
localityName            = optional
organizationName        = optional
organizationalUnitName  = optional
commonName              = supplied
emailAddress            = optional
"
}

function ca_signed_cert {
  hostname="$1"
  echo -e "\n\n# hostname: $hostname"
  key="$2/$1.key.pem"
  echo "# key: $key"
  cert="$3/$1.cert.pem"
  echo "# cert: $cert"
  openssl req \
    -config <(local_openssl_config) \
    -newkey rsa:2048 -nodes \
    -keyout "$key"  \
    -sha256 \
    -out "util/ca/csr/$hostname.csr"
  openssl ca \
    -config  <(local_openssl_config) \
    -batch \
    -in "util/ca/csr/$hostname.csr" \
    -extensions usr \
    -out "$cert"
  #openssl x509 -noout -text -certopt no_header,no_version,no_serial,no_signame,no_validity,no_issuer,no_pubkey,no_sigdump,no_aux -in "$cert"
}

rm -rf util/ca/*
rm -rf test/tls_x509/*
mkdir -p \
  util/ca/certs \
  util/ca/csr \
  usr/local/etc/pki/test \
  etc/pki/ca-trust/source/anchors \
  test/tls_x509/private \
  test/tls_x509/certs

# Create test CA
echo -n > 'util/ca/serial.txt'
#echo -n > 'util/ca/index.txt'
hostname=test_ca
openssl req \
  -config <(local_openssl_config) \
  -newkey rsa:4096 -nodes \
  -keyout util/ca/test_ca.key.pem  \
  -sha256 \
  -out util/ca/csr/test_ca.csr
openssl ca \
  -config  <(local_openssl_config) \
  -batch \
  -in util/ca/csr/test_ca.csr \
  -keyfile util/ca/test_ca.key.pem \
  -selfsign \
  -create_serial \
  -days 7300 \
  -extensions ca_self_signed \
  -out util/ca/test_ca.cert.pem
openssl x509 -noout -text -in util/ca/test_ca.cert.pem

# Rsyslog server
ca_signed_cert test_syslog_server usr/local/etc/pki/test usr/local/etc/pki/test

# Behave sut
ca_signed_cert behave test/tls_x509/private test/tls_x509/certs

# Rsyslog CentOS client
ca_signed_cert test_syslog_client_centos7 test/tls_x509/private test/tls_x509/certs

# Rsyslog Ubuntu client
ca_signed_cert test_syslog_client_ubuntu1604 test/tls_x509/private test/tls_x509/certs

# Kafka server
ca_signed_cert test_kafka test/tls_x509/private test/tls_x509/certs

cp util/ca/test_ca.cert.pem usr/local/etc/pki/test/
# Copy (don't symlink) as docker build context for a test suites blocks access outside context
cp util/ca/test_ca.cert.pem test/tls_x509/certs/

# kafka needs java
openssl pkcs12 -export -inkey 'test/tls_x509/private/test_kafka.key.pem' -in 'test/tls_x509/certs/test_kafka.cert.pem' -CAfile 'util/ca/test_ca.cert.pem' -chain -passout 'pass:changeit' -out 'test/tls_x509/private/test_kafka.pfx'
keytool -trustcacerts \
  -importcert -file util/ca/test_ca.cert.pem \
  -alias 'test_ca' \
  -keystore 'test/tls_x509/certs/test_ca.jks' \
  -storepass 'changeit' -noprompt
