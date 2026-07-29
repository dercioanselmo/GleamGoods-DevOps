# 05 — OpenTelemetry

Installs the observability platform for the EKS cluster: AWS Distro for OpenTelemetry (ADOT) Operator, cert-manager (required by the ADOT Operator), two supporting metrics add-ons, an Amazon Managed Prometheus (AMP) workspace, and an Amazon Managed Grafana (AMG) workspace. Together, these components provide the foundation for collecting metrics, logs, and traces from workloads running in the cluster. ADOT Collectors deployed later export telemetry to AWS-native backends such as Amazon Managed Prometheus, CloudWatch Logs, and AWS X-Ray, while Amazon Managed Grafana provides a single interface for visualizing and querying that data.

Like `04_EKS_Karpenter`, this module only installs the **platform** (the operator, IAM, the AMP/AMG workspaces). It does **not** define what gets collected or how — that's a set of Kubernetes custom resources applied separately, covered below.

Consumes:
- `02_VPC` (`data.terraform_remote_state.vpc`) — VPC context.
- `03_EKS_with_addons` (`data.terraform_remote_state.eks`) — cluster name/id/version/endpoint/CA data, for the `helm`/`kubernetes` providers and for resolving the correct addon version per Kubernetes version.

## EKS addons

| Addon | What it does | Depends on |
|---|---|---|
| `aws_eks_addon.cert_manager` (`c6_04`) | Issues/manages TLS certificates inside the cluster — required by the ADOT addon below, which uses cert-manager to provision the webhook certificate for its own admission webhook | — |
| `aws_eks_addon.adot` (`c6_05`) | The ADOT **operator** — watches for `OpenTelemetryCollector`/`Instrumentation` custom resources and reconciles them into running collector pods / auto-instrumentation webhooks. Installing this addon does not, by itself, collect anything — it just makes the CRDs functional | `aws_eks_addon.cert_manager` (explicit `depends_on`) |
| `aws_eks_addon.prometheus_node_exporter` (`c6_06`) | DaemonSet exposing node-level hardware/OS metrics (CPU, memory, disk, network) in Prometheus format, on every node | — |
| `aws_eks_addon.kube_state_metrics` (`c6_07`) | Exposes the *state* of Kubernetes objects (Deployment replica counts, Pod status, etc.) as Prometheus metrics — different from node_exporter, which is about the host, not Kubernetes object state | — |

**Addon versions are pinned**, same pattern as `03_EKS_with_addons` — all four pull from `var.addon_versions` (`c2_variables.tf`):

```hcl
variable "addon_versions" {
  default = {
    adot                     = "v0.151.0-eksbuild.2"
    cert_manager             = "v1.21.0-eksbuild.2"
    kube_state_metrics       = "v2.19.1-eksbuild.2"
    prometheus_node_exporter = "v1.11.1-eksbuild.7"
  }
}
```

