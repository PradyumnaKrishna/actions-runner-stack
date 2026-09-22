# Setup

This guide describes the core ARC runner setup. Registry and cache server setup are documented separately.

## Prerequisites

- A Kubernetes cluster
- Helm
- kubectl

## 1) Optional services (separate guides)

- Registry: [setup-registry.md](setup-registry.md)
- Cache server: [setup-cache-server.md](setup-cache-server.md)
- Monitoring: [setup-monitoring.md](setup-monitoring.md)

## 2) Build and push the runner image

Build and push the runner image to a registry your cluster can reach, or update `k8s/arc/values/values.dind.yaml` to use any existing image:

```bash
docker build -t mycr.registry.svc.cluster.local/runner:2.337.0 -f images/runner/Dockerfile .
docker push mycr.registry.svc.cluster.local/runner:2.337.0
```

The image digest then goes into `k8s/arc/values/values.dind.yaml` so the deployed image is unambiguous.

The upstream images are multi-arch (amd64 and arm64). The build produces your
build host's architecture, so build on the architecture your nodes run, or use
`--platform` if they differ.

## 3) Create namespaces and secrets

```bash
kubectl apply -f k8s/arc/namespaces.yaml

cp k8s/arc/secrets/github-token.secret.yaml.example k8s/arc/secrets/github-token.secret.yaml
kubectl apply -f k8s/arc/secrets/github-token.secret.yaml
```

## 3.1) Registry authentication (Docker Hub, GHCR, ECR, GCR/AR, ACR)

To pull images from private registries, provide a `dockerconfigjson` secret and mount it into the runner (and DinD if needed).

Option A: use the template and paste your `dockerconfigjson` (supports multiple registries):

```bash
cp k8s/arc/secrets/docker-config.secret.yaml.example k8s/arc/secrets/docker-config.secret.yaml
kubectl apply -f k8s/arc/secrets/docker-config.secret.yaml
```

Option A (alternative): create a secret from your local Docker config:

```bash
kubectl -n arc-runners create secret generic dockerhub-config \
  --type=kubernetes.io/dockerconfigjson \
  --from-file=.dockerconfigjson=$HOME/.docker/config.json
```

Option B: create a registry‑specific secret:

```bash
kubectl -n arc-runners create secret docker-registry dockerhub-config \
  --docker-server=<registry-host> \
  --docker-username=<user> \
  --docker-password=<password-or-token> \
  --docker-email=<email>
```

Then in `k8s/arc/values/values.dind.yaml`:

- Uncomment the `docker-secret` mount under the **runner** container.
- Uncomment the `docker-secret` volume under **volumes**.
- If your workflows pull images through the DinD daemon, also mount the secret into the **dind** container at `/root/.docker/config.json`.

## 4) Configure ARC values

Edit `k8s/arc/values/values.dind.yaml`:

- Set `githubConfigUrl` to your org or repo
- Ensure the runner image points to the registry and tag you built.
- If you use a private registry, follow [setup-registry.md](setup-registry.md) to set up the CA secret and mounts.
- If you use a cache server, follow [setup-cache-server.md](setup-cache-server.md) to set `ACTIONS_RESULTS_URL` and `CUSTOM_ACTIONS_RESULTS_URL`.
- If you want metrics (works with an existing Prometheus or the bundled quick start), follow [setup-monitoring.md](setup-monitoring.md). The controller values in `k8s/arc/values/values.controller.yaml` are what expose them; without those, nothing is scrapeable.
- Uncomment the docker auth secret mount/volume if your registry requires auth

## 5) Install ARC via Helm

Follow the official ARC docs to install the controller and runner scale set. For convenience, the standard Helm installs are:

```bash
# Controller
helm install arc \
  --namespace arc-systems \
  --create-namespace \
  -f k8s/arc/values/values.controller.yaml \
  oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set-controller

# Runner scale set
helm install <RUNNER_SET_NAME> \
  --namespace arc-runners \
  --create-namespace \
  -f k8s/arc/values/values.dind.yaml \
  oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set
```

## 6) Validate

```bash
kubectl -n arc-systems get pods
kubectl -n arc-runners get pods
```

Trigger a workflow that targets your runner labels and confirm that runner pods spin up and complete successfully.
