# Setup: Container registry

Optional. The runners work with any registry the cluster can pull from; this
sets one up inside the cluster, reachable at
`mycr.registry.svc.cluster.local` over TLS. Nodes and workflows use the same
name, and nothing is exposed outside the cluster.

## What the manifests do

- `k8s/registry/base/storage.yaml` creates the `registry` namespace and a PVC for image data.
- `k8s/registry/base/tls.yaml` creates a private CA and the registry certificate, issued and renewed by cert-manager.
- `k8s/registry/base/registry.yaml` runs the registry with that certificate, as a ClusterIP Service on port 443.

## Prerequisite: cert-manager

```bash
helm repo add jetstack https://charts.jetstack.io
helm upgrade --install cert-manager jetstack/cert-manager \
  -n cert-manager --create-namespace --version v1.21.2 --set crds.enabled=true --wait
```

## Step 1: Deploy

```bash
kubectl apply -f k8s/registry/base/storage.yaml
kubectl apply -f k8s/registry/base/tls.yaml
kubectl apply -f k8s/registry/base/registry.yaml
kubectl -n registry get certificate mycr-tls
```

The Service uses a fixed ClusterIP (`10.43.0.100`) so nodes have a stable
address to map the name to. Change it in `registry.yaml` if that address is
taken or your service CIDR differs (k3s default: `10.43.0.0/16`).

## Step 2: Trust the CA on every node

Images are pulled by the container runtime on the node, which sits outside the
cluster network. Each node needs the CA and a way to resolve the name:

```bash
kubectl -n cert-manager get secret registry-ca -o jsonpath='{.data.ca\.crt}' | base64 -d > registry-ca.crt

sudo cp registry-ca.crt /usr/local/share/ca-certificates/actions-runner-stack-ca.crt
sudo update-ca-certificates

echo "10.43.0.100 mycr.registry.svc.cluster.local" | sudo tee -a /etc/hosts
```

The system trust store covers containerd, podman and curl, so no
`registries.yaml` or per-tool config is needed. The CA is valid for ten years;
put both steps in whatever provisions your nodes.

Verify with `curl https://mycr.registry.svc.cluster.local/v2/`.

## Step 3: Give runner pods the CA

```bash
kubectl -n arc-runners create secret generic registry-ca --from-file=ca.crt=registry-ca.crt
```

`k8s/arc/values/values.dind.yaml` mounts it at
`/etc/docker/certs.d/mycr.registry.svc.cluster.local/` for the DinD sidecar.

## Step 4: Build and push the runner image

```bash
podman build -t mycr.registry.svc.cluster.local/runner:<version> -f images/runner/Dockerfile .
podman push mycr.registry.svc.cluster.local/runner:<version>
```

Pin `<version>` to an explicit tag; see [decisions.md](decisions.md) for why the
runner version must stay current. Point the `runner` and `init-dind-externals`
images in `k8s/arc/values/values.dind.yaml` at the tag you pushed.

## Using it from workflows

```yaml
jobs:
  build:
    runs-on: your-runner-label
    services:
      db:
        image: mycr.registry.svc.cluster.local/postgres:16
    steps:
      - run: docker pull mycr.registry.svc.cluster.local/alpine:3.20
```

## Validate

```bash
kubectl -n registry get pods
curl https://mycr.registry.svc.cluster.local/v2/_catalog
```

Then run a workflow that pulls from the registry and confirm it succeeds.

## Other ways to expose it

The setup above keeps the registry inside the cluster and uses a private CA,
which costs one trust step per node. Two alternatives issue publicly trusted
certificates instead, so nodes need no CA at all:

**Tailscale.** With the [Tailscale Kubernetes operator](https://tailscale.com/kb/1236/kubernetes-operator),
an `Ingress` with `ingressClassName: tailscale` gets a Let's Encrypt
certificate for a `*.ts.net` name. Set the hostname in `spec.tls.hosts`; the
`tailscale.com/hostname` annotation applies to Services, not Ingresses. The
registry is then reachable from anything on the tailnet and nowhere else.

**Traefik with cert-manager, on a domain you own.** Point a subdomain at the
cluster and issue a certificate over the ACME DNS-01 challenge, which needs no
inbound ports. Use this when machines outside the cluster and off the tailnet
have to pull images.

Both remove the per-node CA step. Neither adds authentication -- see the note
in [decisions.md](decisions.md).
