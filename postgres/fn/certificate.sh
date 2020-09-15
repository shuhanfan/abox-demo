#!/bin/bash
set -e

resources=$(cat)
if [[ "$resources" != *'${CA_CRT}'* ]]; then
  >&2 echo "Skip certificate generation, because they already exist."
  echo "$resources"
  exit
fi

TMPDIR=$(mktemp -d)
if [[ ! -d $TMPDIR ]]; then
  >&2 echo "Failed to create temp directory"
  exit 1
fi
trap "exit 1" HUP INT PIPE QUIT TERM
trap 'rm -r "$TMPDIR"' EXIT

openssl req -new -nodes -out "$TMPDIR/ca.csr" -keyout "$TMPDIR/ca.key" -subj "/CN=root" 1>&2
openssl x509 -req -in "$TMPDIR/ca.csr" -days 3650 -signkey "$TMPDIR/ca.key" -out "$TMPDIR/ca.crt" 1>&2

openssl req -new -nodes -out "$TMPDIR/server.csr" -keyout "$TMPDIR/server.key" -subj "/CN=server" 1>&2
openssl x509 -req -in "$TMPDIR/server.csr" -days 3650 -CA "$TMPDIR/ca.crt" -CAkey "$TMPDIR/ca.key" -CAcreateserial -out "$TMPDIR/server.crt" 1>&2

openssl req -new -nodes -out "$TMPDIR/replication.csr" -keyout "$TMPDIR/replication.key" -subj "/CN=primaryuser" 1>&2
openssl x509 -req -in "$TMPDIR/replication.csr" -days 3650 -CA "$TMPDIR/ca.crt" -CAkey "$TMPDIR/ca.key" -CAcreateserial -out "$TMPDIR/replication.crt" 1>&2

CA_CRT=$(base64 -w 0 < "$TMPDIR/ca.crt")
SERVER_CRT=$(base64 -w 0 < "$TMPDIR/server.crt")
SERVER_KEY=$(base64 -w 0 < "$TMPDIR/server.key")
REPLICATION_CRT=$(base64 -w 0 < "$TMPDIR/replication.crt")
REPLICATION_KEY=$(base64 -w 0 < "$TMPDIR/replication.key")
export CA_CRT
export SERVER_CRT
export SERVER_KEY
export REPLICATION_CRT
export REPLICATION_KEY
echo "$resources" | envsubst '${CA_CRT} ${SERVER_CRT} ${SERVER_KEY} ${REPLICATION_CRT} ${REPLICATION_KEY}'
