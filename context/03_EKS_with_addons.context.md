# Context: `03_EKS_with_addons` Terraform module

You are senior devops engineer, and bellow is the complete brief for implementing (or re-implementing) the EKS-cluster-and-addons module of the GleamGoods-DevOps project.

## Purpose

Creates the EKS cluster itself, its baseline static node group, and every cluster-wide controller/add-on the rest of the platform depends on: Pod Identity, the AWS Load Balancer Controller, EBS CSI, ExternalDNS, the Secrets Store CSI Driver + AWS provider, metrics-server, Reloader, and (as of the latest addition) native NetworkPolicy enforcement via `vpc-cni`. This is the single largest module in the project — it provisions both the control-plane infrastructure and the cluster-level software layer on top of it. Everything downstream (`04_EKS_Karpenter`, `05_OpenTelemetry`, `08_AWS_managed_databases`, and the application workloads) depends on this module existing first.

Consumes `02_VPC`'s outputs via `data.terraform_remote_state` (VPC ID, private/public subnet IDs). Produces the cluster name/id/endpoint/CA-data/security-group-id that every other module downstream reads back via the same mechanism.

## Cluster core — hard requirements

- **1 EKS cluster**, control-plane ENIs in the private subnets from `02_VPC`. Control-plane role trusts `eks.amazonaws.com`, attached `AmazonEKSClusterPolicy` + `AmazonEKSVPCResourceController`.
- **Logging**: all 5 log types enabled (`api`, `audit`, `authenticator`, `controllerManager`, `scheduler`) — not a subset.
- **`kubernetes_network_config.service_ipv4_cidr`** must be a separate address range from the VPC's own CIDR (e.g. VPC is `10.0.0.0/16`, service CIDR is `172.20.0.0/16`) — no overlap.
- **`access_config`**: `authentication_mode = "API_AND_CONFIG_MAP"` (both the legacy aws-auth ConfigMap and the newer Access Entries API — deliberate, not a leftover: keeps the old path working while being future-ready for AWS's direction), `bootstrap_cluster_creator_admin_permissions = true` (whichever AWS identity runs the first `terraform apply` automatically gets cluster-admin — this is how the human operator gets in; nothing else grants human access by default).
- **1 static managed node group** in the private subnets, alongside (not instead of) Karpenter (`04_EKS_Karpenter`, separate module) — this node group is baseline capacity that exists even if Karpenter isn't running. Node IAM role: `AmazonEKSWorkerNodePolicy`, `AmazonEKS_CNI_Policy`, `AmazonEC2ContainerRegistryReadOnly`.
- **Subnet tags — re-applied here on top of what `02_VPC` already set**, via `aws_ec2_tag` (not by editing the VPC module): `kubernetes.io/role/elb`=`1` (public), `kubernetes.io/role/internal-elb`=`1` (private), and `kubernetes.io/cluster/<cluster_name>`=`"owned"` (both). **Use `"owned"`, not `"shared"`** — same reasoning as the VPC module's own tags: Karpenter and the managed node group both need `"owned"` to launch EC2 instances / attach ENIs into these subnets; `"shared"` only permits the control plane to use them. This is intentionally a second, redundant tagging pass on top of the VPC module's own tags, not a bug.
- **Public endpoint**: `cluster_endpoint_public_access_cidrs = ["0.0.0.0/0"]`, `cluster_endpoint_private_access = false` as the current state. **This is a known, deliberately deferred decision, not an oversight** — restricting the public endpoint (or switching to `cluster_endpoint_private_access = true`) was investigated and explicitly deferred to the *next* full cluster destroy/recreate cycle, specifically because narrowing `cluster_endpoint_public_access_cidrs` alone (with private access still off) would require also tracking and allow-listing the VPC's NAT Gateway EIPs (since with private access off, in-cluster control-plane traffic also egresses through the public endpoint) — a fragile approach that was tried and reverted. Don't "fix" this unprompted; if asked to harden it, the already-decided direction is: enable `cluster_endpoint_private_access = true` first (so in-cluster traffic uses AWS's private path via the Route53-managed private hosted zone, decoupled from the public CIDR list), and only then narrow the public CIDR list — and separately resolve how CI (GitHub-hosted runners, no fixed IP) reaches the API server once that CIDR is narrowed (self-hosted runner in-VPC, or accept CI keeps broad access).

## Pod Identity — the exclusive AWS-auth mechanism

Every addon/controller in this project that needs AWS permissions uses **EKS Pod Identity** (`aws_eks_pod_identity_association`), never IRSA. One shared trust-policy document (`pods.eks.amazonaws.com` as principal, `sts:AssumeRole` + `sts:TagSession`) is reused across every per-addon IAM role in this module — define it once, reference it everywhere, don't duplicate it per addon. The `eks-pod-identity-agent` addon must be installed before anything using `aws_eks_pod_identity_association` — everything else in this module that grants AWS permissions to a pod depends on it implicitly.

## Addons/controllers — one by one

| Addon | Install method | Namespace/SA | IAM | Notes |
|---|---|---|---|---|
| Pod Identity Agent | `aws_eks_addon` (`eks-pod-identity-agent`) | — | none (it's what makes Pod Identity work) | Install first, everything else depends on it |
| EBS CSI Driver | `aws_eks_addon` (`aws-ebs-csi-driver`) | `kube-system` / `ebs-csi-controller-sa` | `AmazonEBSCSIDriverPolicy` via Pod Identity | Needed for any `PersistentVolumeClaim` |
| ExternalDNS | `aws_eks_addon` (`external-dns`) | `external-dns` / `external-dns` | `AmazonRoute53FullAccess` via Pod Identity | Turns Ingress hosts into real Route53 records |
| metrics-server | `aws_eks_addon` (`metrics-server`) | — | none | Source of truth for every HPA and `kubectl top` |
| **`vpc-cni`** | `aws_eks_addon` (`vpc-cni`) | — | none needed beyond what's already on the node role (`AmazonEKS_CNI_Policy`, node-scoped, not Pod-Identity-scoped — see below) | **Must be explicitly adopted as a Terraform-managed addon, not left as EKS's default self-managed install** — see dedicated section below |
| AWS Load Balancer Controller | `helm_release` (`aws-load-balancer-controller` chart) | `kube-system` / `aws-load-balancer-controller` | Custom policy, fetched live (see below) | Actually provisions the ALB/NLB behind Ingress objects |
| Secrets Store CSI Driver | `helm_release` (`secrets-store-csi-driver` chart) | `kube-system` | none itself | Generic CSI framework; delegates AWS-specific work to ASCP |
| AWS Secrets & Config Provider (ASCP) | `helm_release` (`secrets-store-csi-driver-provider-aws` chart) | `kube-system` | none of its own — uses whatever Pod Identity role the *consuming* pod's service account has | The provider plugin the CSI driver calls into over a local socket |
| Stakater Reloader | `helm_release` (`reloader` chart) | `kube-system` | none | Watches Secret/ConfigMap, rolling-restarts annotated workloads |

### `vpc-cni` — special case, do this deliberately

EKS bootstraps a self-managed `vpc-cni` DaemonSet automatically on cluster creation, completely outside Terraform's or the EKS Addon system's tracking. **This module must explicitly adopt it as a real `aws_eks_addon` resource** — not because it needs to exist (it already does), but because `configuration_values` (specifically `enableNetworkPolicy = "true"`, which deploys the AWS Network Policy Agent and is what makes any `NetworkPolicy` object in the cluster actually get enforced) is *only* configurable through the EKS Addon management layer, never on a plain self-managed installation. Use `resolve_conflicts_on_create = "OVERWRITE"` — required specifically because this is adopting an addon that's already running unmanaged; without it, Terraform will fail trying to install "over" the existing installation. Expect the addon-managed version to differ from (likely newer than) whatever self-managed version the cluster started with — that's a real, expected CNI version bump as a side effect of adoption, not an error. No node group or IAM role changes are needed alongside this — the node group's existing `AmazonEKS_CNI_Policy` attachment already covers everything `vpc-cni` needs (it's fundamentally node-scoped infrastructure plumbing, authenticated via the EC2 instance's own IAM role, not per-pod Pod Identity — unlike every other addon in this table).

### AWS Load Balancer Controller — IAM policy is fetched live, not hardcoded

The LBC's IAM policy document is pulled fresh on every `plan`/`apply` from `data "http"` pointed at `https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/main/docs/install/iam_policy.json` (the `main` branch, so it can drift over time as upstream updates it) — not copy-pasted into this repo as a static JSON file. This is deliberate: it keeps the policy in sync with whatever chart version is actually installed, at the cost of the policy silently changing between applies if upstream updates that file. Preserve this pattern rather than vendoring a static copy, unless explicitly asked to pin it for reproducibility.

### Addon versions are pinned — every `aws_eks_addon`, no exceptions

All `aws_eks_addon` resources in this module (`pod_identity_agent`, `ebs_csi`, `external_dns`, `metrics_server`, `vpc_cni`) pull `addon_version` from a single `var.addon_versions` object, not from `data.aws_eks_addon_version...most_recent = true`. Every addon file still keeps a `_default`/`_latest` `data "aws_eks_addon_version"` pair alongside the pinned one — those are for visibility only (their outputs tell you when a newer version exists via `terraform output`), they do not drive what actually installs. Never wire `addon_version` directly to a `_latest` data source — every version bump must be a deliberate, reviewed change to `var.addon_versions`'s defaults.

### Secrets Store CSI Driver — non-default Helm values that are load-bearing

Three Helm values on this specific release matter beyond the chart defaults, and removing any of them breaks the DB-secret-rotation system in `08_AWS_managed_databases`:
- `tokenRequests[0].audience = pods.eks.amazonaws.com` — without this, pods fail to mount CSI secrets at all under Pod Identity.
- `enableSecretRotation = true` + `rotationPollInterval = "2m"` — **not on by default.** `syncSecret.enabled` alone only re-reads the source secret when a pod (re)mounts the volume (pod start only); without the rotation-poll settings, a value rotated in Secrets Manager would never reach a synced Kubernetes `Secret` (or trigger Reloader) until every consuming pod happened to restart for an unrelated reason.

### ASCP — installed after the CSI driver, doesn't reinstall it

The ASCP chart (`secrets-store-csi-driver-provider-aws`) can optionally bundle the generic CSI driver as a subchart dependency. Set `secrets-store-csi-driver.install = false` on this release specifically because `c16-01` already installs it as its own separate release — installing it twice conflicts. `depends_on` the CSI driver's `helm_release` explicitly.

### Reloader — `isArgoRollouts`

`reloader.isArgoRollouts = "true"` is required because workloads in this project are Argo `Rollout` objects (`argoproj.io/Rollout`), not plain `Deployment`s — without this setting Reloader doesn't know how to trigger a restart of a Rollout.

## EKS access entries beyond the cluster creator

The bootstrap-creator admin grant (above) only covers whichever identity ran the cluster's *first* apply. Any other principal that needs to reach the Kubernetes API — including CI roles that manage `helm_release`/`kubernetes_*` Terraform resources in this or other modules — needs its own explicit `aws_eks_access_entry` + `aws_eks_access_policy_association`. Concretely: the GitHub Actions Terraform CI role (`github-actions-terraform-role-gleamgoods-devops`, defined in `01_remote_backend_s3bucket`) needs an access entry here with `AmazonEKSClusterAdminPolicy` (`access_scope.type = "cluster"`) — its broad AWS-side `AdministratorAccess` IAM policy is a *separate* permission system from Kubernetes RBAC/Access Entries, and grants it nothing on the Kubernetes API side by itself. Without this, any CI-driven `plan`/`apply` touching `helm_release` or `kubernetes_*` resources anywhere in this module (or any module using the `helm`/`kubernetes` providers against this cluster) fails with `Unauthorized` the moment it tries to refresh those resources' state — not just on resources it's trying to create. Since this module itself owns several `helm_release`/`kubernetes_*` resources, **the very first time this access entry is added, it must be applied locally/manually** — CI can't bootstrap its own Kubernetes-API access, the same chicken-and-egg shape as `01_remote_backend_s3bucket`'s OIDC role.

## Providers

`helm` and `kubernetes` providers authenticate against this module's own cluster using a short-lived token from `data.aws_eks_cluster_auth`, fetched fresh on every plan/apply — not a static kubeconfig file.

## Repo-wide conventions this module must follow

- File naming: `c1-versions.tf` ... incrementing, grouped by concern (`c11`–`c19` are one file per addon/controller, roughly one number per addon plus sub-numbered files for multi-resource addons like LBC's `c14-01` through `c14-04`). New additions continue the sequence (`c20`, `c21`) rather than being squeezed into existing numbers.
- Variables: `aws_region`, `aws_region_remote_state`, `project_name` (default `gleamgoods`), `business_division` (default `retail`) — this module *does* use the `business_division` + `project_name` naming pair (unlike `02_VPC`, which is `project_name`-only — see that module's context file for the divergence). Naming convention here: `local.name = "${business_division}-${project_name}"` (e.g. `retail-gleamgoods`), used as a prefix for nearly every resource name.
- Remote state: same S3 bucket, key `GleamGoods/eks/terraform.tfstate`.
- Outputs consumed downstream: cluster name/id/version/endpoint/CA-data/security-group-id, node group name, node IAM role ARN — read by `04_EKS_Karpenter`, `05_OpenTelemetry`, `08_AWS_managed_databases`, and others via `data.terraform_remote_state`.

## CI/CD

Same three-stage pattern as every CI-applied module (`TF-03_EKS_with_addons`, Trivy secret scan → plan → manual-approval-gated apply via GitHub Environment `03-EKS-with-addons-Apply`), OIDC auth via the role from `01_remote_backend_s3bucket`. One real constraint specific to this module: **the very first apply of anything this module's CI needs Kubernetes-API access for (the access-entry addition above, or any brand-new `helm_release`) can't be CI's first attempt at it** — it has to be applied locally first, same reasoning as the access-entry section above.

## Explicitly out of scope / deferred

- **`cluster_endpoint_private_access` / narrowing the public CIDR list** — see the Cluster core section above. Deferred to the next full cluster destroy/recreate, not to be picked up unprompted.
- **VPC interface endpoints (PrivateLink)** for Secrets Manager/STS/SQS/etc. don't exist in this project — addon/controller traffic to those AWS APIs leaves the VPC via NAT Gateway to AWS's public regional endpoints. Not this module's concern to fix, but relevant if anyone tries to write a `NetworkPolicy` expecting that traffic to stay inside the VPC CIDR (it won't, without those endpoints).
- **Calico/Cilium** were considered and explicitly not chosen for NetworkPolicy enforcement — the native `vpc-cni` network-policy-agent path was chosen instead specifically because this project is AWS-native throughout. Don't introduce a third-party CNI/policy engine without a deliberate reason to revisit that choice.
- **`NetworkPolicy` objects themselves are not part of this module** — this module only enables the *capability* to enforce them (`enableNetworkPolicy`); the actual policies live in a separate, manually-applied manifests folder (`13_RBAC_NetworkPolicy/`), same pattern as Karpenter's `NodePool`/`EC2NodeClass` and OpenTelemetry's collector configs living outside their respective Terraform modules.