Each addon file still keeps a `_default`/`_latest` `data "aws_eks_addon_version"` pair — they no longer drive `addon_version` (that's `var.addon_versions.*` now), but their outputs are the way to check whether a newer version exists (see `03_EKS_with_addons/README.md`'s "Pinned version map" for the exact `terraform output` commands — note this module doesn't yet expose `_latest` as a Terraform `output{}` itself, so checking today means `terraform state show` on the data source or the `aws eks describe-addon-versions` CLI fallback documented there).

## ADOT Collector IAM (Pod Identity)

| Resource | What it does |
|---|---|
| `aws_iam_role.adot_collector` (`c6_01`) | Role any ADOT collector pod runs as. Trust policy: `pods.eks.amazonaws.com` (Pod Identity, same pattern as everything else in this project) |
| `aws_iam_policy.adot_collector` (`c6_02`) | CloudWatch Logs read/write (`PutLogEvents`, `CreateLogGroup`/`Stream`, `Describe*`, `Get*`, `Filter*`), CloudWatch `PutMetricData`, X-Ray write actions, and AMP actions (`aps:RemoteWrite`, `QueryMetrics`, `GetSeries`, `GetLabels`, `GetMetricMetadata`) scoped to this module's own `aws_prometheus_workspace.amp.arn` — this one role covers all three signals (traces, logs, metrics), since the same service account is reused across all three collector deployments below |
| `aws_eks_pod_identity_association.adot_collector` (`c6_03`) | Associates the role with service account `adot-collector` in the `default` namespace — **not** `kube-system` like most other addons, matching where the application microservices themselves run |
| `kubernetes_service_account_v1.adot_collector` + `kubernetes_cluster_role_v1`/`_role_binding_v1.otel_collector` (`c6_09`) | The actual K8s `ServiceAccount` object (Pod Identity only associates an IAM role with a service account name — something still has to create the K8s object itself), plus cluster-wide RBAC (`get`/`list`/`watch` on nodes/pods/services/deployments/etc., plus the `/metrics` non-resource URL) so the collector can scrape Kubernetes and Prometheus-annotated pods |

## Amazon Managed Prometheus (AMP) — `c7_amp_prometheus_workspace.tf`

A single `aws_prometheus_workspace.amp` — this is the **metrics storage backend**, not a collector. Nothing scrapes anything just because this workspace exists; a collector (see below) has to be configured to `remote_write` into it. Outputs expose the workspace ID and both the remote-write and query API endpoints.

## Amazon Managed Grafana (AMG) — `c8_01`–`c8_03`

- `aws_iam_role.amg_iam_role` + 3 policy attachments — Grafana's own service role (trust: `grafana.amazonaws.com`), with read access to AMP (`aps:ListWorkspaces`/`DescribeWorkspace`/`QueryMetrics`/etc.), `sns:Publish` scoped to `arn:aws:sns:*:<account>:grafana*` (for alert notifications), and the AWS-managed `AWSXrayReadOnlyAccess` policy (so Grafana can query traces, not just metrics).
- `aws_grafana_workspace.main` — `authentication_providers = ["AWS_SSO"]` (AWS Identity Center, not local Grafana users/passwords or SAML), `permission_type = "CUSTOMER_MANAGED"` (we manage who gets in, not AWS), `data_sources = ["PROMETHEUS", "CLOUDWATCH", "XRAY"]` — all three observability signals are queryable from this one workspace. `unifiedAlerting.enabled = true` and `pluginAdminEnabled = true`.
- **Network access is currently open** (no `vpc_configuration` block) — the comment in `c8_03` flags this explicitly; if we want AMG restricted to VPC-only access, that block needs adding.

## Important: what actually gets collected lives in `12_Open_Telemetry/`, applied manually

Exactly the same pattern as `04_EKS_Karpenter`'s `09_KARPENTER_k8s-manifests/`: this Terraform module installs the ADOT **operator** and the IAM/AMP/AMG **platform**, but the `OpenTelemetryCollector`/`Instrumentation` custom resources that actually define pipelines — what's received, how it's processed, where it's exported — live in **`12_Open_Telemetry/`**, a plain folder of YAML with **no Terraform, no CI workflow** behind it. Applied by hand, `kubectl apply -f <file>`.

Three independent collector pipelines, one per signal:

| Folder | Collector | Mode | What it does |
|---|---|---|---|
| `01_OpenTelemetry_Traces/` | `adot-traces` | `deployment`, 1 replica | Receives OTLP traces (gRPC 4317 / HTTP 4318) from every microservice's auto-instrumentation, filters out health-check/probe spans (Spring Boot Actuator, ELB health checks, kube-probe, NestJS/Express health endpoints — a fairly involved filter list, since unfiltered health-check traffic would otherwise dominate trace volume), enriches with `k8sattributes` (namespace/pod/deployment/node), batches, and exports to **AWS X-Ray** |
| `01_OpenTelemetry_Traces/02_adot_instrumentation_traces.yaml` | `Instrumentation` CR `default-instrumentation` | — | Not a collector — this is the auto-instrumentation config the ADOT operator's admission webhook uses to inject the OTel SDK into annotated pods. Points every instrumented app at `http://adot-traces-collector:4318`. Traces only for now — `OTEL_METRICS_EXPORTER`/`OTEL_LOGS_EXPORTER` are explicitly `"none"` here (metrics/logs are handled by the separate collectors below, not via SDK auto-instrumentation) |
| `02_OpenTelemetry_Logs/` | `adot-logs` | `daemonset` (one pod per node) | Tails `/var/log/pods/*/*/*.log` on the host filesystem (`runAsUser: 0` — needs root to read container log files), excludes its own and `kube-system`'s logs to cut noise, enriches with `k8sattributes`, and exports to **CloudWatch Logs** (`/aws/eks/gleamgoods-eks/application`, single log stream) |
| `03_OpenTelemetry_AMP_AMG/` | `adot-metrics-prometheus` | `deployment`, 1 replica | The most complex of the three — runs a full Prometheus-compatible scrape config (apiserver, nodes, cAdvisor, annotated services/pods, both fast and "slow" 5-minute job variants) plus an `otlp` receiver, batches, and `remote_write`s to **AMP** via `sigv4auth` (SigV4-signs the request using the pod's Pod Identity credentials — no separate AMP credential needed) |

**Two things worth flagging, since they're not obvious from the Terraform side alone:**

1. **The AMP remote-write endpoint in `03_OpenTelemetry_AMP_AMG/01_adot_collector_prometheus_full_k8s_cluster.yaml` is a hardcoded workspace ID** (`ws-031ed12a-...`), not read from this module's `amp_endpoint` output. Same pattern/risk as `04_EKS_Karpenter`'s hardcoded node-role ARN in its `EC2NodeClass` — if the AMP workspace is ever destroyed and recreated (new workspace ID), this file needs a manual update, and nothing will error if we forget; metrics will just silently stop reaching AMP. The verification script (`02_verify_amp_metrics.sh`) has the same hardcoded ID.
2. **After applying/updating the `Instrumentation` CR, running microservices need a restart** to pick up the auto-instrumentation webhook (it only injects at pod creation time) — `01_OpenTelemetry_Traces/03_restart-retailapp.sh` / `02_OpenTelemetry_Logs/02_restart-retailapp.sh` do `kubectl rollout restart` on all five microservices for exactly this reason. Easy to forget on a fresh cluster: applying the `Instrumentation` CR alone does nothing to already-running (or not-yet-deployed) pods.

Application-side wiring for this: every microservice's chart sets `instrumentation.opentelemetry.io/inject-sdk: <name>` as a pod annotation when `opentelemetry.enabled = true` (see `03_EKS_with_addons/README.md`'s pod-annotation notes, or any of the app charts' `deployment.yaml`/`rollout.yaml`) — that annotation is what the ADOT operator's webhook looks for to decide whether to inject.

## Providers

Same pattern as `03`/`04`: `c5_helm_and_kubernetes_providers.tf` configures `helm`/`kubernetes` against this module's own `data.terraform_remote_state.eks` outputs, short-lived token via `data.aws_eks_cluster_auth`.

## Variables

Full list in `c2_variables.tf`; overridden in `terraform.tfvars`:

| Name | Value |
|---|---|
| `aws_region` | `us-east-1` |
| `project_name` | `gleamgoods` |
| `business_division` | `retail` |
| `tags` | `{ Terraform, Environment, Project, ManagedBy }` |
| `addon_versions` | see table above — not overridden in `.tfvars`, code defaults are what's live |

## Outputs

```
adot_collector_role_arn        = arn:aws:iam::****:role/retail-gleamgoods-adot-collector-role
adot_addon_id / adot_addon_version                    = adot addon identity + pinned version
prometheus_node_exporter_addon_id / _version
kube_state_metrics_addon_id / _version
amp_workspace_id               = ws-****
amp_endpoint                   = https://aps-workspaces.us-east-1.amazonaws.com/workspaces/ws-****/api/v1/remote_write
amp_query_endpoint             = https://aps-workspaces.us-east-1.amazonaws.com/workspaces/ws-****/api/v1/query
amg_iam_role_arn / amg_iam_role_name
amg_workspace_id / _arn / _endpoint / _url            = https://****.grafana-workspace.us-east-1.amazonaws.com
vpc_id / private_subnet_ids / public_subnet_ids       = passthrough of 02_VPC's outputs
eks_cluster_name / eks_cluster_id                     = passthrough of 03_EKS_with_addons's outputs
```

## CI/CD

`.github/workflows/terraform-05-opentelemetry.yaml`, triggered by pushes to `main` touching `05_OpenTelemetry/**`. Same three-stage pipeline: Trivy secret scan → Terraform Plan (`tfplan-05-opentelemetry`) → Terraform Apply, gated behind the `05-OpenTelemetry-Apply` GitHub Environment. AWS auth via OIDC (`github-actions-terraform-role-gleamgoods-devops`, from `01_remote_backend_s3bucket`) — no static keys. Corresponding `terraform-05-opentelemetry-destroy.yaml` for teardown.

This CI/CD covers this module's Terraform only — it does **not** apply anything under `12_Open_Telemetry/`; those three collector pipelines remain a manual `kubectl apply` step, same caveat as `04_EKS_Karpenter`'s NodePool/EC2NodeClass.

## State

Remote, same backend bucket, key `GleamGoods/opentelemetry/terraform.tfstate`.

## Destroy order

Must be destroyed **before** `03_EKS_with_addons` (depends on the EKS cluster existing) and **before** `02_VPC`. Before destroying, delete the `OpenTelemetryCollector`/`Instrumentation` resources under `12_Open_Telemetry/` first (`kubectl delete -f 12_Open_Telemetry/... -R`) — same reasoning as Karpenter's NodePools: those objects aren't Terraform-managed, so destroying this module won't clean them up on its own, though in this case (unlike Karpenter, which owns live EC2 instances) leaving them behind mostly just means stale pods rather than orphaned billable AWS resources.
