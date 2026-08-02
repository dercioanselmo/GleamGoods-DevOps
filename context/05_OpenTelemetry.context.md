# Context: `05_OpenTelemetry` Terraform module

You are senior devops engineer, and bellow is the complete brief for implementing (or re-implementing) the observability module of the GleamGoods-DevOps project.

## Purpose

Installs the observability **platform**: AWS Distro for OpenTelemetry (ADOT — the operator only, not a running collector), cert-manager (ADOT's own prerequisite), two supporting metrics addons (`prometheus-node-exporter`, `kube-state-metrics`), an Amazon Managed Prometheus (AMP) workspace, an Amazon Managed Grafana (AMG) workspace, and AMP-side recording rules. Together these carry three observability signals — traces, logs, metrics — into AWS-native backends (X-Ray, CloudWatch Logs, AMP), queryable from one Grafana workspace.

**Like `04_EKS_Karpenter`, this module installs the platform only — not what actually gets collected.** The Kubernetes custom resources that define real collector pipelines (`OpenTelemetryCollector`, `Instrumentation`) live outside this module entirely (see below). Don't fold those into this module's Terraform.

Consumes `02_VPC` and `03_EKS_with_addons` via `data.terraform_remote_state`.

## EKS addons — hard requirements

| Addon | Purpose | Depends on |
|---|---|---|
| `cert-manager` | Issues the webhook TLS certificate the ADOT addon's own admission webhook needs | — |
| `adot` | The ADOT **operator** — reconciles `OpenTelemetryCollector`/`Instrumentation` CRs into running pods/webhooks. Installing it alone collects nothing | `cert-manager`, explicit `depends_on` |
| `prometheus-node-exporter` | Node-level hardware/OS metrics, DaemonSet | — |
| `kube-state-metrics` | Kubernetes *object* state (replica counts, pod status) as Prometheus metrics — distinct from node_exporter | — |

All four addon versions pinned via a single `var.addon_versions` object (`adot`, `cert_manager`, `kube_state_metrics`, `prometheus_node_exporter`) — same pattern as `03`, never wire `addon_version` to a `_latest` data source directly. Each addon file keeps its own `_default`/`_latest` data source pair for visibility only.

## ADOT Collector IAM (Pod Identity)

- One IAM role (`pods.eks.amazonaws.com` trust, same shared pattern as every other Pod-Identity role in this project), associated to service account **`adot-collector` in the `default` namespace** — not `kube-system` like most other addons, deliberately matching where the application microservices themselves run.
- One IAM policy covering **all three signals from one role** (all three collector deployments below reuse the same service account): CloudWatch Logs read/write, CloudWatch `PutMetricData`, X-Ray write actions, and AMP actions (`aps:RemoteWrite`/`QueryMetrics`/`GetSeries`/`GetLabels`/`GetMetricMetadata`) scoped to this module's own `aws_prometheus_workspace` ARN specifically, not `"*"`.
- The K8s `ServiceAccount` object itself, plus a `ClusterRole`/`ClusterRoleBinding` (`get`/`list`/`watch` on nodes/pods/services/deployments/etc., plus the `/metrics` non-resource URL) — Pod Identity only *associates* a role with a service-account name, it doesn't create the K8s object or its RBAC; both must be created explicitly here.

## AMP workspace

A single `aws_prometheus_workspace` — this is metrics **storage**, not a collector. Nothing scrapes anything just because the workspace exists. Expose the workspace ID, the `remote_write` endpoint, and the query endpoint as outputs — every downstream collector config needs these.

### AMP recording rules — required for community Grafana dashboards, not optional polish

Standard community Kubernetes dashboards (the `kubernetes-mixin`/kube-prometheus-stack family — e.g. Grafana dashboard IDs 15757/15759/15760/15761) query **precomputed recording-rule metrics** (`node_namespace_pod_container:container_memory_working_set_bytes`, `namespace_workload_pod:kube_pod_owner:relabel`, `node:node_num_cpu:sum`, etc.), not raw scraped metrics. Nothing in this project's ADOT-based collection pipeline computes these — ADOT collectors are pure receiver→processor→exporter pipelines with no rule-evaluation engine. **AMP has its own server-side rule evaluation feature** (`aws_prometheus_rule_group_namespace`) that must be populated with the standard `kubernetes-mixin` recording-rule set (`k8s.rules` + `node.rules` groups) for these dashboards to show any data at all — this isn't AMP configuration polish, it's a hard prerequisite if anyone intends to import one of these dashboards. If implementing this, verify the exact rule expressions against the upstream `kubernetes-mixin` source (https://github.com/kubernetes-monitoring/kubernetes-mixin) rather than reproducing them from memory — the `kube_pod_info`/`kube_pod_owner` join logic is intricate and has shifted across kube-state-metrics versions; a wrong expression won't error, AMP will just silently store an incorrect computed value. This project has no `cluster` label on any of its metrics (single-cluster), so the upstream rules' `cluster` label dimension should be dropped from every `by(...)`/`group_left(...)` clause.

## AMG workspace

- IAM role trusting `grafana.amazonaws.com`, with: read access to AMP (`aps:ListWorkspaces`/`DescribeWorkspace`/`QueryMetrics`/etc.), `sns:Publish` scoped to `arn:aws:sns:*:<account>:grafana*` (alert notifications), and the AWS-managed `AWSXrayReadOnlyAccess` policy.
- `aws_grafana_workspace`: `authentication_providers = ["AWS_SSO"]` (AWS Identity Center — not local Grafana users, not SAML), `permission_type = "CUSTOMER_MANAGED"`, `data_sources = ["PROMETHEUS", "CLOUDWATCH", "XRAY"]`, `unifiedAlerting.enabled = true`, `pluginAdminEnabled = true`.
- Network access is open by default (no `vpc_configuration` block) — add one explicitly if VPC-only access is required; don't assume it's already restricted.
- **Enabling `data_sources = ["PROMETHEUS", ...]` on the workspace only grants IAM *permission* to connect a Prometheus datasource — it does not create or configure the actual datasource connection inside the Grafana app itself.** That's a separate, manual, in-Grafana-UI step (Connections → Data sources → Amazon Managed Service for Prometheus, pointed at this module's AMP workspace/region) that Terraform cannot perform — AMG's datasource configuration isn't exposed via any Terraform-manageable API. Don't assume a working Grafana datasource exists just because this module applied cleanly.

