#!/bin/bash

set -e

ADMINCRED=Administrator:password
CHAIN=chain
INTERMEDIATE=int
NODE=pkey
ROOT_CA=ca

IP=${2:-127.0.0.1}
OS=${1:-centos} # or macos
USERNAME=${3:-travel-sample}

# Example commands
# ./gen_keystore.sh macos 127.0.0.1 travel-sample
# ./gen_keystore.sh centos 192.168.33.10 foo-bar

echo Generate ROOT CA
# Generate ROOT CA
openssl genrsa -out ${ROOT_CA}.key 2048 2>/dev/null
openssl req -new -x509  -days 3650 -sha256 -key ${ROOT_CA}.key -out ${ROOT_CA}.pem \
-subj '/C=UA/O=My Company/CN=My Company Root CA' 2>/dev/null

echo Generate Intermediate
# Generate intemediate key and sign with ROOT CA
openssl genrsa -out ${INTERMEDIATE}.key 2048 2>/dev/null
openssl req -new -key ${INTERMEDIATE}.key -out ${INTERMEDIATE}.csr -subj '/C=UA/O=My Company/CN=My Company Intermediate CA' 2>/dev/null
openssl x509 -req -in ${INTERMEDIATE}.csr -CA ${ROOT_CA}.pem -CAkey ${ROOT_CA}.key -CAcreateserial \
-CAserial rootCA.srl -extfile v3_ca.ext -out ${INTERMEDIATE}.pem -days 365 2>/dev/null

# Generate client key and sign with ROOT CA and INTERMEDIATE KEY
echo Generate RSA
openssl genrsa -out ${NODE}.key 2048 2>/dev/null
openssl req -new -key ${NODE}.key -out ${NODE}.csr -subj "/C=UA/O=My Company/CN=${USERNAME}" 2>/dev/null
openssl x509 -req -in ${NODE}.csr -CA ${INTERMEDIATE}.pem -CAkey ${INTERMEDIATE}.key -CAcreateserial \
-CAserial intermediateCA.srl -out ${NODE}.pem -days 365 -extfile openssl-san.cnf -extensions 'v3_req'

# Generate certificate chain file
cat ${NODE}.pem ${INTERMEDIATE}.pem ${ROOT_CA}.pem > ${CHAIN}.pem

# Install certificate to inbox
if [ "${OS}" = "centos" ]; then
	echo Copying files to Ubuntu path
	INBOX=/opt/couchbase/var/lib/couchbase/inbox/
	mkdir -p ${INBOX}
	cp ./${CHAIN}.pem ${INBOX}${CHAIN}.pem
	chmod a+x ${INBOX}${CHAIN}.pem
	cp ./${NODE}.key ${INBOX}${NODE}.key
	chmod a+x ${INBOX}${NODE}.key
elif [ "${OS}" = "macos" ]; then
	echo Copying files to macOS path
	mkdir -p /Users/jamesnocentini/Library/Application\ Support/Couchbase/var/lib/couchbase/inbox/
	cp ./${CHAIN}.pem /Users/jamesnocentini/Library/Application\ Support/Couchbase/var/lib/couchbase/inbox/${CHAIN}.pem
	chmod a+x /Users/jamesnocentini/Library/Application\ Support/Couchbase/var/lib/couchbase/inbox/${CHAIN}.pem
	cp ./${NODE}.key /Users/jamesnocentini/Library/Application\ Support/Couchbase/var/lib/couchbase/inbox/${NODE}.key
	chmod a+x /Users/jamesnocentini/Library/Application\ Support/Couchbase/var/lib/couchbase/inbox/${NODE}.key
else
	echo "Error: the first param must be `centos` or `macos`"
fi

# Upload ROOT CA and activate it
curl -vX POST --data-binary "@./${ROOT_CA}.pem" \
		http://${ADMINCRED}@${IP}:8091/controller/uploadClusterCA
curl -vX POST http://${ADMINCRED}@${IP}:8091/node/controller/reloadCertificate

# Enable client cert
POST_DATA='{"state": "enable","prefixes": [{"path": "subject.cn","prefix": "","delimiter": ""}]}'
curl -vX POST -H "Content-Type: application/json" -d "${POST_DATA}" http://${ADMINCRED}@${IP}:8091/settings/clientCertAuth
