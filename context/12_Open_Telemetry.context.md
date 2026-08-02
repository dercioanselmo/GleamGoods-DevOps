# Context: `12_Open_Telemetry`

You are senior devops engineer, and bellow is the complete brief for implementing (or re-implementing) the OpenTelemetry collector pipelines of the GleamGoods-DevOps project.

## Purpose

Defines what actually gets collected — the `OpenTelemetryCollector`/`Instrumentation` custom resources the ADOT operator (installed by `05_OpenTelemetry`'s Terraform) reconciles into running collector pods and auto-instrumentation webhooks. Plain Kubernetes manifests, **no Terraform, no CI**, applied by hand — same split rationale as `04_EKS_Karpenter`/`09_KARPENTER_k8s-manifests`. Don't fold these into the Terraform module.

Three independent pipelines, one per signal, each in its own numbered subfolder.

## `01_OpenTelemetry_Traces/`

- **`01_adot_collector_traces.yaml`** — `OpenTelemetryCollector`, `mode: deployment`, 1 replica, `serviceAccount: adot-collector`. Receivers: OTLP gRPC (4317) + HTTP (4318). Processors, in this order: `memory_limiter` (OOM protection, must run first) → a `filter/healthcheck` processor dropping health/probe spans (match on Spring Boot Actuator paths, `ELB-HealthChecker` user-agent, `kube-probe/*` user-agent, `/health` path variants, and framework-specific health middleware spans for NestJS/Express — a deliberately long list, since unfiltered health-check traffic dominates trace volume otherwise) → `k8sattributes` (adds namespace/pod/deployment/node context, required for trace-to-resource correlation in the UI) → `batch`. Exporter: `awsxray`. A `debug` exporter is also wired in for teaching/troubleshooting visibility — comment it out for a quieter production setup, don't remove the pattern entirely.
- **`02_adot_instrumentation_traces.yaml`** — the `Instrumentation` CR the ADOT operator's admission webhook uses for auto-instrumentation. Points every annotated pod's SDK at `http://adot-traces-collector:4318`. `OTEL_TRACES_EXPORTER=otlp`, but **`OTEL_METRICS_EXPORTER=none`** and **`OTEL_LOGS_EXPORTER=none`** — traces only via SDK auto-instrumentation; metrics and logs are handled entirely by the separate collectors below, not by the application SDK. Don't enable those exporters here without also reconsidering whether that duplicates what the dedicated metrics/logs collectors already do.
- **`03_restart-retailapp.sh`** — `kubectl rollout restart` on all 5 microservice deployments. **Required, not optional tooling**: the instrumentation webhook only injects the SDK at pod *creation* time. Applying or updating the `Instrumentation` CR does nothing to already-running pods — they need an explicit restart to pick it up. Include an equivalent step whenever this CR changes.

## `02_OpenTelemetry_Logs/`

- **`01_adot_collector_logs.yaml`** — `OpenTelemetryCollector`, `mode: daemonset` (one pod per node — logs are node-local, unlike traces/metrics which can centralize). `podSecurityContext: { runAsUser: 0 }` — required to read host log files under `/var/log/pods`, mounted via a `hostPath` volume. `filelog` receiver on `/var/log/pods/*/*/*.log`, excluding its own pods and everything in `kube-system` (noise reduction), `start_at: end` (don't ingest historical logs on collector startup). Processors: `memory_limiter`, `k8sattributes`, `batch`. Exporter: `awscloudwatchlogs`, single log group + single log stream (adequate for this cluster's size; note in comments that per-node log streams are the scale-up path if needed later).
- **`02_restart-retailapp.sh`** — same rollout-restart requirement as the traces folder, if logs-related annotations/env are ever added to the application pod spec.

## `03_OpenTelemetry_AMP_AMG/`

- **`01_adot_collector_prometheus_full_k8s_cluster.yaml`** — `OpenTelemetryCollector`, `mode: deployment`, 1 replica, `serviceAccount: adot-collector`. This is the most complex of the three: a full Prometheus-compatible `prometheus` receiver scrape config (apiserver, nodes, cAdvisor, annotated services/pods, both fast and 5-minute-interval "slow" job variants) plus an `otlp` receiver, processors (`batch`, `memory_limiter`, `resourcedetection/eks`, a `resource` processor stamping `cluster.name`/`deployment.environment`). Exporter: `prometheusremotewrite` to AMP, authenticated via a `sigv4auth` extension (SigV4-signs using the pod's own Pod Identity credentials — no separate AMP credential needed).

### Critical gotcha: raw scrape-config job names don't match what community Grafana dashboards expect

A scrape config copied from Prometheus's own generic docs (the shape this file uses) discovers kube-state-metrics and node-exporter via a shared, annotation-driven `kubernetes-service-endpoints` job — **not** dedicated `job=kube-state-metrics`/`job=node-exporter` jobs. Standard `kubernetes-mixin`/kube-prometheus-stack dashboards filter on those conventional job names and will show empty panels without them, even though the underlying metric data is present under a different label. **Fix, required if importing any standard community Kubernetes dashboard**: add conditional `relabel_configs` on the shared `kubernetes-service-endpoints` job overriding `job` based on `__meta_kubernetes_service_name` (match `kube-state-metrics` → `job=kube-state-metrics`, `prometheus-node-exporter` → `job=node-exporter` — conditional because that job also scrapes anything *else* carrying the `prometheus.io/scrape` annotation, so it can't be blanket-renamed), plus an unconditional `job=cadvisor` override on the dedicated `kubernetes-nodes-cadvisor` job (safe unconditionally since that job scrapes nothing else). Verify the exact live service names/namespaces (`kubectl get svc -n kube-state-metrics`, `-n prometheus-node-exporter`) before writing the relabel match values — don't assume generic names.

### Second requirement, not part of this collector: AMP recording rules

Even with correct job labels, standard dashboards (the `kubernetes-mixin` family — Grafana IDs like 15757/15759/15760/15761) additionally require **precomputed recording-rule metrics** this collector cannot produce (it has no rule-evaluation engine). That's a Terraform-side requirement in `05_OpenTelemetry` (`aws_prometheus_rule_group_namespace`) — see that module's context file. Don't try to solve this by adding rule evaluation to the collector config itself.

### AMP workspace ID / endpoint — prefer sourcing from Terraform output over hardcoding

The `prometheusremotewrite` endpoint in this file currently embeds the AMP workspace ID directly as a literal string. If the AMP workspace is ever destroyed/recreated (new workspace ID), this file needs a manual update and nothing will error — metrics just silently stop arriving. If reimplementing, prefer templating this value from `05_OpenTelemetry`'s Terraform output where the deployment tooling allows it (e.g. a substitution step before `kubectl apply`), rather than a bare literal.

- **`02_verify_amp_metrics.sh`** — a diagnostic script (`awscurl`, SigV4-signed queries against the AMP query API) checking basic connectivity, discovering scrape jobs, and counting unique metric names. Has the same hardcoded-workspace-ID characteristic as the collector YAML above — keep both in sync if the workspace ever changes.

## Repo-wide conventions

- Numbered subfolders/files by apply order and by signal, matching this project's other manual-manifest folders.

## CI/CD

None — manual `kubectl apply -f` per file/folder.

## Explicitly out of scope

- AMP recording rules — Terraform concern (`05_OpenTelemetry`), not this folder.
- The ADOT operator, cert-manager, AMP/AMG workspaces themselves — Terraform concern (`05_OpenTelemetry`), this folder only consumes them.
- Application-side instrumentation annotations — live in the application Helm charts (separate repo), not here.