## Critical: collector pipelines are NOT part of this Terraform module

Same pattern as Karpenter's `NodePool`/`EC2NodeClass`: the `OpenTelemetryCollector`/`Instrumentation` custom resources that define actual telemetry pipelines live in a separate, manually-applied, plain-YAML folder (this project's convention: `12_Open_Telemetry/`, three subfolders — Traces, Logs, AMP/AMG metrics — no Terraform, no CI). If asked to implement collection behavior, write these as plain manifests in that sibling structure, not as `kubernetes_manifest` Terraform resources. Expect, at minimum:
- **Traces collector** (`deployment`, 1 replica): OTLP receiver (gRPC 4317 / HTTP 4318), a health-check filter dropping probe/health-endpoint spans (Spring Boot Actuator, ELB health checks, kube-probe, framework-specific health middleware — a long, deliberate filter list, since unfiltered health-check traffic dominates trace volume otherwise), `k8sattributes` enrichment, export to AWS X-Ray.
- **`Instrumentation` CR**: the auto-instrumentation config the ADOT operator's admission webhook injects into annotated pods — points at the traces collector's OTLP endpoint, traces-only for now (metrics/logs exporters explicitly disabled at the SDK level, since those signals go through the separate collectors below, not SDK auto-instrumentation).
- **Logs collector** (`daemonset`, one per node): tails `/var/log/pods/*/*/*.log` (needs `runAsUser: 0` to read host log files), excludes its own and `kube-system`'s logs, exports to CloudWatch Logs.
- **Metrics collector** (`deployment`, 1 replica): a full Prometheus-compatible scrape config (apiserver, nodes, cAdvisor, annotated services/pods) plus an OTLP receiver, `remote_write`s to AMP via `sigv4auth` (SigV4-signs using the pod's own Pod Identity credentials — no separate AMP credential needed).

**Known gotcha if implementing the metrics collector's scrape config**: community dashboards expect `job` labels matching kube-prometheus-stack convention (`kube-state-metrics`, `node-exporter`, `cadvisor`) — a raw/generic Prometheus scrape config (the kind copied from Prometheus's own docs, using discovery-role-based job names like `kubernetes-service-endpoints`/`kubernetes-nodes-cadvisor`) will *not* produce those labels by default, since `kubernetes-service-endpoints` is a shared job scraping every `prometheus.io/scrape`-annotated service (kube-state-metrics and node-exporter both included) under one generic job name. Add `relabel_configs` renaming the `job` label based on `__meta_kubernetes_service_name` (conditional — can't blanket-rename the shared endpoints job) for `kube-state-metrics`/`prometheus-node-exporter` specifically, and an unconditional job-label override for the cadvisor-dedicated node job.

**Also expect to need a manual pod restart after applying/updating the `Instrumentation` CR** — the injection webhook only fires at pod creation time; a helper script restarting the application deployments/rollouts after applying this CR is a reasonable thing to include alongside it, not an afterthought.

**AMP remote-write endpoint / workspace ID referenced by the metrics collector YAML should read from this module's Terraform output where possible** — hardcoding the workspace ID directly in the manifest (as opposed to interpolating a Terraform output at apply time) creates a silent-drift risk if the AMP workspace is ever destroyed and recreated with a new ID; nothing will error, metrics will just silently stop reaching AMP.

## Repo-wide conventions this module must follow

- File naming: underscore convention (`c1_versions.tf`, matching `04`, not `03`'s hyphens).
- Variables/naming: `business_division` + `project_name`, same `local.name` prefix pattern.
- Remote state key: `GleamGoods/opentelemetry/terraform.tfstate`.
- Providers: `helm`/`kubernetes` via `data.aws_eks_cluster_auth`, same pattern as `03`/`04`.

## CI/CD

Same three-stage pattern (`TF-05_OpenTelemetry`, Trivy → plan → manual-approval apply via GitHub Environment `05-OpenTelemetry-Apply`), OIDC via the role from `01_remote_backend_s3bucket`. Covers this module's Terraform only — does not apply anything under `12_Open_Telemetry/`; that stays a manual step.

## Explicitly out of scope

- `OpenTelemetryCollector`/`Instrumentation` CRs — covered above, deliberately not Terraform.
- The AMG Grafana **datasource** configuration itself — covered above, not Terraform-manageable at all.
- Any application-side instrumentation annotations (`instrumentation.opentelemetry.io/inject-sdk`) — those live in the application Helm charts in the separate app repo, not here.
