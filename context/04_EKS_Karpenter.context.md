# Context: `04_EKS_Karpenter` Terraform module

You are senior devops engineer, and bellow is the complete brief for implementing (or re-implementing) the Karpenter module of the GleamGoods-DevOps project.

## Purpose

Installs the Karpenter **controller** — dynamic EC2 node provisioning for the EKS cluster from `03_EKS_with_addons`. That module's static managed node group gives the cluster a fixed baseline of capacity; Karpenter watches for unschedulable pods and provisions additional, right-sized EC2 nodes on demand, then removes them again once they're not needed.

**This module installs the controller only.** It does not define what Karpenter is allowed to provision (instance types, Spot vs on-demand, AMI, disruption policy) — that's a separate, deliberately non-Terraform concern, covered below. Don't fold `NodePool`/`EC2NodeClass` resources into this module.

Consumes `02_VPC` and `03_EKS_with_addons` outputs via `data.terraform_remote_state`.

## Hard requirements

### Controller IAM (Pod Identity — same pattern as `03`)
- `aws_iam_role` for the controller, trust = `pods.eks.amazonaws.com` (Pod Identity, not IRSA), associated via `aws_eks_pod_identity_association` to service account `karpenter` in `kube-system`.
- IAM policy: use **AWS's official published Karpenter controller policy** (write it out as a full `data "aws_iam_policy_document"` — scoped EC2 instance/launch-template/fleet actions, scoped instance-profile management, the SQS interruption queue, `iam:PassRole` limited to the node role only, read-only EC2/SSM/pricing/EKS actions). Every scoped statement must condition on the `kubernetes.io/cluster/<cluster-name> = owned` and/or `karpenter.sh/nodepool` tags — this role must only be able to manage EC2 resources Karpenter itself tagged, never arbitrary EC2 instances in the account. Don't write a broader policy for convenience.
- A **separate** IAM role for the EC2 instances Karpenter *launches* (not the controller's own role): `AmazonEKSWorkerNodePolicy`, `AmazonEC2ContainerRegistryPullOnly`, `AmazonEKS_CNI_Policy`, `AmazonSSMManagedInstanceCore`.
- An `aws_eks_access_entry` (type `EC2_LINUX`) registering the node role — without this, nodes Karpenter launches can authenticate to AWS fine but can't join the Kubernetes cluster at all (this is the Access Entries half of `03`'s `cluster_authentication_mode = "API_AND_CONFIG_MAP"`).

### Interruption handling
- 1 SQS queue (name = cluster name), `message_retention_seconds = 300`, SSE-managed encryption, with a queue policy allowing `events.amazonaws.com`/`sqs.amazonaws.com` to `SendMessage`, plus an explicit `Deny` statement blocking any non-TLS (`aws:SecureTransport = false`) access.
- 4 EventBridge rules routing into that queue: AWS Health events, EC2 Spot interruption warnings, EC2 instance rebalance recommendations, EC2 instance state-change notifications. This is what lets Karpenter gracefully cordon/drain/replace a node *before* AWS forcibly reclaims it, not just react after the fact.
- 2 EC2 Spot service-linked roles (`spot.amazonaws.com`, `spotfleet.amazonaws.com`) — required before EC2 will let anything, including Karpenter, launch Spot instances via `CreateFleet`. These are idempotent (safe to declare even if they already exist from something else in the account) — don't skip them assuming they already exist.

### Helm release
- Chart `karpenter` from `oci://public.ecr.aws/karpenter`. Pin the version explicitly (a literal string, e.g. `"1.8.2"`) — check against AWS's published latest and bump deliberately; don't track `latest`.
- **Public ECR requires a fresh auth token to pull from, and that token API only works in `us-east-1`** regardless of which region the rest of the project deploys to. Add a second, aliased `aws` provider block pinned to `us-east-1` used *only* for `data "aws_ecrpublic_authorization_token"`, even if the primary region is different.
- Required Helm values: `settings.clusterName`, `settings.clusterEndpoint`, `settings.interruptionQueue` (the SQS queue name from above), `serviceAccount.name = "karpenter"`, `serviceAccount.create = true`.
- `depends_on` every IAM/Pod-Identity/SQS resource above explicitly — Karpenter's own pod would otherwise be able to start before it has permission to do anything, and Terraform has no other way to know the ordering matters here.

