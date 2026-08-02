# Context: `08_AWS_managed_databases` Terraform module

You are senior devops engineer, and bellow is the complete brief for implementing (or re-implementing) the managed-databases module of the GleamGoods-DevOps project.

## Purpose

Provisions the data layer for all 4 stateful microservices — Catalog (RDS MySQL), Orders (RDS PostgreSQL + SQS), Cart (DynamoDB), Checkout (ElastiCache Redis) — plus the full zero-downtime credential-rotation system for the two RDS-backed secrets. This is the largest module after `03_EKS_with_addons` in scope, and the one with the most non-obvious operational gotchas, several discovered only through live incidents. **For the rotation mechanism's full design rationale and step-by-step mechanics, defer to `SECRETS.md` at the repo root — that document is the authoritative deep-dive; this file focuses on what to build and the gotchas not obvious from reading AWS's own docs.**

Consumes `02_VPC` and `03_EKS_with_addons` via `data.terraform_remote_state`.

## Shared foundation

- One shared Pod Identity assume-role policy document (`pods.eks.amazonaws.com` principal, `sts:AssumeRole` + `sts:TagSession`), defined **once** in its own file, referenced by every per-service IAM role in this module — don't redeclare it per service.
- `local.name = "${business_division}-${project_name}"`, same convention as `03`/`04`/`05`.

## Catalog — RDS MySQL

- Security group allowing 3306 from the EKS cluster security group (inline `ingress {}` block — see the SG-rules gotcha below, this matters a lot for this module specifically).
- DB subnet group across the private subnets.
- `aws_db_instance`: `engine = "mysql"`, master `username`/`password` read from a `data "aws_secretsmanager_secret"`/`data "aws_secretsmanager_secret_version"` pair pointed at the master secret (see Rotation section) — **not hardcoded, not a `random_password` resource**. `publicly_accessible = false`, `skip_final_snapshot = true` (dev-appropriate; reconsider for prod), single-AZ.
- Dedicated Pod Identity IAM role for the CSI driver to assume on Catalog's behalf, scoped only to `secretsmanager:GetSecretValue`/`DescribeSecret` on the Catalog app secret's ARN prefix — not the master secret, not Orders' secret.

## Orders — RDS PostgreSQL + SQS

- Same shape as Catalog: security group (5432, inline ingress from EKS cluster SG), subnet group, `aws_db_instance` (`engine = "postgres"`) reading master credentials the same way, dedicated scoped Pod Identity role.
- **Plus SQS**: one queue (`<name>-orders-queue`, `message_retention_seconds = 86400`, standard — not FIFO), and an IAM policy granting `sqs:SendMessage`/`ReceiveMessage`/`DeleteMessage`/`GetQueueAttributes`/`GetQueueUrl`/`ListQueues`/`PurgeQueue` scoped to that one queue's ARN. **Attach this policy to the same IAM role Orders already has for Secrets Manager access** — don't create a second Orders role. One role per service, multiple policies attached to it, is the pattern throughout this module.

## Cart — DynamoDB

- Table name `Items`, `PAY_PER_REQUEST` billing, hash key `id` (string), a global secondary index `idx_global_customerId` on `customerId`.
- IAM policy: broad DynamoDB actions (`CreateTable` through `BatchWriteItem`, plus `DescribeTimeToLive`/`ListTables`/`ListTagsOfResource`), `Resource = "*"`. **This is genuinely broader than the least-privilege pattern used for Catalog/Orders' Secrets Manager access** (those are ARN-scoped; this is account-wide `*`) — a known, existing gap, not something to silently narrow without flagging, since narrowing it needs to be checked against what the actual DynamoDB table ARN(s) are first.
- Pod Identity association: **service account name is `carts`** (plural) — not `cart`, matching the actual application deployment's service account name. Easy mismatch to introduce if guessing from the folder/module naming instead of checking the app chart.

### Critical: Cart's DynamoDB table must be created in `us-west-2`, not the project's primary region

The Cart microservice's application code is **hardcoded** to connect to the `us-west-2` DynamoDB endpoint, regardless of what region the rest of the infrastructure deploys to (this project's primary region is `us-east-1` everywhere else). This requires a second, aliased AWS provider (`provider "aws" { alias = "west2", region = "us-west-2" }`, declared once in `c1_versions.tf` alongside the primary provider) and the DynamoDB table resource must set `provider = aws.west2` explicitly. **Get this wrong and Cart's table exists in the wrong region while every other resource in this project sits in `us-east-1`, and the application will fail to find its table at runtime** — this isn't a Terraform bug, it's matching an application-code constraint that lives in a different repo (`DynamoDBConfiguration.java`). If reimplementing, verify against the current application code whether this constraint still holds before assuming `us-west-2` is still correct.

## Checkout — ElastiCache Redis

**Current state: plain, unauthenticated `aws_elasticache_cluster`** — no `auth_token`, no `transit_encryption_enabled`, access control is security-group-only (6379 from the EKS cluster SG). Node type `cache.t3.micro`, single node, `engine_version = "7.1"`.

**This is a deliberate reversion, not an oversight — a Secrets-Manager-backed, AUTH-token version (`aws_elasticache_replication_group` with `auth_token`, a dedicated Secrets Manager secret, Pod Identity role, and app-side CSI wiring) was fully implemented and then explicitly reverted** because the app-side change it required (reading the token from a CSI-mounted file rather than a synced K8s Secret) broke the Reloader-driven auto-refresh pattern used everywhere else, and that tradeoff wasn't accepted. If asked to add Redis credentials again, don't silently repeat the same app-side approach — the credential-delivery model needs to be one that preserves `secretObjects`/`envFrom`/Reloader, matching how Catalog/Orders deliver their DB credentials, not the mounted-file-read-at-startup alternative. Full context on why that alternative was rejected: `SECRETS.md` §3.

