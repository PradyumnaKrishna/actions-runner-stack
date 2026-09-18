# Decisions and rationale

## Why `privileged: true`?

- **DinD sidecar**: Docker-in-Docker requires privileged mode so the Docker daemon can run inside the pod.
- **Runner container**: Some workflows build/run nested containers or require kernel capabilities. We defaulted to privileged for compatibility, but you can disable it if your jobs do not require it.

If you can run without privileged runners, set `securityContext.privileged: false` on the `runner` container.

## Why a custom Docker MTU?

Docker defaults to MTU 1500. In some CNI / overlay / VPN setups the effective MTU is smaller, causing:

- `docker pull` timeouts
- flaky Git operations inside build containers
- intermittent TLS handshake issues

Setting `--mtu=1300` on `dockerd` avoids fragmentation in those networks. Adjust based on your cluster MTU.

## How the registry is reached

The registry is a ClusterIP Service named `mycr`, so pods resolve
`mycr.registry.svc.cluster.local` through cluster DNS like any other service.

Image pulls are different: they are performed by the container runtime on the
node, which is outside the cluster network and does not use cluster DNS. Nodes
map the name to the Service's fixed ClusterIP in `/etc/hosts`, which is why the
Service pins its address.

The registry has no authentication: anything that can reach the Service and
trusts the CA can push and delete images. TLS does not change that. Add
htpasswd auth or a NetworkPolicy if the cluster is shared.

TLS comes from a private CA managed by cert-manager. Installing that CA into
each node's system trust store covers containerd, podman and curl at once, so
no registry-specific runtime configuration is needed. Runner pods get the same
CA mounted into the DinD sidecar.

## Why patch `Runner.Worker.dll` in the runner image?

We use a custom actions cache server and set `ACTIONS_RESULTS_URL`/`CUSTOM_ACTIONS_RESULTS_URL` to redirect results traffic. The runner always prefers the `ACTIONS_RESULTS_URL` that GitHub sends with each job, so the patch renames that lookup string inside `Runner.Worker.dll` to `ACTIONS_RESULTS_ORL`. The lookup misses and the runner falls back to `CUSTOM_ACTIONS_RESULTS_URL`. This is a pragmatic workaround until upstream supports a first-class config.

Because it patches bytes in a compiled binary, the runner base image is pinned and the build fails if the patch doesn't apply. When bumping the runner version, keep it recent: GitHub stops sending jobs to deprecated runner versions, and ARC runners can't self-update.

## Why are we defining the DinD sidecar explicitly?

ARC supports `containerMode.type: dind` in the Helm chart. We keep an explicit `dind` container in `values.dind.yaml` so we can:

- mount a custom registry CA
- control Docker storage paths
- set MTU directly

If you prefer the chart-managed DinD, migrate to `containerMode.type: dind` and move the extra mounts into the chart's supported template overrides.