## How Karpenter finds subnets/security groups — not a Terraform concern

Karpenter's controller doesn't take a list of subnet IDs as a Helm value. It discovers what it's allowed to use **by tag**, at the Kubernetes-manifest layer (`EC2NodeClass`, see below) — `02_VPC` tags private subnets with `karpenter.sh/discovery = <cluster-name>`, and the `EC2NodeClass` references that tag via `subnetSelectorTerms`/`securityGroupSelectorTerms`. This module's own resources don't need to read subnet IDs directly for this reason — don't add that wiring here.

## Critical: `NodePool`/`EC2NodeClass` are NOT part of this Terraform module

The Kubernetes custom resources that actually define what Karpenter provisions — instance families/sizes, Spot vs on-demand, AMI, disruption/consolidation policy — are Karpenter's own CRDs, and they belong in a **separate, plain-YAML, manually-applied folder** (this project's convention: `09_KARPENTER_k8s-manifests/`, no Terraform, no CI, applied via `kubectl apply -f`). If asked to implement Karpenter node provisioning behavior, write these as plain Kubernetes manifests in a sibling folder, not as `kubernetes_manifest` Terraform resources inside this module. At minimum, expect:
- One `EC2NodeClass` (AL2023 AMI, references the node IAM role's ARN, subnet/SG discovery via the `karpenter.sh/discovery` tag, encrypted gp3 root volume, IMDSv2 required with hop limit 1-2).
- Separate `NodePool`s for on-demand and Spot capacity, each with its own instance-family/size constraints, AZ constraints matching the cluster's actual subnets, a cluster-wide vCPU limit, and a `disruption` block (`consolidationPolicy: WhenEmptyOrUnderutilized`).

Because these live outside Terraform, **re-running this module's `apply` never touches them** — but a cluster destroy/recreate must remember to re-apply this folder by hand, or Karpenter will run with zero `NodePool`s and provision nothing, silently.

## Repo-wide conventions this module must follow

- File naming: `c1_versions.tf` (this module uses underscores, not hyphens, unlike `03`'s `c1-versions.tf` — a naming-convention divergence, preserve as-is rather than "fixing" to match `03`), `c6_01`...`c6_09` grouping every Karpenter-specific resource under one number with sub-numbering.
- Variables/naming: `business_division` + `project_name` pair, same `local.name` prefix pattern as `03`.
- Remote state key: `GleamGoods/karpenter/terraform.tfstate`.
- Two `data.terraform_remote_state` blocks (`vpc`, `eks`), each re-exported as this module's own outputs (`vpc_id`, `private_subnet_ids`, `public_subnet_ids`, `eks_cluster_name`, `eks_cluster_id`) as a passthrough convenience for anything downstream that wants them without reaching further upstream itself.
- Providers: `helm`/`kubernetes` authenticate via `data.aws_eks_cluster_auth`, same short-lived-token pattern as `03`.

## CI/CD

Same three-stage pattern (`TF-04_EKS_Karpenter`, Trivy → plan → manual-approval apply via GitHub Environment `04-EKS-Karpenter-Apply`), OIDC via the role from `01_remote_backend_s3bucket`. This CI/CD covers this module's Terraform only — it must **not** be expected to apply `09_KARPENTER_k8s-manifests/`; that stays a manual step outside any pipeline.

## Explicitly out of scope

- `NodePool`/`EC2NodeClass` — covered above, deliberately not Terraform.
- Chart-version pinning via a shared `var.addon_versions` object (the pattern used in `03`/`05`) — Karpenter's chart version is currently a standalone literal in the Helm release resource, not yet folded into that shared variable pattern. Worth doing for consistency if asked, but not yet done — don't assume it already follows that pattern.
- Migrating `vpc-cni`'s node-role IAM to Pod Identity, or anything else affecting `03`'s addons — this module only manages Karpenter's own controller/node roles.
