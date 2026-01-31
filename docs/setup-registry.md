# Setup: Container registry

This guide explains how we run a private Docker registry in‑cluster and wire runner pods to it. The registry is exposed over HTTP by default, with an optional HTTPS path using Traefik and a custom certificate that the runner trusts.

## What the registry manifests do

- `k8s/registry/base/storage.yaml` creates the `registry` namespace plus a hostPath PV/PVC to persist images on the node.
- `k8s/registry/base/registry.yaml` creates the registry Deployment (image `registry:2`) and a ClusterIP Service on port 5000.
- `k8s/registry/ingress/traefik-https.yaml` optionally exposes the registry over HTTPS via Traefik.
- `k8s/registry/scripts/mkcert.sh` generates a local certificate and stores:
  - a TLS secret in the `registry` namespace
  - a CA secret in `arc-runners` so runner pods trust the registry certificate

## Step 1: Choose the registry host

Pick a hostname (examples: `registry.local`, `registry.mycorp.internal`). Runner pods must be able to resolve this hostname.

If you don’t have cluster DNS, use `hostAliases` in `k8s/arc/values/values.dind.yaml` to map the hostname to a node IP.

## Step 2: Provision storage

Update the hostPath in `k8s/registry/base/storage.yaml`:

```yaml
hostPath:
  path: /mnt/data/container/registry
```

Apply the storage manifests:

```bash
kubectl apply -f k8s/registry/base/storage.yaml
```

## Step 3: Deploy the registry

```bash
kubectl apply -f k8s/registry/base/registry.yaml
```

Verify:

```bash
kubectl -n registry get pods
kubectl -n registry get svc
```

The registry is now reachable at `registry:5000` inside the cluster. For runner pods, we route traffic through a node IP (via Traefik or another ingress) and map the registry hostname using `hostAliases`.

## Step 4: Enable HTTPS and create the CA secret

Generate a certificate and create secrets:

```bash
chmod +x k8s/registry/scripts/mkcert.sh
REGISTRY_HOST=registry.local REGISTRY_NAMESPACE=registry ARC_NAMESPACE=arc-runners \
  k8s/registry/scripts/mkcert.sh
kubectl apply -f k8s/registry/ingress/traefik-https.yaml
```

This creates:

- `registry-tls` in the `registry` namespace
- `registry-ca` in the `arc-runners` namespace

If you do not use the script, you can also create the CA secret from the template in this repo:

```bash
cp k8s/arc/secrets/registry-ca.secret.yaml.example k8s/arc/secrets/registry-ca.secret.yaml
kubectl apply -f k8s/arc/secrets/registry-ca.secret.yaml
```

## Step 5: Wire the registry into ARC

Edit `k8s/arc/values/values.dind.yaml`:

1) Add or update `hostAliases` so `registry.local` resolves to the node IP where your ingress listens.
2) Trust the registry certificate by mounting the CA into the DinD container:

```yaml
# in the dind container mounts
- name: registry-ca
  mountPath: /etc/docker/certs.d/registry.local
  readOnly: true

# in volumes
- name: registry-ca
  secret:
    secretName: registry-ca
```

3) If your registry requires auth, create and mount the docker config secret:

```bash
cp k8s/arc/secrets/docker-config.secret.yaml.example k8s/arc/secrets/docker-config.secret.yaml
kubectl apply -f k8s/arc/secrets/docker-config.secret.yaml
```

Then mount `docker-secret` in the runner container.

## Step 6: Build and push the runner image

```bash
docker build -t registry.local/runner:latest -f images/runner/Dockerfile .
docker push registry.local/runner:latest
```

Make sure `k8s/arc/values/values.dind.yaml` points to `registry.local/runner:latest`.

## Step 7: Validate

- Registry pod is running: `kubectl -n registry get pods`
- Runner pods can pull the runner image from the registry
- If HTTPS is enabled, ensure the CA secret exists in `arc-runners`
