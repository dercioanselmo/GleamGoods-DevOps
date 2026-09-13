# 14/03 — Konecta AWS Managed Databases

Provisions the 5 RDS PostgreSQL databases for Konecta's stateful microservices — Cart, Checkout, Security, Courier, Store Stock — plus the shared IAM/Secrets Manager wiring each service's pod needs to read its DB credentials.

This is a **Konecta-only** module, structurally modeled on `08_AWS_managed_databases` (the GleamGoods equivalent) but scoped to just Postgres and a single shared secret. **Rotation is not yet applied** — see "Rotation" below for the open question blocking it.

Consumes the **same shared VPC and EKS cluster** as the rest of GleamGoods, via `data.terraform_remote_state` — Konecta runs inside the `konecta` namespace of the existing cluster, it does not get its own VPC/EKS.

## What this creates

| Concern | Resource(s) | Notes |
|---|---|---|
| Networking | 1× `aws_security_group` (`c7_01`) | Shared by all 5 DBs. Allows port 5432 from the EKS cluster security group only. |
| Networking | 1× `aws_db_subnet_group` (`c7_02`) | Shared by all 5 DBs, across the VPC's private subnets. |
| Databases | 5× `aws_db_instance` (`c7_03`–`c7_07`) | `konecta-cart`, `konecta-checkout`, `konecta-security`, `konecta-courier`, `konecta-store-stock`. Postgres 17.6, `db.t4g.micro`, 20→100 GiB autoscaling storage, single-AZ, not publicly accessible, `skip_final_snapshot = true`. |
| Secret | `random_password` + `aws_secretsmanager_secret` + version (`c6_01`) | Creates the **one** `konecta-db-secret` — Terraform generates the password and sets the value, no manual step. Used as master username/password for all 5 databases. |
| IAM | 1× `aws_iam_role` (`c8_01`) + 1× `aws_iam_policy` (`c8_02`) | One role/policy shared by every Konecta service, scoped to `GetSecretValue`/`DescribeSecret` on `konecta-db-secret*` only. |
| Pod Identity | 5× `aws_eks_pod_identity_association` (`c8_03`–`c8_07`) | One per service account (`cart`, `checkout`, `security`, `courier`, `store-stock`) in the `konecta` namespace, all bound to the one shared role above. |

## The secret is created by Terraform — no manual step

Unlike GleamGoods' `gleamgoods-db-secret` (created out-of-band, only ever read via a `data` source), `konecta-db-secret` is fully managed here (`c6_01`):

- `random_password.konecta_db_password` generates a 32-character, alphanumeric-only password (no special characters — punctuation in a generated password has broken DSN/connection-string parsing in this project before, see `08_AWS_managed_databases`' rotation-Lambda gotcha).
- `aws_secretsmanager_secret.konecta_secret` creates the secret container.
- `aws_secretsmanager_secret_version.konecta_secret_value` sets its value to `{"username": "<konecta_db_username>", "password": "<generated>"}`.

Just run `terraform apply` — nothing to create by hand first. The username defaults to `konecta_admin` (`var.konecta_db_username`); override it in `terraform.tfvars` if you need something else.

To see the generated password: `terraform output` doesn't expose it (it's not declared as an output, since that would print it to state-inspection commands unnecessarily) — pull it from Secrets Manager instead: `aws secretsmanager get-secret-value --secret-id konecta-db-secret`.

## Rotation — not yet applied, blocked on a real architectural question

`08_AWS_managed_databases` rotates its per-service secrets using AWS's Serverless-Application-Repository rotation apps (`c10_03_rotation_lambdas.tf`: `SecretsManagerRDSMySQLRotationMultiUser` / `...PostgreSQLRotationMultiUser`, deployed via `aws_serverlessapplicationrepository_cloudformation_stack`). That's the intended pattern here too — **not** a hand-written Lambda.

