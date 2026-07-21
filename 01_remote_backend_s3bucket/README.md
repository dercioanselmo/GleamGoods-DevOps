# 01 — Remote Backend S3 Bucket

Creates the S3 bucket that every other Terraform module in this project uses as its remote state backend. This is the **bootstrap module** — it must exist before any other module's `terraform init` can succeed, since they all point their `backend "s3"` block at the bucket created here.

## What this creates

| Resource | Purpose |
|---|---|
| `aws_s3_bucket.tfstate_bucket` | The bucket itself: `tfstate-<environment_name>-<aws_region>-<random suffix>` |
| `random_string.suffix` | 6-character lowercase suffix appended to the bucket name, so it's globally-unique |
| `aws_s3_bucket_versioning.tfstate_versioning` | Versioning **enabled** — every state write is kept as a prior version, so a bad `apply` or accidental overwrite can be recovered from bucket version history |
| `aws_s3_bucket_server_side_encryption_configuration.tfstate_encryption` | SSE-S3 (`AES256`) encryption at rest on every object |
| `aws_s3_bucket_public_access_block.tfstate_block_public` | All four public-access blocking controls enabled — this bucket must never be reachable from the internet, since state files contain resource IDs, ARNs, and in some modules sensitive data |

**Current live bucket:** `tfstate-dev-us-east-1-1v8wcs` (`us-east-1`).

## Variables

| Name | Default | Notes |
|---|---|---|
| `environment_name` | `"dev"` | Used only in the bucket name and tags — this repo does not currently deploy separate environments, so this has stayed at its default |
| `aws_region` | `"us-east-1"` | Region for both the bucket and the AWS provider |

Neither variable is overridden via a `terraform.tfvars` file in this module — both are left at their defaults.

## Outputs

- `tfstate_bucket_arn`
- `tfstate_bucket_id` (the bucket name)


## How every other module uses this bucket

Each of the other Terraform directories (`02_VPC`, `03_EKS_with_addons`, `04_EKS_Karpenter`, `05_OpenTelemetry`, `06_Amazon_ECR`, `08_AWS_managed_databases`) declares its own state location inside this same bucket, one unique `key` per module, e.g.:

```hcl
backend "s3" {
  bucket       = "tfstate-dev-us-east-1-1v8wcs"
  key          = "GleamGoods/vpc/terraform.tfstate"
  region       = "us-east-1"
  encrypt      = true
  use_lockfile = true
}
```

`use_lockfile = true` uses S3's native conditional-write locking (no separate DynamoDB lock table needed — this requires a reasonably recent AWS provider/Terraform version, which lines up with the `>= 1.9.0` / `>= 6.0` constraints in `c1-versions.tf`).

Several modules also read *another* module's outputs at plan time via `data.terraform_remote_state`, pointing at the same bucket with a different `key` — e.g. `03_EKS_with_addons` reads `02_VPC`'s state to get the VPC ID and subnet IDs, `08_AWS_managed_databases` reads both the VPC and EKS state. This module (`01`) is the one piece of shared infrastructure nothing else reads outputs from — it's consumed purely as a backend target, not as a data source.

## Applying this module

This is the one module in the repo without a corresponding GitHub Actions workflow. That's intentional, not an oversight: every workflow authenticates to AWS and then needs a place to store its own state, which is this bucket.

```bash
cd 01_remote_backend_s3bucket
terraform init
terraform apply
```

After apply, copy the resulting bucket name into every other module's `backend "s3" { bucket = "..." }` block.

## Deletion protection

`aws_s3_bucket.tfstate_bucket` has `lifecycle { prevent_destroy = true }`. A `terraform destroy` (or a plan that would recreate the bucket) will hard-fail rather than delete it. To actually remove this bucket it is necessary delete the `prevent_destroy` line first — given every other module's state lives inside it, there's normally no reason to.

`force_destroy` is commented out on the bucket resource, meaning `terraform destroy` would additionally fail if the bucket still contains objects (all the other modules' state files) even if `prevent_destroy` were removed. Both guards would need to be deliberately dismantled to delete this bucket, which is by design.
