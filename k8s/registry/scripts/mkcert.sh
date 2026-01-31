#!/usr/bin/env bash
set -euo pipefail

REGISTRY_HOST="${REGISTRY_HOST:-registry.local}"
REGISTRY_NAMESPACE="${REGISTRY_NAMESPACE:-registry}"
ARC_NAMESPACE="${ARC_NAMESPACE:-arc-runners}"

mkcert -install
mkcert "${REGISTRY_HOST}"
# produces: ${REGISTRY_HOST}.pem (cert), ${REGISTRY_HOST}-key.pem (key)

# Create a TLS secret in the registry namespace for Traefik:
kubectl -n "${REGISTRY_NAMESPACE}" create secret tls registry-tls \
  --cert="${REGISTRY_HOST}.pem" --key="${REGISTRY_HOST}-key.pem"

# Create a secret from that CA:
kubectl -n "${ARC_NAMESPACE}" create secret generic registry-ca \
  --from-file=ca.crt="$(mkcert -CAROOT)/rootCA.pem"
