# Setup: Actions cache server

This guide explains how we run the GitHub Actions cache server inside the cluster and wire runner pods to it through a NodePort service and `hostAliases`.

## What the cache server deployment does

`k8s/cache-server/deployment.yaml` creates a Deployment and a NodePort Service for the cache server. The container runs `ghcr.io/falcondev-oss/github-actions-cache-server:latest` and stores cache data on the node using a hostPath volume. The Service exposes port 3000 inside the cluster and also opens a NodePort (30300 by default) on the node, so the cache server is reachable at `<node-ip>:30300`.

The Deployment sets `API_BASE_URL` to the public base URL the cache server uses when returning cache URLs. This must match how the runner pods will reach the service (host + port), otherwise cache upload/download links will be wrong.

## How the runner pods reach the cache server

We do not rely on the in‑cluster Service DNS for the cache server. Instead, runner pods resolve a host name using `hostAliases` (in `k8s/arc/values/values.dind.yaml`) and connect to the NodePort service on the node IP. The runner container is configured with `ACTIONS_RESULTS_URL` and `CUSTOM_ACTIONS_RESULTS_URL` to point at that host and port.

This means the cache server is accessed as:

```
http://<cache-host>:30300/
```

Where `<cache-host>` is mapped to the node IP through `hostAliases`.

## Step 1: Deploy the cache server

```bash
kubectl apply -f k8s/cache-server/namespace.yaml
kubectl apply -f k8s/cache-server/deployment.yaml
```

Verify it is running:

```bash
kubectl -n actions-cache get pods
kubectl -n actions-cache get svc
```

## Step 2: Set the cache server base URL

Edit `k8s/cache-server/deployment.yaml` and set `API_BASE_URL` to the URL that runner pods will use:

```yaml
- name: API_BASE_URL
  value: http://registry.local:30300
```

Re‑apply if you changed it:

```bash
kubectl apply -f k8s/cache-server/deployment.yaml
```

## Step 3: Wire the runner pods to the cache server

Edit `k8s/arc/values/values.dind.yaml`:

1. Add or update `hostAliases` so `registry.local` resolves to the node IP where the NodePort is reachable.
2. Uncomment and set the cache URLs:

```yaml
- name: ACTIONS_RESULTS_URL
  value: "http://registry.local:30300/"
- name: CUSTOM_ACTIONS_RESULTS_URL
  value: "http://registry.local:30300/"
```

These must match `API_BASE_URL` in the cache server deployment.

## Step 4: Use the custom runner image

The GitHub runner binary needs a small patch to allow the custom cache URL. We bake this change into our runner image in `images/runner/Dockerfile`.

Build and push the image, then make sure `k8s/arc/values/values.dind.yaml` points to it:

```bash
docker build -t registry.local/runner:latest -f images/runner/Dockerfile .
docker push registry.local/runner:latest
```

## Step 5: Deploy or upgrade the runner scale set

Install or upgrade your runner scale set with the updated values file so the runner pods pick up the cache settings.

## Validate

Trigger a workflow that uses `actions/cache` and verify cache hits/misses are routed through the cache server. If you see cache upload errors, double‑check that `API_BASE_URL`, `ACTIONS_RESULTS_URL`, and `CUSTOM_ACTIONS_RESULTS_URL` all match and that the host alias resolves inside runner pods.
