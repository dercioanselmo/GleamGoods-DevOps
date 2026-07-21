# 03 — EKS with Addons

Creates the EKS cluster itself, its managed (static) node group, and every cluster-wide controller/addon. The rest of the stack depends on: Pod Identity, the Load Balancer Controller, EBS CSI, ExternalDNS, the Secrets Store CSI driver + AWS provider, metrics-server, and Reloader. This is the biggest module in the project — everything in it either builds the cluster or installs something cluster-wide onto it.

Reads `02_VPC`'s state (VPC ID, subnet IDs) via `data.terraform_remote_state`. Its own outputs are read by `04_EKS_Karpenter`, `05_OpenTelemetry`, and `08_AWS_managed_databases`.

Currently Live cluster: `retail-gleamgoods-eks`, Kubernetes `1.35`, endpoint `https://2230D9910377A9D6D2722F3EFE0D767A.gr7.us-east-1.eks.amazonaws.com`.

## Cluster core

| Resource | What it does |
|---|---|
| `aws_iam_role.eks_cluster` | Control-plane role, trusts `eks.amazonaws.com`, gets `AmazonEKSClusterPolicy` + `AmazonEKSVPCResourceController` |
| `aws_eks_cluster.main` | The cluster. Control plane ENIs go in the private subnets from `02_VPC`. Logging: all 5 log types enabled (`api`, `audit`, `authenticator`, `controllerManager`, `scheduler`) |
| `aws_ec2_tag.eks_subnet_tag_*` (4 resources) | Tags every VPC subnet `kubernetes.io/cluster/retail-gleamgoods-eks = owned` (both public and private — see note below) plus the ELB role tags. This is a second, cluster-specific layer of tagging on top of what `02_VPC` already applies |
| `aws_iam_role.eks_nodegroup_role` + 3 policy attachments | Node role: `AmazonEKSWorkerNodePolicy`, `AmazonEKS_CNI_Policy`, `AmazonEC2ContainerRegistryReadOnly` |
| `aws_eks_node_group.private_nodes` | The **static** managed node group — `m7i-flex.large`, `ON_DEMAND`, desired 3 / min 1 / max 6, in the private subnets. This coexists with Karpenter (`04_EKS_Karpenter`), which provisions its *own* dynamic nodes separately — this node group is the baseline capacity that exists even if Karpenter isn't running |

**"owned" vs "shared" subnet tags:** In the `c5_eks_tags.tf`, was deliberately changed from `shared` to `owned` on *both* public and private subnets, because Karpenter and the managed node group both need `owned` to launch EC2 instances / attach ENIs — `shared` would only let the control plane use the subnet, not launch workers into it.

**Public endpoint access:** `cluster_endpoint_public_access_cidrs = ["0.0.0.0/0"]` and `cluster_endpoint_private_access = false` (both in `terraform.tfvars`) — the EKS API server's public endpoint is reachable from **any IP on the internet**, and there is no private/VPC-internal path to it at all. IAM auth is still required to actually do anything, but network-level access is fully open. Worth a deliberate look if this ever needs tightening (e.g. restricting `cluster_endpoint_public_access_cidrs` to known office/VPN IPs).

**Primary cluster-admin:** `access_config.bootstrap_cluster_creator_admin_permissions = true` — whichever AWS identity's credentials ran the `terraform apply` that *created* the cluster automatically has cluster-admin. `cluster_authentication_mode = "API_AND_CONFIG_MAP"` keeps both the legacy `aws-auth` ConfigMap and the newer EKS Access Entries API active simultaneously.

## Pod Identity (not IRSA)

Every addon/controller in this project that needs AWS permissions uses **EKS Pod Identity** (`aws_eks_pod_identity_association`), I evolved from the older IRSA/OIDC-provider pattern. The shared trust policy (`c13-podidentity-assumerole.tf`) lets principal `pods.eks.amazonaws.com` assume any of these roles; each individual role is scoped to one specific namespace + service account. `aws_eks_addon.podidentity` (the Pod Identity Agent addon itself) has to be installed before anything using pod identity can actually authenticate — most other resources in this module `depends_on` it.

This same pattern (and the same `assume_role` document) is reused in `08_AWS_managed_databases` for the DB-secret Pod Identity roles.

## Addons installed