**Open question that needs resolving before this can be built**: that SAR app rotates credentials against exactly **one** RDS host — it reads a single `host` field out of the secret it's rotating, and its `setSecret` step opens one connection to that one host. `konecta-db-secret` is one password shared identically across **5** separate RDS instances. Point one SAR rotation app at it and it can only ever rotate the password on whichever single host is in that secret's `host` field — the other 4 instances' live passwords never change, silently drifting from what the secret says, while still technically "working" since nothing forced them to change. Using the stock app here doesn't rotate all 5 databases; it rotates one and leaves the illusion that all 5 are covered.

`08` avoids this entirely by giving Catalog and Orders **separate** secrets — one SAR app, one host, one secret. Reconciling "SAR-style rotation, exactly like `08`" with "one shared secret across 5 hosts" needs a decision from whoever owns this requirement before any `c9`/`c10` files get written again: either (a) split into 5 secrets/5 SAR apps/5 Lambdas — mirrors `08` exactly, but is no longer "one shared secret", or (b) keep one shared secret and accept it can only be wired to rotate one of the 5 hosts via the stock app, or (c) something else. Nothing in this module currently attempts rotation — do not add a workaround Lambda to paper over this without that decision being made explicitly.

## Database naming

- `identifier` (the RDS instance name in the console) uses the hyphenated names you asked for: `konecta-cart`, `konecta-checkout`, etc.
- `db_name` (the actual Postgres database created inside the instance) uses underscores instead — `konecta_cart`, `konecta_checkout`, etc. — because Postgres database names can't contain hyphens.

## Variables

Defined in `c2_variables.tf`, overridden in `terraform.tfvars`:

| Name | Value | Notes |
|---|---|---|
| `aws_region` | `us-east-1` | |
| `project_name` | `konecta` | |
| `business_division` | `retail` | Same org-wide division as the GleamGoods modules, giving the `retail-konecta` naming prefix (`local.name`). |
| `konecta_db_secret_name` | `konecta-db-secret` | |
| `konecta_db_username` | `konecta_admin` | The master username baked into the secret's bootstrap value. |
| `rotation_days` | `30` | Unused until rotation is actually implemented (see "Rotation" above) — kept so the value's already decided when it is. |
| `tags` | `{ Terraform, Environment, Project, ManagedBy }` | |

## State

Remote, same S3 backend bucket as everything else (`tfstate-dev-us-east-1-1v8wcs`), its own key: `Konecta/databases/terraform.tfstate` — matching the `Konecta/ecr/terraform.tfstate` convention already used by `06_Amazon_ECR_Konecta`.

## Deploying

```bash
terraform init
terraform plan
terraform apply
```

No CI/CD workflow exists for this module yet (unlike `08_AWS_managed_databases`, which has `terraform-08-aws-managed-databases.yaml`) — applies are manual for now. If you want one, copy that workflow's pattern (Trivy scan → plan → manual-approval apply via a GitHub Environment) and point it at `14_Konecta/03_AWS_managed_databases/**`.

## Destroy order

No `data.terraform_remote_state` dependency from any other module onto this one's outputs, so it can be destroyed independently — but it does depend on the shared VPC/EKS state existing, so don't destroy `02_VPC`/`03_EKS_with_addons` before this. Destroying it deletes all 5 Konecta databases (final snapshots are **skipped**, so this is unrecoverable) and the shared IAM role/pod identity associations — confirm no Konecta service is expected to be reachable before destroying.

## Known gaps / deliberately out of scope

- **No credential rotation yet** — see "Rotation" above; blocked on reconciling "one shared secret" with the SAR rotation app's one-host-per-secret design, not yet a code problem.
- **No CI/CD workflow** — see above.
- **Master credentials shared across all 5 databases** — a compromise of `konecta-db-secret` affects every Konecta service at once, since there's no blast-radius isolation between them (unlike GleamGoods' `08_AWS_managed_databases` per-service secrets). Accepted per the "one secret for everything" requirement — revisit if any one Konecta service's data becomes more sensitive than the others.
