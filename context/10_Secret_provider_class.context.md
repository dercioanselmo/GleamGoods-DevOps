# Context: `10_Secret_provider_class`

You are senior devops engineer, and bellow is the complete brief for understanding (or cleaning up) this folder in the GleamGoods-DevOps project.

## What this folder actually is — read this before treating it as a requirement

Two standalone `SecretProviderClass` YAML files (`01_catalog_db_secretproviderclass.yaml`, `02_orders_db_secretproviderclass.yaml`) that **appear to be an early, standalone draft of what later became a Helm-templated resource inside the application repo's own charts** (`src/catalog/chart/templates/secretproviderclass.yaml`, etc. — see the application charts, source of truth for what's actually deployed). Evidence this folder is **not** the live/authoritative source:

- Grepped the entire repo: nothing — no CI workflow, no script, no other manifest folder — references or applies these two files.
- The `metadata.name` here is `catalog-db-secrets`; the actual live resource deployed via the app repo's Helm chart is named `{{ include "catalog.fullname" . }}-secrets`, which resolves to `catalog-secrets` — a **different name**, meaning these are not simply a copy of the live object, they'd create a **second, redundant** `SecretProviderClass` if applied.

**If reimplementing this project from scratch, don't recreate this folder as a requirement** — the actual `SecretProviderClass` resources belong templated inside each service's Helm chart (in the separate application repo), conditioned on `useSecretsManager`, exactly as documented in `SECRETS.md` §3. Recreate that instead. This folder's contents are useful only as a historical reference for what the hand-written, pre-Helm version of this resource looked like.

## If asked to clean up this repo

Flag this folder for removal (or at minimum, add a clear `README.md` inside it stating it's unused/superseded) rather than deleting it unilaterally — confirm with whoever owns the repo first, since it's possible it's kept intentionally as a reference/rollback artifact.

## What it would specify, if it were live (for historical/reference purposes only)

Each file: `provider: aws`, `usePodIdentity: "true"`, one `objects` entry per service's Secrets Manager secret (`gleamgoods-catalog-db-secret` / `gleamgoods-orders-db-secret`) with JMESPath extraction of `username`/`password`, and a `secretObjects` block syncing those into a K8s Secret (`catalog-db` / `orders-db`) under the `RETAIL_<SERVICE>_PERSISTENCE_USER`/`PASSWORD` keys — structurally identical in intent to what the live Helm-templated version does, just hand-written and now out of sync with it (different resource name, no Helm conditionals, no templating for region/secret name).
