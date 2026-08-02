# Context: `06_Amazon_ECR` Terraform module

You are senior devops engineer, and bellow is the complete brief for implementing (or re-implementing) the ECR module of the GleamGoods-DevOps project.

## Purpose

Creates the container image registries for all 5 application microservices, plus the GitHub OIDC trust relationship the **application repo's** CI (a separate GitHub repo from this Terraform repo) uses to push images into them. This module also owns the account's one-and-only GitHub Actions OIDC **provider** — every other OIDC-authenticated role in the whole project (including the unrelated Terraform-CI role in `01_remote_backend_s3bucket`) looks this provider up read-only rather than duplicating it.

This is a small, self-contained module — no `data.terraform_remote_state` dependencies on any other module, and nothing else depends on this module's outputs via remote state either (the app repo's own CI workflow references the role ARN directly, outside Terraform).

## Hard requirements

- **5 ECR repositories**, one per microservice, driven by a `for_each` over a `var.ecr_repositories` list (default: `gleamgoods/ui`, `gleamgoods/cart`, `gleamgoods/catalog`, `gleamgoods/checkout`, `gleamgoods/orders`) — not 5 separate hardcoded resource blocks. `image_tag_mutability = "MUTABLE"`, `image_scanning_configuration.scan_on_push = true` on every repo.
- **The GitHub OIDC provider** (`aws_iam_openid_connect_provider`, `url = "https://token.actions.githubusercontent.com"`, `client_id_list = ["sts.amazonaws.com"]`) is created **here**, not in any other module. This is the one and only place it should exist — AWS allows exactly one OIDC provider per issuer URL per account, so any other module needing to reference GitHub's OIDC provider (e.g. `01_remote_backend_s3bucket`'s Terraform-CI role) must look it up via `data "aws_iam_openid_connect_provider"`, never create a second one.
- **A GitHub Actions IAM role scoped to image push/pull only** (`aws_iam_role.github_actions`, name from `var.role_name`), trusting this provider, condition `token.actions.githubusercontent.com:sub` matching `repo:<github_repo>:*` (the **application** repo, `dercioanselmo/GleamGoods` — a different GitHub repo from this Terraform repo, and note the trust condition here is *not* branch-restricted like the Terraform-CI role is, since the app repo's image-build workflow may need to run from more than just `main`). Attach only `AmazonEC2ContainerRegistryPowerUser` — this role must never be broadened to `AdministratorAccess` or similar; it exists specifically so the application repo's CI can push/pull images and nothing else.

## Critical distinction — do not conflate the two GitHub-Actions-OIDC roles in this project

There are **two separate GitHub Actions IAM roles** authenticating via the **same** OIDC provider (the one created in this module), and they must stay separate:

| | This module's role (`github_actions`) | Terraform-CI role (`01_remote_backend_s3bucket`) |
|---|---|---|
| Trusts | The **application** repo (`dercioanselmo/GleamGoods`) | **This** Terraform repo (`dercioanselmo/GleamGoods-DevOps`) |
| Trust scope | Any ref (`:*`) | `main` branch only |
| Permissions | `AmazonEC2ContainerRegistryPowerUser` only | `AdministratorAccess` |
| Used by | The app repo's own build/push CI workflow (outside this Terraform repo) | Every `terraform-*.yaml` workflow in *this* repo |

Don't merge these into one role, don't widen this module's role's permissions to cover Terraform operations, and don't let the Terraform-CI role's definition end up in this module — it belongs in `01_remote_backend_s3bucket` specifically so it exists before any CI-applied module (including this one) needs it. See that module's context file for the full reasoning.

## Repo-wide conventions this module must follow

- File naming: `c1-versions.tf` (hyphen convention, matching `03`), `c2-variables.tf`, `c3-ecr-iam.tf` (ECR repos + OIDC provider + role combined in one file — this module is small enough that everything IAM-related lives in a single file rather than being split like `03`'s addon-per-file pattern), `c4-outputs.tf`.
- Variables: `aws_region`, `project_name` (default `gleamgoods`) — **no `business_division` variable here**, another instance of the naming-convention divergence already noted in `02_VPC`'s and `01_remote_backend_s3bucket`'s context files. Also: `github_repo` (default `dercioanselmo/GleamGoods` — the app repo, not this one), `role_name` (default `github-actions-oidc-role-gleamgoods`), `ecr_repositories` (list, the 5 repo names), `tags`.
- Remote state key: `GleamGoods/ecr/terraform.tfstate`.
- Outputs: `ecr_repository_urls` / `ecr_repository_arns` (both maps keyed by repo name, via `for k, v in aws_ecr_repository.ecr : k => v.<attr>`), `github_oidc_role_arn`, `github_oidc_role_name`.

## CI/CD

Same three-stage pattern (`TF-06_Amazon_ECR`, Trivy → plan → manual-approval apply), OIDC via the **Terraform-CI** role from `01_remote_backend_s3bucket` (not this module's own app-facing role — this module's CI, like every other Terraform module's CI, authenticates as the Terraform-CI identity; the role this module *creates* is for a completely different, unrelated CI pipeline in the app repo).

## Explicitly out of scope

- The Terraform-CI OIDC role and its trust/permissions — lives in `01_remote_backend_s3bucket`, only referenced (its provider) read-only from here.
- Anything about how the application repo's own CI workflow is structured (build steps, scan steps, tagging strategy) — this module only provisions the AWS-side registries and trust relationship; the workflow YAML consuming them lives in the separate application repo.
- Repository lifecycle policies (image expiration/cleanup rules) — not currently defined on any of the 5 repositories; every pushed image tag persists indefinitely unless this is added deliberately.
