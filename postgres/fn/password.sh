#!/bin/bash
set -e

POSTGRES_PASSWORD=$(openssl rand -base64 18 | tr -d '\n' | base64 -w 0)
PRIMARYUSER_PASSWORD=$(openssl rand -base64 18 | tr -d '\n' | base64 -w 0)
TESTUSER_PASSWORD=$(openssl rand -base64 18 | tr -d '\n' | base64 -w 0)
export POSTGRES_PASSWORD
export PRIMARYUSER_PASSWORD
export TESTUSER_PASSWORD
envsubst '${POSTGRES_PASSWORD} ${PRIMARYUSER_PASSWORD} ${TESTUSER_PASSWORD}'