| Addon / controller | What it does | Install method | Namespace / SA | IAM |
|---|---|---|---|---|
| Pod Identity Agent | Runs on every node; hands out short-lived AWS credentials to pods via Pod Identity associations, so pods can call AWS APIs without static keys | `aws_eks_addon` (`eks-pod-identity-agent`) | — | none needed (it's what makes Pod Identity work) |
| EBS CSI Driver | Lets pods claim EBS-backed `PersistentVolume`s (dynamic provisioning, attach/detach) — needed for anything using a `PersistentVolumeClaim` | `aws_eks_addon` (`aws-ebs-csi-driver`) | `kube-system` / `ebs-csi-controller-sa` | `AmazonEBSCSIDriverPolicy` via Pod Identity |
| ExternalDNS | Watches Ingress/Service objects and automatically creates/updates matching Route53 DNS records — this is what turns an Ingress host into a resolvable domain name | `aws_eks_addon` (`external-dns`) | `external-dns` / `external-dns` | `AmazonRoute53FullAccess` via Pod Identity |
| metrics-server | Collects CPU/memory usage from every pod and node; the source of truth `kubectl top` and every `HorizontalPodAutoscaler` in this project reads from | `aws_eks_addon` (`metrics-server`) | — | none |
| AWS Load Balancer Controller | Watches Ingress/Service objects and provisions real AWS ALBs/NLBs to match — this is what actually creates the load balancer behind `ui`'s | `helm_release` (`aws-load-balancer-controller` chart) | `kube-system` / `aws-load-balancer-controller` | Custom policy — see below |
| Secrets Store CSI Driver | Generic CSI framework for mounting secrets from an external secrets store into pods as a volume; the actual "talk to AWS" part is delegated to the ASCP provider below | `helm_release` (`secrets-store-csi-driver` chart) | `kube-system` | none itself; the ASCP provider below does the AWS calls |
| AWS Secrets & Config Provider (ASCP) | The AWS-specific plugin for the CSI driver above — this is what actually fetches values from Secrets Manager/SSM Parameter Store when a `SecretProviderClass` references them | `helm_release` (`secrets-store-csi-driver-provider-aws` chart) | `kube-system` | uses whatever Pod Identity role the *consuming* pod's service account has (per-app roles live in `08_AWS_managed_databases`) |
| Stakater Reloader | Watches `Secret`/`ConfigMap` objects and rolling-restarts any workload annotated to opt in, whenever the referenced data changes. Specifically using to manage zero downtime for secrets rotation | `helm_release` (`reloader` chart) | `kube-system` | none |

**Every `aws_eks_addon` here uses `data.aws_eks_addon_version...most_recent = true`** — none of these addon versions are pinned. Every `terraform apply` picks up whatever AWS currently considers "latest" for the cluster's Kubernetes version at that moment, which means an addon can silently upgrade on a routine `apply` that touches this module for an unrelated reason. This was observed directly during this session: `externaldns_addon_version` moved from `v0.21.0-eksbuild.5` to `.6` between two applies with no corresponding code change. If reproducible/pinned versions ever matter, switch these to `data.aws_eks_addon_version...default` (still auto-tracks the *recommended* version for the cluster version, but moves less aggressively) or a hardcoded `addon_version`.

**LBC's IAM policy is fetched live from GitHub on every plan** (`data "http" "lbc_iam_policy"`, pulling `kubernetes-sigs/aws-load-balancer-controller`'s `main` branch `iam_policy.json` directly). If that file changes upstream, your next `terraform plan` in this repo can show a diff with zero local changes — this policy isn't vendored/pinned to a release tag, it tracks upstream `main` continuously.

### Secrets Store CSI Driver — rotation settings

`c16-01` sets three non-default Helm values worth knowing about, since they're load-bearing for the DB-secret rotation set up in `08_AWS_managed_databases`:

- `tokenRequests[0].audience = pods.eks.amazonaws.com` — without this, pods fail to mount CSI secrets at all under Pod Identity (`token for audience "pods.eks.amazonaws.com" not found`).
- `enableSecretRotation = true` + `rotationPollInterval = 2m` — **not on by default.** Without these, `syncSecret.enabled` alone only re-reads the source secret when a pod (re)mounts the volume — a rotated Secrets Manager value would never reach the synced Kubernetes `Secret` (or trigger Reloader) until every consuming pod happened to restart on its own for an unrelated reason. This was discovered and fixed mid-session; it's not a hypothetical.

### Reloader

Watches Kubernetes `Secret`/`ConfigMap` objects and rolling-restarts anything annotated `reloader.stakater.com/auto: "true"` when the referenced object's data changes. `reloader.isArgoRollouts = true` is set because `orders` (and now other services) run as `argoproj.io` `Rollout` objects, not plain `Deployment`s — Reloader needs that flag to know how to trigger a restart on a Rollout. This is what closes the loop between "Secrets Manager rotated a DB password" and "the pod using it actually gets restarted with the new value" — see `08_AWS_managed_databases`.

