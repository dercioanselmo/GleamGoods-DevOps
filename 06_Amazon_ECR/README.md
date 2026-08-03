# 06 — Amazon ECR

Creates the container image registries for all 5 application microservices, plus the GitHub OIDC trust relationship the **application repo's** own CI (`dercioanselmo/GleamGoods`, a separate GitHub repo from this one) uses to authenticate and push images — no long-lived AWS keys stored in that repo either. This module also owns the account's one-and-only GitHub Actions OIDC **provider**; every other OIDC-authenticated role in the project (including the unrelated Terraform-CI role in `01_remote_backend_s3bucket`) looks this provider up read-only rather than creating a second one.

This is a small, self-contained module — no `data.terraform_remote_state` dependencies on any other module, and nothing else in this repo depends on its outputs via remote state either (the app repo's workflows reference the role ARN directly, outside Terraform).

## Resources

| File | Resource | What it does |
|---|---|---|
| `c3-01-ecr-repositories.tf` | `aws_ecr_repository.ecr` (× 5, `for_each` over `var.ecr_repositories`) | One repo per microservice (`gleamgoods/ui`, `/cart`, `/catalog`, `/checkout`, `/orders`). `image_tag_mutability = "MUTABLE"`, `scan_on_push = true` |
| `c3-02-github-actions-iam.tf` | `aws_iam_openid_connect_provider.github` | The account's GitHub Actions OIDC provider (`token.actions.githubusercontent.com`). Owned here — every other module that needs it looks it up via `data`, never recreates it |
| `c3-02-github-actions-iam.tf` | `aws_iam_role.github_actions` | Trusts the OIDC provider above, condition `token.actions.githubusercontent.com:sub = repo:${var.github_repo}:*` — the **application** repo, any ref (not branch-restricted, unlike the Terraform-CI role in `01_remote_backend_s3bucket`) |
| `c3-02-github-actions-iam.tf` | `aws_iam_role_policy_attachment.ecr_poweruser` | Attaches AWS-managed `AmazonEC2ContainerRegistryPowerUser` — push/pull/describe, nothing broader |

**Split into two files deliberately** (ECR resources vs. IAM/OIDC resources), matching the per-concern file convention used throughout this project (e.g. `03_EKS_with_addons`'s addon files) rather than one combined file. Resource addresses aren't tied to filenames in Terraform, so this split carries zero state risk.

## Two separate GitHub Actions OIDC roles exist in this project — don't confuse them

| | This module's role (`github_actions`) | Terraform-CI role (`01_remote_backend_s3bucket`) |
|---|---|---|
| Trusts | Application repo (`dercioanselmo/GleamGoods`) | This Terraform repo (`dercioanselmo/GleamGoods-DevOps`) |
| Trust scope | Any ref | `main` branch only |
| Permissions | `AmazonEC2ContainerRegistryPowerUser` only | `AdministratorAccess` |
| Used by | The app repo's own build/push/scan CI workflows | Every `terraform-*.yaml` workflow in *this* repo |

Both trust the **same** OIDC provider (created here), but are otherwise unrelated. Don't widen this module's role's permissions to cover anything beyond image push/pull.

## Known gap: security-scan report uploads have no S3 permission anywhere

The application repo's CI workflows (`build-push-*.yaml` × 5, `codeql.yaml`, `dast-zap.yaml`) all upload Trivy/Snyk/CodeQL/ZAP scan reports to S3 (`aws s3 cp ... s3://${{ vars.REPORT_BUCKET }}/...`), authenticated via this module's `github_actions` role. **That role has no S3 permission of any kind** (only `AmazonEC2ContainerRegistryPowerUser`), and **no S3 bucket for these reports is provisioned anywhere in this Terraform project**. Every upload step is wrapped in `|| echo "... upload skipped"`, so this fails silently rather than breaking CI — worth confirming whether `REPORT_BUCKET` is actually set to a real bucket and whether reports are landing anywhere before assuming this works. Fixing it (if wanted) needs: an S3 bucket (Terraform, could live here or elsewhere) + a scoped `s3:PutObject` policy attached to the existing `github_actions` role — not a new role.

## Variables

Full list in `c2-variables.tf`; overridden in `terraform.tfvars`:

| Name | Value | Notes |
|---|---|---|
| `aws_region` | `us-east-1` | |
| `project_name` | `gleamgoods` | No `business_division` variable in this module — see the naming-convention note below |
| `github_repo` | `dercioanselmo/GleamGoods` | The **application** repo, not this one |
| `role_name` | `github-actions-oidc-role-gleamgoods` | Must match exactly what the app repo's workflows reference in `role-to-assume` |
| `ecr_repositories` | `[gleamgoods/ui, /cart, /catalog, /checkout, /orders]` | One repo per microservice |
| `tags` | `{ Terraform, Environment, Project, ManagedBy }` | |

**Naming convention note:** unlike most other modules in this project, this one has no `business_division` variable — resource naming here is flat (`gleamgoods/ui`, `github-actions-oidc-role-gleamgoods`), not the `<business_division>-<project_name>-...` pattern used in `03`–`05`/`08`. Same divergence as `01_remote_backend_s3bucket` and `02_VPC` — not an oversight, just inconsistent across the project's history.

## Outputs

```
ecr_repository_urls  = { "gleamgoods/ui" = "<account>.dkr.ecr.us-east-1.amazonaws.com/gleamgoods/ui", ... }
ecr_repository_arns  = { "gleamgoods/ui" = "arn:aws:ecr:us-east-1:<account>:repository/gleamgoods/ui", ... }
github_oidc_role_arn = arn:aws:iam::<account>:role/github-actions-oidc-role-gleamgoods
github_oidc_role_name = github-actions-oidc-role-gleamgoods
```

## CI/CD

`.github/workflows/terraform-06-amazon-ecr.yaml`, triggered by pushes to `main` touching `06_Amazon_ECR/**`. Same three-stage pipeline as every other module: Trivy secret scan → Terraform Plan (uploads `tfplan-06-amazon-ecr`) → Terraform Apply, gated behind the `06-Amazon-ECR-Apply` GitHub Environment's manual approval. AWS auth via OIDC (`github-actions-terraform-role-gleamgoods-devops`, defined in `01_remote_backend_s3bucket`) — this module's *own* CI uses the Terraform-CI role, not the role it creates. Corresponding `terraform-06-amazon-ecr-destroy.yaml` for teardown.

## State

Remote, same backend bucket, key `GleamGoods/ecr/terraform.tfstate`.

## Destroy order

No `data.terraform_remote_state` dependency on any other module, and nothing else depends on this module's state — can be destroyed independently of the VPC/EKS chain. Destroying it removes the ECR repositories (and every image in them, unless `force_destroy`/lifecycle protections are added) and the GitHub OIDC role the application repo's CI depends on — confirm the app repo's CI is expected to be down before destroying.
