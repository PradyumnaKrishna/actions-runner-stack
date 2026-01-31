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

## Why `hostAliases` for the registry?

The runners need to resolve the registry hostname. If cluster DNS does not resolve it, we pin the registry host to a node IP. Prefer a real DNS record or a CoreDNS override if possible.

## Why patch `Runner.Worker.dll` in the runner image?

We use a custom actions cache server and set `ACTIONS_RESULTS_URL`/`CUSTOM_ACTIONS_RESULTS_URL` to redirect results traffic. The runner image includes a small patch to allow this override. This is a pragmatic workaround until upstream supports a first-class config.

TODO: confirm the exact reason and update this section.

## Why are we defining the DinD sidecar explicitly?

ARC supports `containerMode.type: dind` in the Helm chart. We keep an explicit `dind` container in `values.dind.yaml` so we can:

- mount a custom registry CA
- control Docker storage paths
- set MTU directly

If you prefer the chart-managed DinD, migrate to `containerMode.type: dind` and move the extra mounts into the chart's supported template overrides.
