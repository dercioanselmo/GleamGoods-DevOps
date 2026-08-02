# Context: `01_remote_backend_s3bucket` Terraform module

You are senior devops engineer, and bellow is the complete brief for implementing (or re-implementing) the remote-backend-bootstrap module of the GleamGoods-DevOps project.

## Purpose

The one module in this project with no remote state of its own. It creates two things every other module depends on before their own Terraform can run at all:

1. The **S3 bucket** every other module uses as its `backend "s3"` remote state.
2. The **GitHub Actions OIDC IAM role** every other module's CI workflow assumes to authenticate to AWS.

Both exist here specifically to solve the same chicken-and-egg problem: a module can't use a remote-state bucket that doesn't exist yet, and a CI workflow can't authenticate via a role that its own apply is supposed to create. This module has to be self-contained and applied first, by hand, before anything else in the project can function.

## Hard requirements

### S3 state bucket
- Named `tfstate-<environment_name>-<aws_region>-<random-6-char-suffix>` — the random suffix (`random_string`, lowercase alphanumeric, no special characters, 6 chars) exists because S3 bucket names are globally unique across *every* AWS account, not just this one; a fixed name risks colliding with some other account's bucket.
- **Versioning enabled** — state history/rollback matters more here than almost anywhere else in the project.
- **Server-side encryption**, AES256.
- **All four public-access-block settings `true`** — this bucket must never be reachable from outside the account under any circumstance.
- **`lifecycle { prevent_destroy = true }` on the bucket resource** — deliberate and non-negotiable. This single bucket holds the Terraform state for every module in the entire project; accidental destruction here is catastrophic (loses the ability to manage everything else via Terraform, not just this module). Do not relax this even if asked to add `force_destroy` for convenience — that comment exists in the current code, commented out, on purpose.

### GitHub Actions OIDC role
- Role name: `github-actions-terraform-role-gleamgoods-devops`.
- Trust policy: `Federated` principal = the account's existing GitHub OIDC provider, looked up via `data "aws_iam_openid_connect_provider" { url = "https://token.actions.githubusercontent.com" }` — **do not create a new `aws_iam_openid_connect_provider` resource here.** AWS allows only one OIDC provider per issuer URL per account, and this account's provider is already created and owned by a different module (`06_Amazon_ECR`, for an unrelated ECR-push role trusted by the separate application repo). Creating a second one for the same URL will conflict.
- Trust condition: `StringLike` on `token.actions.githubusercontent.com:sub` = `repo:<github-org>/<this-repo>:ref:refs/heads/main`, plus `StringEquals` on `:aud` = `sts.amazonaws.com`. Scoped to exactly this repo and exactly the `main` branch — every `terraform-*.yaml` workflow in this project only triggers on push to `main`, so nothing legitimate needs this role from any other ref or repo.
- Attached policy: AWS managed `AdministratorAccess`. This is intentionally broad — the project's Terraform creates/modifies IAM roles and policies across nearly every AWS service in play (EKS, RDS, ElastiCache, Lambda, SQS, CloudFormation, Secrets Manager, ECR, S3, AMP/AMG), which inherently needs broad rights (`iam:CreateRole`, `iam:PassRole`, service-specific create/modify/delete). The actual security boundary is not this policy — it's (a) no long-lived static AWS keys anywhere, (b) the repo+branch trust condition above, and (c) manual-approval GitHub Environments gating every apply job in every other module's workflow.

## Repo-wide conventions this module must follow

- **File naming**: same `c1-versions.tf`, `c2-variables.tf`, `c3-<topic>.tf`, `c4-outputs.tf` incrementing pattern as every other module (here: `c5-github-actions-terraform-role.tf` for the OIDC role, added after the original 4 files).
- **Variables**: `environment_name` (default `dev`), `aws_region` (default `us-east-1`), `tags` (map, default `{ Terraform = "true" }`). Note this module uses `environment_name`, not `project_name`/`business_division` like most other modules — yet another naming-convention divergence across this project's modules (same kind of divergence noted in the VPC module's context file). Don't silently unify these without flagging it.
- **No `terraform.tfvars`** currently — all variables stay at their code defaults for this module.

## What makes this module different from every other module in the project — read before touching CI

**This module has no `backend "s3"` block at all** (`c1-versions.tf` has no `backend` configuration whatsoever) — it uses plain local state, deliberately. It cannot reference the S3 bucket as its own backend because that bucket is the resource this module creates; the backend can't exist before the thing that creates it has already run once.

**This module has no GitHub Actions workflow, and should not get one** without fundamentally solving the bootstrap problem first. A CI-based apply here would need to authenticate via OIDC by assuming `github-actions-terraform-role-gleamgoods-devops` — the exact role this module's own apply is responsible for creating. On a fresh AWS account with nothing yet deployed, that role doesn't exist, so CI could never successfully run this module's first apply. This is applied **exclusively by a human, locally**, from an AWS identity that already has sufficient privileges (`terraform init && terraform plan && terraform apply`, run from this directory). Every other module in the project (`02` onward) is CI-applied via OIDC through the role this module creates — this one is the deliberate exception, not an oversight to "fix" by adding a workflow.

Consequence for local state hygiene: `terraform.tfstate`/`terraform.tfstate.backup` will exist as real files in this directory after applying. They're already covered by `.gitignore` (`*.tfstate`, `*.tfstate.backup`) — confirm this stays true if the `.gitignore` is ever touched; these files must never be committed, since they contain account IDs, ARNs, and other resource details in plaintext.

## Explicitly out of scope for this module

- The OIDC **provider** itself — owned by `06_Amazon_ECR`, only referenced here read-only.
- Any IAM roles/policies beyond the one Terraform-CI role — this module's IAM surface is strictly "what every other module's CI needs to bootstrap," nothing broader (no application-facing roles, no per-service roles — those live in the modules that actually need them).
- DynamoDB state-lock tables — this project uses Terraform's native S3 lockfile locking (`use_lockfile = true` in every *other* module's backend block) instead of the older DynamoDB-table locking pattern. This module itself doesn't need locking configuration at all, since it has no remote backend to lock.
