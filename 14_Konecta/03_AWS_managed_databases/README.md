# 14/03 — Konecta AWS Managed Databases

Provisions the 5 RDS PostgreSQL databases for Konecta's stateful microservices — Cart, Checkout, Security, Courier, Store Stock — plus the shared IAM/Secrets Manager wiring each service's pod needs to read its DB credentials.

This is a **Konecta-only** module, structurally modeled on `08_AWS_managed_databases` (the GleamGoods equivalent) but deliberately simpler: Konecta uses a single shared database secret for every service, instead of GleamGoods' per-service secret + automatic rotation Lambda setup. There is no rotation infrastructure here.

Consumes the **same shared VPC and EKS cluster** as the rest of GleamGoods, via `data.terraform_remote_state` — Konecta runs inside the `konecta` namespace of the existing cluster, it does not get its own VPC/EKS.

## What this creates

| Concern | Resource(s) | Notes |
|---|---|---|
| Networking | 1× `aws_security_group` (`c7_01`) | Shared by all 5 DBs. Allows port 5432 from the EKS cluster security group only. |
| Networking | 1× `aws_db_subnet_group` (`c7_02`) | Shared by all 5 DBs, across the VPC's private subnets. |
| Databases | 5× `aws_db_instance` (`c7_03`–`c7_07`) | `konecta-cart`, `konecta-checkout`, `konecta-security`, `konecta-courier`, `konecta-store-stock`. Postgres 17.6, `db.t4g.micro`, 20→100 GiB autoscaling storage, single-AZ, not publicly accessible, `skip_final_snapshot = true`. |
| Secret | `data.aws_secretsmanager_secret` + version (`c6_01`) | Reads the **one** pre-existing `konecta-db-secret` — used as master username/password for all 5 databases. |
| IAM | 1× `aws_iam_role` (`c8_01`) + 1× `aws_iam_policy` (`c8_02`) | One role/policy shared by every Konecta service, scoped to `GetSecretValue`/`DescribeSecret` on `konecta-db-secret*` only. |
| Pod Identity | 5× `aws_eks_pod_identity_association` (`c8_03`–`c8_07`) | One per service account (`cart`, `checkout`, `security`, `courier`, `store-stock`) in the `konecta` namespace, all bound to the one shared role above. |

## Prerequisite: the secret must already exist

Terraform only **reads** `konecta-db-secret` (via `data` sources in `c6_01`) — it never creates or sets its value, the same pattern GleamGoods uses for `gleamgoods-db-secret`. Before running `apply` for the first time, create it manually, e.g.:

```bash
aws secretsmanager create-secret \
  --name konecta-db-secret \
  --secret-string '{"username":"konecta_admin","password":"<a-strong-password>"}'
```

If the secret doesn't exist yet, `terraform plan`/`apply` will fail at the `data.aws_secretsmanager_secret.konecta_secret` lookup.

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
| `konecta_db_secret_name` | `konecta-db-secret` | Must match the secret you create manually (see above). |
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

- **No credential rotation.** All 5 databases and every Konecta service share one static secret — if you need auto-rotation like GleamGoods' `08_AWS_managed_databases` (`c10_*` files), that's a separate, larger change (per-service secrets, host-qualified master-secret copies, SAR rotation Lambdas) and should be scoped deliberately, not bolted on ad hoc.
- **No CI/CD workflow** — see above.
- **Master credentials shared across all 5 databases** — a compromise or rotation of `konecta-db-secret` affects every Konecta service at once, since there's no blast-radius isolation between them. Acceptable for now per the "one secret for everything" requirement, but worth revisiting if any one Konecta service's data becomes more sensitive than the others.
