# Setup: Monitoring

## What you get

Metrics from the ARC controller, from each runner scale set's listener (job startup and execution times, runner counts) and from the in-cluster registry. Use the Prometheus you already have, or the bundled one if you don't have one yet.

Monitoring requires two distinct halves. The Prometheus manifests alone are not enough: ARC's controller and its per-scale-set listener only expose `:8080` when the controller Helm chart is installed with the `metrics` configuration block enabled. Without that block, neither component opens port `:8080`, and every Prometheus scrape job returns nothing. Missing this configuration is the easiest thing to get wrong.

Because listener pods have no stable network address, Prometheus cannot scrape them through static targets. Instead, Prometheus discovers listener pods dynamically using Kubernetes pod discovery targeting the `arc-systems` namespace.

## Step 1: Enable metrics (required for all options)

Install or upgrade the ARC controller chart with `k8s/arc/values/values.controller.yaml`. The `metrics` block in this values file configures both the controller manager and runner scale set listeners to listen on `:8080` and expose `/metrics`:

```bash
helm upgrade --install arc -n arc-systems --create-namespace \
  --version 0.14.2 \
  -f k8s/arc/values/values.controller.yaml \
  oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set-controller
```

The registry's debug listener is plain HTTP and separate from the TLS registry port; `k8s/registry/base/registry.yaml` turns it on with `REGISTRY_HTTP_DEBUG_ADDR` and `REGISTRY_HTTP_DEBUG_PROMETHEUS_ENABLED`. See [setup-registry.md](setup-registry.md).

## Step 2: Configure Prometheus

Choose one of the following options based on your cluster's Prometheus setup.

### Option A: Prometheus Operator / kube-prometheus-stack

If your cluster runs the Prometheus Operator (e.g., via `kube-prometheus-stack`), apply the PodMonitors:

```bash
kubectl apply -f k8s/monitoring/prometheus-operator/podmonitors.yaml
```

Note: `kube-prometheus-stack`'s Prometheus only picks up PodMonitors whose labels match its `podMonitorSelector` (by default `release: <helm release name>`). This is the most common reason a PodMonitor is silently ignored. To fix this, either:
- label the PodMonitors with your release name:

  ```bash
  kubectl label podmonitor -n arc-systems arc-listener arc-controller release=<your-release>
  kubectl label podmonitor -n registry registry release=<your-release>
  ```

- or set the kube-prometheus-stack Helm value `prometheus.prometheusSpec.podMonitorSelectorNilUsesHelmValues=false`, which makes Prometheus select every PodMonitor.

### Option B: An existing Prometheus without the Operator

Copy the three scrape jobs (`arc-listener`, `arc-controller`, `registry`) from the `scrape_configs` in the ConfigMap in `k8s/monitoring/prometheus/prometheus.yaml` into your Prometheus configuration.

The listener job requires Kubernetes pod discovery (`kubernetes_sd_configs` with `role: pod` in the `arc-systems` namespace). Ensure your Prometheus service account has `get`, `list`, and `watch` permissions on pods in that namespace.

### Option C: No Prometheus yet (bundled quick start)

If you do not have Prometheus, you can deploy the bundled quick start. Apply the manifests in order to avoid backoff:

```bash
kubectl apply -f k8s/monitoring/prometheus/namespace.yaml
kubectl apply -f k8s/monitoring/prometheus/rbac.yaml
kubectl apply -f k8s/monitoring/prometheus/storage.yaml
kubectl apply -f k8s/monitoring/prometheus/prometheus.yaml
```

The storage allocates 20Gi via k3s' `local-path` provisioner, which is node-local. The Deployment runs Prometheus with `fsGroup: 65534` because `prom/prometheus` runs as the non-root user `nobody`, while k3s `local-path` volumes are created root-owned.

You can access the UI by port-forwarding:

```bash
kubectl port-forward -n monitoring svc/prometheus 9090:9090
```

## Validate

In the Prometheus UI (Status > Targets), the listener, controller and registry targets should be **UP**. With the scrape jobs (options B and C) they appear as `arc-listener`, `arc-controller` and `registry`; with PodMonitors (option A) as `podMonitor/arc-systems/arc-listener/0`, `podMonitor/arc-systems/arc-controller/0` and `podMonitor/registry/registry/0`.

After a job has run, `gha_job_startup_duration_seconds` and `gha_job_execution_duration_seconds` should have samples. The listener creates these metrics on its first job, so they are absent on a fresh listener.
