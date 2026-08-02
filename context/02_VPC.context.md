# Context: `02_VPC` Terraform module

You are senior devops engineer, and bellow is the complete brief for implementing (or re-implementing) the VPC module of the GleamGoods-DevOps project.

## Purpose

Foundational networking for an EKS-based platform: one VPC spanning 3 Availability Zones, with public and private subnets in each, NAT egress for the private subnets, and the exact tagging scheme EKS/Karpenter need to auto-discover these subnets later. This module owns networking only — no compute, no EKS cluster, no security groups beyond what subnets/route tables require.

## Hard requirements

- **1 VPC**, CIDR `10.0.0.0/16`, DNS hostnames + DNS support both enabled (required for EKS).
- **3 Availability Zones** — discovered dynamically via `data "aws_availability_zones" "available" { state = "available" }`, sliced to the first 3. Do not hardcode AZ names (region-portable).
- **1 public + 1 private subnet per AZ** (6 subnets total). `/24` each (`subnet_newbits = 8` added to the `/16` VPC CIDR).
- **Subnet CIDR allocation is offset, not sequential** — public subnets use `cidrsubnet(vpc_cidr, newbits, k)` for `k = 0,1,2` (→ `10.0.0.0/24`, `10.0.1.0/24`, `10.0.2.0/24`); private subnets use `k+10` (→ `10.0.10.0/24`, `10.0.11.0/24`, `10.0.12.0/24`). This deliberately reserves `10.0.3.0/24`–`10.0.9.0/24` as unused address space for future subnet types (e.g. dedicated DB subnets) without needing to renumber anything already allocated. Preserve this offset scheme, don't collapse it to sequential numbering.
- **1 Internet Gateway**, attached to the VPC.
- **1 NAT Gateway per AZ (3 total), each in its own public subnet, each with its own Elastic IP** — not a single shared NAT Gateway. This is a deliberate availability/cost tradeoff: higher cost (3 NAT Gateways instead of 1) buys no cross-AZ NAT traffic and no single point of failure for egress. Keep this per-AZ pattern unless explicitly told to cost-optimize to a single shared NAT.
- **Public route tables**: one per public subnet, default route (`0.0.0.0/0`) → the Internet Gateway.
- **Private route tables**: one per private subnet, default route (`0.0.0.0/0`) → that AZ's own NAT Gateway (not a shared one — each private subnet routes through the NAT Gateway in its *own* AZ).

## Tagging — exact keys and values matter

Every subnet needs these tags, or downstream EKS/Karpenter modules silently fail to discover them:

**Public subnets:**
```
Name                                          = "<project_name>-public-<az>"
kubernetes.io/cluster/<cluster_name>          = "owned"
kubernetes.io/role/elb                        = "1"
karpenter.sh/discovery                        = "<cluster_name>"
```

**Private subnets:**
```
Name                                          = "<project_name>-private-<az>"
kubernetes.io/cluster/<cluster_name>          = "owned"
kubernetes.io/role/internal-elb               = "1"
karpenter.sh/discovery                        = "<cluster_name>"
```

**Use `"owned"`, not `"shared"`, on the `kubernetes.io/cluster/<cluster_name>` tag — on both public and private subnets.** This is a deliberate, non-default choice: `"shared"` (the more commonly-recommended value when a VPC might host multiple clusters) only lets the EKS control plane use the subnet — it does **not** let Karpenter or a managed node group actually launch EC2 instances into it. Since this project needs both Karpenter and a managed node group to launch nodes into these subnets, both public and private subnets must be `"owned"`.

