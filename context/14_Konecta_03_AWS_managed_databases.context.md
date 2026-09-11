# Context: `14_Konecta/03_AWS_managed_databases` Terraform module

You are senior devops engineer, and bellow is the complete brief for implementing (or re-implementing) the Konecta managed-databases module of the GleamGoods-DevOps project.

## Purpose

Provisions the data layer for Konecta's 5 stateful microservices — Cart, Checkout, Security, Courier, Store Stock — all on RDS PostgreSQL. This module was built by copying the *structure* of `08_AWS_managed_databases` (remote-state lookups, locals, Pod Identity assume-role doc, per-DB security-group/subnet-group/instance/IAM-role/pod-identity-association shape) but scoped down to **only Postgres and only a single shared secret** — Konecta explicitly does not want GleamGoods' per-service-secret + auto-rotation-Lambda architecture (`08`'s `c10_*` files). If asked to "add rotation" or "split the secret per service" later, that is a deliberate scope expansion, not a bug fix — confirm before doing it, since it's a real architecture change (per-service secrets, host-qualified master-secret copies, SAR rotation Lambdas, per-service IAM policies).

Consumes `02_VPC` and `03_EKS_with_addons` via `data.terraform_remote_state` — **the same shared VPC and EKS cluster GleamGoods uses**, not a Konecta-specific one. Konecta runs in the `konecta` namespace of the existing cluster (see `14_Konecta/01_namespace.yaml`).

## Why this module is simpler than `08_AWS_managed_databases`

08's rotation infrastructure exists because GleamGoods needed zero-downtime credential rotation with blast-radius isolation between Catalog and Orders. Konecta's explicit requirement was: **one secret (`konecta-db-secret`) for all 5 databases and all 5 services.** That single requirement cascades into every other simplification here:

- One `data "aws_secretsmanager_secret"`/`data "aws_secretsmanager_secret_version"` pair (`c6_01`), not five, not per-service master-secret copies.
- One shared `aws_iam_role` + one `aws_iam_policy` (`c8_01`/`c8_02`), not one role per service — since every service needs access to the exact same secret, a shared role/policy is equivalent in practice to five identical ones, so don't create five.
- No rotation Lambda, no SAR stack, no `aws_secretsmanager_secret_rotation`, no host-qualified master-secret copies. All of that exists in `08` purely to support *safe, per-service* rotation — with one shared static secret, none of it applies.
- One shared security group and one shared DB subnet group across all 5 `aws_db_instance` resources, since they all live in the same VPC/subnets and accept the same ingress rule (5432 from the EKS cluster SG) — no per-service SG needed like `08`'s per-Lambda SGs.

If a future ask reintroduces per-service secrets, most of `08`'s `c10_*` pattern can be copied wholesale — the file-numbering gap (`c6`–`c8` used here, no `c9`/`c10`) was left deliberately in case that happens, mirroring how `08` itself left room by numbering rotation infra `c10` despite modifying `c6`/`c9`'s resources.

## Shared foundation (mirrors `08`)

- One shared Pod Identity assume-role policy document (`pods.eks.amazonaws.com` principal, `sts:AssumeRole` + `sts:TagSession`), `c5_01_podidentity_assumerole.tf` — identical to `08`'s, copied verbatim since the trust relationship doesn't vary by project.
- `local.name = "${business_division}-${project_name}"` → `retail-konecta`. **`business_division` stays `"retail"`** (same org-wide division as GleamGoods), only `project_name` changes to `"konecta"` — this was a judgment call, not something the user specified; revisit if Konecta turns out to belong to a different business division than GleamGoods.

## The 5 databases

All five `aws_db_instance` resources (`c7_03`–`c7_07`) are identical in shape, differing only in `identifier`/`db_name`/tags/outputs — same pattern as `08`'s single Orders instance, just repeated 5×:

- `engine = "postgres"`, `engine_version = "17.6"` (matches `08`'s Orders Postgres version — kept in sync deliberately, revisit both together if bumping).
- `instance_class = "db.t4g.micro"`, `allocated_storage = 20`, `max_allocated_storage = 100`, single-AZ, `storage_encrypted = true`, `publicly_accessible = false`, `skip_final_snapshot = true` (dev-appropriate, same caveat as `08` — reconsider for prod), `backup_retention_period = 7`, `deletion_protection = false`.
- `username`/`password` read from `local.konecta_secret_json` (the one shared secret) — **not hardcoded, not `random_password`**, matching `08`'s pattern exactly.
- **Naming split**: `identifier` uses the hyphenated names as given (`konecta-cart`, `konecta-checkout`, `konecta-security`, `konecta-courier`, `konecta-store-stock`) since RDS identifiers allow hyphens; `db_name` uses underscores (`konecta_cart`, etc.) since Postgres database names cannot contain hyphens. Don't try to make these match exactly — they can't, by AWS/Postgres naming rules.

## Service accounts / Pod Identity

- **Namespace is `konecta`, not `default`.** This is the one place this module's Pod Identity associations diverge structurally from `08`'s (`08` uses `namespace = "default"` because all GleamGoods workloads run there) — Konecta has its own namespace (`14_Konecta/01_namespace.yaml`), so every `aws_eks_pod_identity_association` here uses `namespace = "konecta"`.
- Service account names (`cart`, `checkout`, `security`, `courier`, `store-stock`) were chosen to match the existing frontend convention in `14_Konecta/02_services_K8s_manifests/01_frontend/01_ui_service_account.yaml` (short name, no `-service` suffix, even though the ECR repos and app repos are named e.g. `konecta-cart-service`). **This is inferred, not confirmed against each service's actual Helm chart/deployment manifest** — if those charts don't exist yet or land with different service account names, these 5 `aws_eks_pod_identity_association` resources' `service_account` fields need to be updated to match before `apply` will actually grant the right pods access. Check this the same way `08`'s context doc flags Cart's DynamoDB service account name (`carts`, plural) as a place where guessing from folder naming got it wrong once already — verify against the real chart, don't assume.

## Secret shape

`konecta-db-secret` must be created manually (out-of-band, same as `gleamgoods-db-secret`) before first `apply`, with JSON shape:

```json
{ "username": "konecta_admin", "password": "<password>" }
```

No `host`/`engine`/`port`/`dbname`/`masterarn` fields needed — unlike `08`'s master secrets, this one is never used by a rotation Lambda, only read as `aws_db_instance` master credentials via Terraform `data` sources (`c6_01`). Terraform will fail at plan time (`data.aws_secretsmanager_secret.konecta_secret`) if the secret doesn't exist yet.

## Repo-wide conventions this module follows

- File naming: underscore convention (`c1_versions.tf` style), numbered by concern — `c1`–`c5` shared scaffolding (identical shape to `08`), `c6` = the shared secret, `c7` = the 5 Postgres instances + their shared SG/subnet group, `c8` = the shared IAM role/policy + 5 pod identity associations.
- Remote state key: `Konecta/databases/terraform.tfstate` — matches the `Konecta/ecr/terraform.tfstate` key already used by `06_Amazon_ECR_Konecta`'s `c1-versions.tf` (note: that module's own README.md still says `GleamGoods/ecr/terraform.tfstate`, which is stale/wrong — don't copy that mistake here or "fix" this module's key to match it).
- VPC/EKS remote state keys stay `GleamGoods/vpc/terraform.tfstate` / `GleamGoods/eks/terraform.tfstate` — Konecta does not have (and per current scope, should not get) its own VPC/EKS state.

## CI/CD — does not exist yet

Unlike `08_AWS_managed_databases` (`terraform-08-aws-managed-databases.yaml` + `-destroy.yaml`), there is no GitHub Actions workflow for this module, and none exists yet for `06_Amazon_ECR_Konecta` either — Konecta's Terraform modules currently apply manually. If adding one, copy `08`'s three-stage pattern (Trivy secret scan → Terraform Plan → manual-approval Terraform Apply via a GitHub Environment) and path-filter on `14_Konecta/03_AWS_managed_databases/**`.

## Explicitly out of scope (don't add unprompted)

- Per-service secrets and rotation Lambdas (the `08`-style `c10_*` architecture) — Konecta explicitly wants one shared secret; only revisit if asked.
- A dedicated Konecta VPC/EKS cluster — Konecta runs on the existing shared infrastructure.
- CI/CD workflow — not built yet, see above; only add if asked.
- Multi-AZ / production hardening (`skip_final_snapshot`, `deletion_protection`, single-AZ) — copied as-is from `08`'s dev-appropriate defaults, not reconsidered for a Konecta-specific prod posture.
