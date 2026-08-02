# Context: `09_KARPENTER_k8s-manifests`

You are senior devops engineer, and bellow is the complete brief for implementing (or re-implementing) the Karpenter node-provisioning manifests of the GleamGoods-DevOps project.

## Purpose

Defines **what** Karpenter (installed by `04_EKS_Karpenter`'s Terraform) is allowed to provision — instance types, capacity type, AMI, disruption policy. Plain Kubernetes manifests, **no Terraform, no CI workflow**, applied by hand with `kubectl apply -f`. This split is deliberate: see `04_EKS_Karpenter.context.md` for why the controller and its provisioning policy live in different places. If reimplementing, do not fold these into the Terraform module as `kubernetes_manifest` resources.

## Required resources

### `01_ec2nodeclass.yaml` — one `EC2NodeClass`
- `amiFamily: AL2023`, `amiSelectorTerms: [{ alias: "al2023@latest" }]`.
- `role`: the ARN of the node IAM role created by `04_EKS_Karpenter`'s Terraform (`aws_iam_role.karpenter_node`). **This is a hardcoded ARN string in the YAML, not read from a Terraform output** — if that role is ever renamed or recreated with a different ARN, this file needs a manual update; nothing will error if it's stale, nodes will just fail to launch.
- Subnet and security-group discovery **by tag only** (`subnetSelectorTerms`/`securityGroupSelectorTerms` matching `karpenter.sh/discovery = <cluster-name>`) — not by explicit subnet/SG IDs. That tag is applied to the private subnets by `02_VPC`.
- `blockDeviceMappings`: 20Gi gp3, encrypted, `deleteOnTermination: true`.
- `metadataOptions`: `httpTokens: required` (IMDSv2 only), `httpPutResponseHopLimit: 2`.
- Note in comments why the discovery tag is used instead of the plain `kubernetes.io/cluster/<name>=owned` tag: that tag exists on *both* public and private subnets, and using it alone risks Karpenter launching nodes into public subnets with public IPs. The dedicated `karpenter.sh/discovery` tag exists only on private subnets, keeping Karpenter's node placement decoupled from the load-balancer-facing tagging.

### `02_nodepool_ondemand.yaml` / `03_nodepool_spot.yaml` — two `NodePool`s
- Both reference the single `EC2NodeClass` above via `nodeClassRef`.
- On-demand: `karpenter.sh/capacity-type: [on-demand]` explicitly (don't rely on the implicit default), a conservative/budget instance-family list (`t3`, `t3a`, `c5`, `c5a`, `c6i`, `m5`, `m6i`), sizes `small`–`xlarge`.
- Spot: `karpenter.sh/capacity-type: [spot]`, a *wider* instance-family list than on-demand (more families = better Spot availability), sizes `micro`–`xlarge`, and an explicit `disruption.budgets` block allowing 100% of nodes to be disrupted for `Drifted`/`Underutilized`/`Empty` reasons (Spot capacity is expected to churn — don't apply the same conservative disruption budget as on-demand).
- Both: `requirements` must constrain `topology.kubernetes.io/zone` to the actual AZs the cluster's subnets exist in (Karpenter can only launch into AZs with a configured subnet) — don't hardcode AZ names independent of what `02_VPC` actually created.
- Both: a cluster-wide `limits.cpu` cap (currently `"50"` on each pool) and `disruption.consolidationPolicy: WhenEmptyOrUnderutilized` with a short `consolidateAfter` (currently `30s`).

## Repo-wide conventions

- Numbered filenames matching apply order, same convention as this project's other manual-manifest folders (`12_Open_Telemetry`, `13_RBAC_NetworkPolicy`).

## CI/CD

None — manual `kubectl apply -f` only.

## Explicitly out of scope / known risk to flag if asked to harden this

- **Easy to forget on a cluster rebuild**: applying `04_EKS_Karpenter`'s Terraform installs the controller with zero `NodePool`s. Nothing errors — Karpenter just sits idle, provisioning nothing, until this folder is applied by hand. If asked to make cluster rebuilds more robust, this is the gap to close (e.g. a post-apply checklist step, or eventually converting these to Terraform `kubernetes_manifest` resources with an explicit `depends_on` the controller — a real option, just not the current design).
- The hardcoded node-role ARN in `EC2NodeClass` — same class of drift risk as above.