**Known coupling smell, preserve or fix deliberately, don't silently drop:** `<cluster_name>` is currently a hardcoded local (`retail-gleamgoods-eks`) inside the VPC module itself, not something passed in or read from another module's state. The VPC module technically doesn't own or know about the EKS cluster, but has to know its exact name up front for these tags to resolve correctly at EKS-cluster-creation time. If the EKS cluster is ever renamed, this value has to be updated here by hand — there's no automatic cross-module reference. Acceptable as-is given the ordering constraint (VPC is created *before* the EKS cluster exists, so there's no cluster resource yet to reference), but worth knowing rather than rediscovering.

## Repo-wide conventions this module must follow

- **File naming**: `c1-versions.tf`, `c2-variables.tf`, `c3-<topic>.tf`, `c4-outputs.tf`, incrementing — this numbering convention is used across every module in this project, not unique to VPC.
- **Root module + submodule split**: the actual resources live in `./modules/vpc/` (a local child module: `main.tf`, `variables.tf`, `outputs.tf`, `datasources-and-locals.tf`); the root `02_VPC/` just wires `module "vpc" { source = "./modules/vpc" ... }` and re-exposes its outputs. Preserve this split unless asked to flatten it.
- **Remote state backend** — every module in this project uses the same S3 bucket with a per-module key:
  ```hcl
  backend "s3" {
    bucket       = "tfstate-dev-us-east-1-1v8wcs"
    key          = "GleamGoods/vpc/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
  ```
  `region` is hardcoded (not variable-driven) because Terraform's `backend` block cannot reference input variables. `use_lockfile = true` uses Terraform's native S3 state locking (no separate DynamoDB lock table).
- **Provider versions**: `terraform >= 1.0.0` in this module specifically (other modules in the project pin higher, e.g. `>= 1.5.7`); `hashicorp/aws ~> 6.0`.
- **Variables this module exposes**: `aws_region` (default `us-east-1`), `project_name` (default `gleamgoods`), `vpc_cidr` (default `10.0.0.0/16`), `subnet_newbits` (default `8`), `tags` (map, default `{ Terraform = "true" }`). Note: unlike most other modules in this project, VPC does **not** have a `business_division` variable — naming here is `project_name`-only (e.g. `gleamgoods-public-us-east-1a`), not the `<business_division>-<project_name>` prefix pattern used elsewhere (e.g. `retail-gleamgoods-...`). Keep this inconsistency in mind if unifying naming later — it's a known divergence, not an oversight to silently "fix" without flagging.
- **`terraform.tfvars`** sets `project_name`, `aws_region`, `vpc_cidr`, `subnet_newbits`, and a `tags` map (`Terraform`, `Project`, `Owner`) — everything else stays at variable defaults.
- **Outputs required by downstream modules** (consumed via `data.terraform_remote_state` by `03_EKS_with_addons`, `04_EKS_Karpenter`, `05_OpenTelemetry`, `08_AWS_managed_databases`, and others): `vpc_id`, `public_subnet_ids` (list), `private_subnet_ids` (list), `public_subnet_map` (map of AZ → subnet ID, used where an AZ-keyed lookup is needed rather than a plain list).

## CI/CD

GitHub Actions workflow `TF-02_VPC` (`.github/workflows/terraform-02-vpc.yaml`), triggered on push to `main` touching `02_VPC/**`. Three sequential jobs:
1. **Trivy secret scan** — fails the pipeline (and opens a GitHub issue) if it finds exposed secrets in the diff.
2. **Terraform Plan** — `terraform init` → `validate` → `plan -out=plan.tfplan`, uploads the plan as a build artifact.
3. **Terraform Apply** — downloads that exact plan artifact and applies it. Gated behind the `02-VPC-Apply` GitHub Environment, which requires manual approval before the job runs.

AWS authentication is via **GitHub OIDC** — `aws-actions/configure-aws-credentials@v4` assuming `arn:aws:iam::<account-id>:role/github-actions-terraform-role-gleamgoods-devops`. That role is defined in `01_remote_backend_s3bucket` (the one module in this project applied manually, specifically so this role exists before any other module's CI needs it) — no static `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` anywhere. A corresponding `terraform-02-vpc-destroy.yaml` provides the teardown path with the same auth/gating pattern.

## Explicitly out of scope for this module

- No VPC interface endpoints (PrivateLink) for AWS APIs (Secrets Manager, STS, SQS, etc.) exist yet — traffic to those services currently leaves the VPC via NAT Gateway to AWS's public regional endpoints. This is a known, not-yet-addressed gap (surfaced while designing NetworkPolicy egress rules elsewhere in this project) — worth considering if asked to harden network egress further, but not part of the current VPC module's scope.
- `cluster_endpoint_private_access` / restricting the EKS public endpoint to specific CIDRs is an **EKS module** concern (`03_EKS_with_addons`), not a VPC one — don't fold that decision into this module even though it's network-adjacent.
- No database-specific subnets (e.g. an isolated RDS subnet group) exist separately from the general private subnets — RDS currently shares the same private subnets as everything else. The reserved `10.0.3.0/24`–`10.0.9.0/24` gap exists partly to make adding these later possible without renumbering.
