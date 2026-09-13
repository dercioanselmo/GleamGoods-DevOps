# Context: `14_Konecta/03_AWS_managed_databases` Terraform module

You are senior devops engineer, and bellow is the complete brief for implementing (or re-implementing) the Konecta managed-databases module of the GleamGoods-DevOps project.

## Purpose

Provisions the data layer for Konecta's 5 stateful microservices — Cart, Checkout, Security, Courier, Store Stock — all on RDS PostgreSQL, with per-database credential rotation. Structurally this module **is `08_AWS_managed_databases`'s rotation architecture, applied to 5 databases of the same engine instead of 08's 2 databases of different engines** — same resource types, same SAR rotation app, same master/app-secret split, just reached via `for_each` over one locals map instead of 08's hand-duplicated blocks (5 near-identical services makes copy-paste the wrong tradeoff; it isn't for 08's 2). See [[08_AWS_managed_databases]] context for the rotation mechanism's full rationale — this file only covers what's Konecta-specific or was a live judgment call.

Consumes `02_VPC` and `03_EKS_with_addons` via `data.terraform_remote_state` — **the same shared VPC and EKS cluster GleamGoods uses**, not a Konecta-specific one. Konecta runs in the `konecta` namespace of the existing cluster (see `14_Konecta/01_namespace.yaml`).

## IMPORTANT — a wrong turn was taken and corrected here; don't repeat it

The first version of this module's rotation (now fully removed) was a **hand-written custom Python Lambda** that rotated one shared secret's password across all 5 RDS hosts directly via `ALTER ROLE`. This was built because the user's earlier, separate requirement — "one secret for all 5 databases and services" — seemed to conflict with the AWS-provided SAR rotation app (`aws_serverlessapplicationrepository_cloudformation_stack` with `SecretsManagerRDSPostgreSQLRotationMultiUser`, the mechanism `08` actually uses), which only ever rotates credentials against **one** RDS host per secret.

**The user explicitly rejected this** ("remove every python thing... check well how it was implemented [in 08]") and, when asked to choose, picked splitting into 5 separate secrets/SAR-apps/Lambdas — i.e., **the "one shared secret" requirement does not extend to the rotated per-service app secrets**; it only ever applied to the master credential used to create the RDS instances (see below). The lesson: when a stated requirement ("one shared secret") appears to conflict with how this repo's established pattern works (SAR app = one host), **don't invent a custom mechanism to reconcile it — surface the conflict and ask which side gives way.** The custom Lambda was technically workable but was the wrong call because it deviated from the repo's actual rotation mechanism without being asked to.

## Shared foundation (mirrors `08`)

- One shared Pod Identity assume-role policy document (`pods.eks.amazonaws.com` principal, `sts:AssumeRole` + `sts:TagSession`), `c5_01_podidentity_assumerole.tf` — identical to `08`'s, copied verbatim since the trust relationship doesn't vary by project.
- `local.name = "${business_division}-${project_name}"` → `retail-konecta`. **`business_division` stays `"retail"`** (same org-wide division as GleamGoods), only `project_name` changes to `"konecta"` — this was a judgment call, not something the user specified; revisit if Konecta turns out to belong to a different business division than GleamGoods.

## The 5 databases

All five `aws_db_instance` resources (`c7_03`–`c7_07`) are identical in shape, differing only in `identifier`/`db_name`/tags/outputs:

- `engine = "postgres"`, `engine_version = "17.6"` (matches `08`'s Orders Postgres version — kept in sync deliberately, revisit both together if bumping).
- `instance_class = "db.t4g.micro"`, `allocated_storage = 20`, `max_allocated_storage = 100`, single-AZ, `storage_encrypted = true`, `publicly_accessible = false`, `skip_final_snapshot = true` (dev-appropriate, same caveat as `08` — reconsider for prod), `backup_retention_period = 7`, `deletion_protection = false`.
- `username`/`password` read from `local.konecta_master_secret_json` (the one shared **master** secret, `c6_01`) — **never** from the per-database app secrets (`c9_03`). The master secret is what creates the instances; the app secrets are what the applications actually use to connect, exactly like `08`'s Catalog/Orders split.
- **Naming split**: `identifier` uses the hyphenated names as given (`konecta-cart`, `konecta-checkout`, `konecta-security`, `konecta-courier`, `konecta-store-stock`) since RDS identifiers allow hyphens; `db_name` uses underscores (`konecta_cart`, etc.) since Postgres database names cannot contain hyphens. Don't try to make these match exactly — they can't, by AWS/Postgres naming rules.
- No `lifecycle { ignore_changes = [password] }` on these — unlike the earlier custom-Lambda draft, the master secret feeding these is **never** rotated (see below), so there's nothing external that could change this value out from under Terraform.

## Service accounts / Pod Identity

- **Namespace is `konecta`, not `default`.** `08` uses `namespace = "default"` because all GleamGoods workloads run there; Konecta has its own namespace (`14_Konecta/01_namespace.yaml`), so every `aws_eks_pod_identity_association` here uses `namespace = "konecta"`.
- Service account names (`cart`, `checkout`, `security`, `courier`, `store-stock`) were chosen to match the existing frontend convention in `14_Konecta/02_services_K8s_manifests/01_frontend/01_ui_service_account.yaml` (short name, no `-service` suffix, even though the ECR repos and app repos are named e.g. `konecta-cart-service`). **This is inferred, not confirmed against each service's actual Helm chart/deployment manifest** — verify against the real chart before relying on it, the same way `08`'s Cart DynamoDB service account name (`carts`, plural) was once a wrong guess from folder naming.
- **Each service now has its own dedicated IAM role** (`c8_01`, `for_each` over the 5 service keys) with a policy scoped only to that service's own app secret (`c8_02`) — not a shared role. This changed from an earlier, since-abandoned single-shared-role design once rotation went per-database; a shared role stopped making sense the moment each service got its own secret.

## The two-tier secret model — mirrors `08` exactly

**Tier 1 — the master secret (`c6_01`), never rotated:**
- `random_password.konecta_db_password` (32 chars, `special = false` — alphanumeric only; punctuation in a generated password has broken DSN/connection-string parsing in this project before, same rationale as `08`'s `excludePunctuation = "true"`) + `aws_secretsmanager_secret.konecta_secret` + `aws_secretsmanager_secret_version.konecta_secret_value`.
- Fully Terraform-owned (no manual `create-secret` step) — this is the one deliberate divergence from `08`'s `gleamgoods-db-secret` (which is created manually, only ever read via a `data` source), per Konecta's explicit "don't make me create secrets by hand" ask. This ask was satisfied for the master secret; it could **not** be fully satisfied for tier 2 (see below) without contradicting `08`'s actual rotation mechanism.
- Used **only** as `aws_db_instance` master credentials via `local.konecta_master_secret_json` — never opened as an independent connection, never mounted to any pod, never rotated. No `lifecycle { ignore_changes }` needed since nothing external ever touches it.

**Tier 2 — per-database app secrets (`c9_03`), auto-rotated, what pods actually mount:**
- One `aws_secretsmanager_secret.konecta_app_db_secret` per database (`konecta-cart-db-secret`, etc.) — **container only**. The initial JSON value must be set manually, out-of-band, exactly like `08`'s `catalog-db-secret`/`orders-db-secret`:
  ```json
  {"username": "cart_app", "password": "<temp>", "engine": "postgres", "host": "<konecta-cart's endpoint>", "port": 5432, "dbname": "konecta_cart", "masterarn": "<c6_01 secret's ARN>"}
  ```
  The dedicated least-privilege app user (`cart_app` etc.) must **also** be created manually inside that database first — Terraform has no Postgres-role resource here, same gap `08` has.
- One `aws_secretsmanager_secret.konecta_app_db_master_secret` per database (`konecta-cart-db-secret-master`, etc.) — a host-qualified copy of the tier-1 master credential, needed because the rotation Lambda's `setSecret` step opens its own connection and needs `host`/`port`/`dbname`/`engine`, which tier-1's secret intentionally doesn't carry. **Unlike the app secret above, Terraform populates this one's value automatically** (`aws_secretsmanager_secret_version.konecta_app_db_master_secret_value`) — every field it needs (master creds, each instance's `.address`/`.db_name`) is already known to Terraform, so there's no reason to make this one manual too.

## Rotation infrastructure (`c9_02`, `c9_04`, `c9_05`) — mirrors `08`'s `c10_02`-`c10_04`

- `c9_02`: one dedicated rotation-Lambda security group per database (`for_each` over the static service-key set — see the cycle note below for why), egress-all. The RDS-side ingress allowing each in is added as an **inline** `dynamic "ingress"` block on the shared `aws_security_group.konecta_rds_postgresql_sg` (`c7_01`) — never a standalone `aws_security_group_rule`. Same gotcha `08` documents: a classic `aws_security_group`'s inline blocks are treated as the *complete* authoritative rule set the moment it has any, so a rule added via a separate resource gets silently revoked on the next unrelated apply.
- `c9_04`: one `aws_serverlessapplicationrepository_cloudformation_stack` (`SecretsManagerRDSPostgreSQLRotationMultiUser`) per database — same SAR app `08`'s Orders uses, same `excludePunctuation = "true"` parameter, `superuserSecretArn` pointing at that database's tier-2 master copy. `sar_publisher_account_id` variable added here (wasn't previously in this module) since it wasn't needed before rotation existed — default `297356227824`, same as `08`.
- `c9_05`: one `aws_secretsmanager_secret_rotation` per app secret, `rotate_immediately = false` (creating/updating this must never force a rotation as a side effect), `automatically_after_days = var.rotation_days` (default 30).

### A real dependency cycle was hit and fixed here — the reason for `c9_01`'s two locals

`c9_01_konecta_rotation_locals.tf` defines **two** locals, not one, and this split is load-bearing:
- `konecta_service_keys` — a static `toset([...])` of the 5 names, no dependency on anything.
- `konecta_databases` — a map carrying each instance's live `.address`/`.db_name`, which necessarily depends on the `aws_db_instance` resources.

Every `for_each` that doesn't need the live attributes (`c9_02`'s SGs, `c8_01`'s roles, `c8_02`'s policies, `c9_03`'s secret *containers*, `c9_04`'s SAR stacks, `c9_05`'s rotation config) uses `konecta_service_keys`. Only `c9_03`'s master-secret-copy **value** resource uses `konecta_databases`. Collapsing these into one local (using `konecta_databases` everywhere, since it has both keys and values) reintroduces a real cycle: `aws_db_instance` → its security group (`c7_01`) → the rotation Lambda SGs (`c9_02`) → a locals map reading `.address` back off `aws_db_instance`. Terraform caught this immediately (`terraform validate`/`plan` fail with a `Cycle:` error) — if refactoring this module, keep the split, don't "simplify" it away.

## Repo-wide conventions this module follows

- File naming: underscore convention (`c1_versions.tf` style), numbered by concern — `c1`–`c5` shared scaffolding (identical shape to `08`), `c6` = the master secret, `c7` = the 5 Postgres instances + their shared SG/subnet group, `c8` = per-service IAM roles/policies/pod-identity, `c9` = rotation infrastructure (locals, Lambda networking, secrets, SAR stacks, rotation config) — mirrors `08` numbering the rotation stuff separately (`08` uses `c10` for the same reason, despite it modifying `c6`/`c9`'s resources there too).
- Remote state key: `Konecta/databases/terraform.tfstate` — matches the `Konecta/ecr/terraform.tfstate` key already used by `06_Amazon_ECR_Konecta`'s `c1-versions.tf` (note: that module's own README.md still says `GleamGoods/ecr/terraform.tfstate`, which is stale/wrong — don't copy that mistake here or "fix" this module's key to match it).
- VPC/EKS remote state keys stay `GleamGoods/vpc/terraform.tfstate` / `GleamGoods/eks/terraform.tfstate` — Konecta does not have (and per current scope, should not get) its own VPC/EKS state.

## CI/CD — does not exist yet

Unlike `08_AWS_managed_databases` (`terraform-08-aws-managed-databases.yaml` + `-destroy.yaml`), there is no GitHub Actions workflow for this module, and none exists yet for `06_Amazon_ECR_Konecta` either — Konecta's Terraform modules currently apply manually. If adding one, copy `08`'s three-stage pattern (Trivy secret scan → Terraform Plan → manual-approval Terraform Apply via a GitHub Environment) and path-filter on `14_Konecta/03_AWS_managed_databases/**`.

## Apply status as of this writing

Code is written and validated (`terraform validate`/`plan` clean, `plan` showed 45 to add / 7 to change / 12 to destroy — the 12 destroys being full teardown of the abandoned custom-Lambda resources, nothing touching the live databases). **Not yet applied** — pending the manual per-database bootstrapping described above (dedicated app DB users + each app secret's initial JSON value), since the SAR rotation apps will exist but fail at first rotation without that. Check `terraform plan`/AWS directly rather than trusting this note once time has passed - both application state and this document can drift.

## What this module does NOT cover: the Kubernetes-side secret delivery

This module only builds the AWS side (Secrets Manager + rotation Lambda + IAM/Pod Identity to *allow* access). The actual pipeline that gets a secret's value into a running pod - `SecretProviderClass` CRD → Secrets Store CSI Driver → synced K8s `Secret` → `envFrom` → Reloader-triggered restart on rotation - is documented in full in `SECRETS.md` at the repo root, and lives in each **application's own Helm chart** (see `gleamgoods-catalog`'s chart for the pattern, e.g. the `secret-db.yaml` template referenced there), not in this Terraform module. None of Konecta's 5 backend service charts exist yet (only the frontend chart does, and it doesn't need a DB secret) - when they're built, each one needs its own `SecretProviderClass` pointing at its `konecta-<name>-db-secret`, following `SECRETS.md`'s pattern exactly. Don't consider Konecta's secrets "wired up" just because this Terraform module applied cleanly - the K8s-side half is a separate, not-yet-started piece of work.

## Explicitly out of scope (don't add unprompted)

- A dedicated Konecta VPC/EKS cluster — Konecta runs on the existing shared infrastructure.
- CI/CD workflow — not built yet, see above; only add if asked.
- Multi-AZ / production hardening (`skip_final_snapshot`, `deletion_protection`, single-AZ) — copied as-is from `08`'s dev-appropriate defaults, not reconsidered for a Konecta-specific prod posture.
- Automating the manual per-database app-user/secret bootstrap — `08` doesn't automate this either (no Postgres-role Terraform provider in use here); don't introduce one unprompted just to remove Konecta's manual step, since it'd be an inconsistency with how `08` itself is built.