## Rotation infrastructure — the core of this module

Full mechanics and rationale: `SECRETS.md`. Summary of what to build:

- **Per-service app secrets** (`aws_secretsmanager_secret` containers only — Terraform never writes their `secret_string`; the initial value is set once, manually, via CLI/console, matching how the value AWS's rotation Lambda itself expects to find: `{"username", "password", "engine", "host", "port", "dbname", "masterarn"}`).
- **Per-service host-qualified master-secret copies** (`*-secret-master`) — required because the rotation Lambda's `setSecret` step needs its own DB connection info (`host`/`port`/`dbname`/`engine`), which the *original* shared master secret (used only as a Terraform `data` source elsewhere) never had. One master-copy secret per service, each holding the same underlying master credential, host-qualified for that service's specific RDS instance.
- **Rotation Lambdas via SAR** (`aws_serverlessapplicationrepository_cloudformation_stack`, not a directly-authored Lambda) — `SecretsManagerRDSMySQLRotationMultiUser` for Catalog, `SecretsManagerRDSPostgreSQLRotationMultiUser` for Orders. Required parameters: `endpoint` (regional Secrets Manager endpoint), `functionName`, `superuserSecretArn` (the host-qualified master copy, not the original shared secret), `vpcSecurityGroupIds`/`vpcSubnetIds` (a dedicated SG per Lambda, in the private subnets). **Two behavioral parameters that must be set, not left at SAR defaults**: `usernameLimit = "32"` (the SAR default of 16 is too small to fit `<service>_app` + the Lambda's own `_clone` suffix), `excludePunctuation = "true"` (the default character-exclusion set is not enough — real incident: a generated password containing `%`/`>`/`<` broke DSN/connection-string parsing in application code; alphanumeric-only avoids this entire class of bug).
- **The SAR publisher account ID is a variable, not a hardcoded literal in the ARN** (`var.sar_publisher_account_id`, default `297356227824` — AWS's own publisher account, not this project's account) — keep it out of the raw `application_id` ARN string.
- **`aws_secretsmanager_secret_rotation`** per app secret: `rotation_lambda_arn` from the SAR stack's `RotationLambdaARN` output, `rotation_rules.automatically_after_days = 30`, **`rotate_immediately = false`** — creating/updating this resource must never force-trigger a rotation as a side effect.
- **Per-service IAM policies scoped to exactly one secret's ARN prefix** (`secretsmanager:GetSecretValue`/`DescribeSecret` on `<service>-db-secret*` only) attached to each service's own Pod Identity role — never a shared policy covering both services' secrets.

### Networking gotcha — inline SG rules only, never standalone `aws_security_group_rule` for these SGs

The RDS security groups (Catalog's, Orders') already manage their ingress via inline `ingress {}` blocks (for EKS cluster access). **Add the rotation Lambda's access as an additional inline block in the same `aws_security_group` resource — never as a separate, standalone `aws_security_group_rule` resource.** Terraform's classic `aws_security_group` resource treats its own inline blocks as the *complete* list of allowed rules the moment it has any; a rule added via a separate resource gets silently revoked on the next unrelated apply that touches that security group. This caused a real incident. (A known, deferred improvement: migrating to `aws_vpc_security_group_ingress_rule`/`_egress_rule` — the newer per-rule resource model that doesn't have this authority conflict — was discussed and deferred to the next full infrastructure rebuild, not yet done.)

### Known deferred items — don't act on these unprompted

- **Retiring the original shared `gleamgoods-db-secret`** — it's still a live dependency: both `aws_db_instance` resources (Catalog, Orders) read their `username`/`password` directly from it via a `data` source at every plan/apply. Deleting it today breaks planning for the entire module. Deferred to the next full cluster/database destroy-and-recreate cycle, at which point `c6_04`/`c9_03` need to be re-pointed at one of the host-qualified master copies (or have `username`/`password` dropped from active management via `lifecycle { ignore_changes }`) before the original secret can be removed.
- **The inline-SG-rules-vs-newer-resource-model migration** noted above — same deferred timing.

## Repo-wide conventions this module must follow

- File naming: underscore convention (`c1_versions.tf`), numbered by concern: `c5` = shared Pod Identity assume-role, `c6` = Catalog, `c7` = Cart, `c8` = Checkout, `c9` = Orders, `c10` = rotation infrastructure (added later, hence the higher number despite applying to `c6`/`c9`'s secrets).
- Remote state key: `GleamGoods/databases/terraform.tfstate`.
- Every per-service IAM role's Pod Identity association uses `namespace = "default"` — all application workloads in this project run in the `default` namespace, not per-service namespaces.

## CI/CD

Same three-stage pattern (`TF-08_AWS_managed_databases`, Trivy → plan → manual-approval apply via GitHub Environment), OIDC via the role from `01_remote_backend_s3bucket`. This workflow is also triggered by `workflow_run` completion of `TF-03_EKS_with_addons` (in addition to its own path-based trigger) — since this module depends on the EKS cluster and Pod Identity agent existing, its CI chains off that module's successful run, not just off changes to its own files.

## Explicitly out of scope

- Rotation mechanics/rationale beyond what's summarized above — see `SECRETS.md`.
- The Checkout Redis AUTH-token implementation — reverted, see above; don't reintroduce without also solving the app-side Reloader-compatibility problem.
- Narrowing Cart's DynamoDB IAM policy from `Resource = "*"` — a known gap, not yet addressed, needs the actual table ARN(s) confirmed first.
- Any change to which region Cart's DynamoDB table lives in — hardcoded application-code constraint, verify against the app repo before touching.