## Providers

`c12-helm-and-kubernetes-providers.tf` configures the `helm` and `kubernetes` Terraform providers to authenticate against the cluster this same module just created, using a short-lived token from `data.aws_eks_cluster_auth` — every `plan`/`apply` fetches a fresh token, so there's no stale-credential concern, but it does mean **this module can't be planned against a cluster that doesn't exist yet in the same run** (the two Helm-based addon files depend on `aws_eks_cluster.main` transitively through these providers).

## Variables

Full list in `c2-variables.tf`; the ones actually overridden in `terraform.tfvars` (rest stay at their code defaults):

| Name | Value | Notes |
|---|---|---|
| `cluster_version` | `"1.35"` | Only non-null override — the variable defaults to `null` (AWS default) otherwise |
| `cluster_service_ipv4_cidr` | `172.20.0.0/16` | Kubernetes Service CIDR — separate address space from the VPC's `10.0.0.0/16`, no overlap risk |
| `node_instance_types` | `["m7i-flex.large"]` | |
| `node_capacity_type` | `ON_DEMAND` | This is the managed node group; Karpenter's spot/on-demand choice in `04` is independent |
| `node_desired_size` / `min` / `max` | `3` / `1` / `6` | |
| `cluster_endpoint_public_access_cidrs` | `["0.0.0.0/0"]` | See public endpoint note above |

## Outputs (live values)

```
eks_cluster_name              = retail-gleamgoods-eks
eks_cluster_id                = retail-gleamgoods-eks
eks_cluster_version            = 1.35
eks_cluster_endpoint           = https://2230D9910377A9D6D2722F3EFE0D767A.gr7.us-east-1.eks.amazonaws.com
eks_cluster_security_group_id  = sg-0681ec91bfc0b6ead
private_node_group_name        = retail-gleamgoods-private-ng
eks_node_instance_role_arn     = arn:aws:iam::564956047797:role/retail-gleamgoods-eks-nodegroup-role
to_configure_kubectl           = aws eks --region us-east-1 update-kubeconfig --name retail-gleamgoods-eks
```

Plus one IAM role ARN, Pod Identity association ARN, and (where applicable) addon ARN/ID/version per addon in the table above — see `c10_eks_outputs.tf` and each addon's own file for the full set. `data.terraform_remote_state.vpc`'s `vpc_id`/`private_subnet_ids`/`public_subnet_ids` are also re-exported here (`c3_remote-state.tf`), same pattern as every other module that consumes the VPC state.

Two outputs return full Helm release metadata blocks (`helm_lbc_metadata`, `helm_secrets_store_csi_driver_metadata`, etc.) rather than just a version string — convenient for debugging (`revision`, `last_deployed`, the exact `values` JSON that was applied) but bulkier than the addon outputs.

## CI/CD

`.github/workflows/terraform-03-eks-with-addons.yaml`, triggered on push to `main` touching `03_EKS_with_addons/**`. Same three-stage shape as `02_VPC`: Trivy secret-scan → plan (uploads `tfplan-03-eks-with-addons` artifact) → apply (downloads that exact plan, applies it, gated behind GitHub Environment `03-EKS-with-addons-Apply`). A matching `terraform-03-eks-with-addons-destroy.yaml` exists for teardown.

Given the addon-version-drift note above, a CI-triggered `plan` on this module can show changes (addon version bumps, LBC policy diffs) that have nothing to do with whatever code change actually triggered the run — worth checking the plan output carefully before approving the apply gate, rather than assuming "no code diff in this PR" means "no infrastructure diff."

## State

Remote, same backend bucket, key `GleamGoods/eks/terraform.tfstate`.

## Destroy order

Must be destroyed **after** `04_EKS_Karpenter`, `05_OpenTelemetry`, and `08_AWS_managed_databases` (they all read this module's outputs), and **before** `02_VPC` (this module reads the VPC's outputs). None of the addons or the node group have `prevent_destroy` set, so nothing at the Terraform level stops a destroy here — but AWS itself will block deleting the cluster's subnetted resources (ENIs, node group, LBC-created ALBs/NLBs still attached) if downstream modules haven't been torn down first, surfacing as apply-time AWS API errors rather than a Terraform guardrail — same pattern as the VPC module's destroy-order note.
