# Setup: Actions cache server

This guide explains how we run the GitHub Actions cache server inside the cluster and wire runner pods to it over cluster DNS.

## What the cache server deployment does

`k8s/cache-server/deployment.yaml` creates a Deployment and a ClusterIP Service for the cache server, exposed on port 80. The container stores cache data on the node using a hostPath volume.

The Deployment sets `API_BASE_URL` to the public base URL the cache server uses when returning cache URLs. This must match how the runner pods will reach the service (host + port), otherwise cache upload/download links will be wrong.

## How the runner pods reach the cache server

Cache traffic comes from the runner container itself, which runs inside a pod and so resolves cluster DNS. No `hostAliases` or node-level exposure is needed. The runner container is configured with `ACTIONS_RESULTS_URL` and `CUSTOM_ACTIONS_RESULTS_URL` pointing at the Service:

```
http://actions-cache-server.actions-cache.svc.cluster.local
```

(This is unlike the runner image itself, which is pulled by the node's container runtime and therefore does need an address the node can reach — see [setup-registry.md](setup-registry.md).)

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
  value: http://actions-cache-server.actions-cache.svc.cluster.local
```

Re‑apply if you changed it:

```bash
kubectl apply -f k8s/cache-server/deployment.yaml
```

## Step 3: Wire the runner pods to the cache server

Edit `k8s/arc/values/values.dind.yaml`:

Uncomment and set the cache URLs:

```yaml
- name: ACTIONS_RESULTS_URL
  value: "http://actions-cache-server.actions-cache.svc.cluster.local"
- name: CUSTOM_ACTIONS_RESULTS_URL
  value: "http://actions-cache-server.actions-cache.svc.cluster.local"
```

These must match `API_BASE_URL` in the cache server deployment exactly.

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

Trigger a workflow that uses `actions/cache` and verify cache hits/misses are routed through the cache server. If you see cache upload errors, double‑check that `API_BASE_URL`, `ACTIONS_RESULTS_URL`, and `CUSTOM_ACTIONS_RESULTS_URL` all match exactly.
