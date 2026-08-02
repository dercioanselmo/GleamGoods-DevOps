# Context: `13_RBAC_NetworkPolicy`

You are senior devops engineer, and bellow is the complete brief for implementing (or re-implementing) the Kubernetes-level access-control manifests of the GleamGoods-DevOps project.

## Purpose

Kubernetes-native access control layered on top of everything else: `RBAC` scoping who can read specific Secrets or exec into pods, and `NetworkPolicy` scoping what each service's pods can talk to. Plain manifests, **no Terraform, no CI**, applied by hand. Grew out of a deliberate decision **not** to eliminate the `catalog-db`/`orders-db` Kubernetes Secret objects (an alternative, mounted-file-only approach was tried and reverted — see `08_AWS_managed_databases.context.md` and `SECRETS.md`) — RBAC + NetworkPolicy is the chosen mitigation instead.

## `01_RBAC/` — two narrowly-scoped `Role`s, deliberately not pre-bound

- **`db-secrets-reader`**: `get`/`list`/`watch` on `secrets`, `resourceNames` scoped to exactly `catalog-db` and `orders-db` — not a blanket Secrets-read grant. Ship with a `RoleBinding` **commented out** in the same file, with a placeholder subject — applying this file grants nobody access until a specific principal is deliberately bound. Don't ship it pre-bound to anyone by default.
- **`pod-exec-limited`**: `pods/exec` (`create`) + `pods/log` (`get`), scoped to the `default` namespace only — can't be scoped to specific pod names in this project, since Argo Rollouts generates a new pod name on every deploy. Same commented-out-binding pattern.
- **Why both roles exist together**: reading a Secret via the Kubernetes API and reading the same value out of a running pod's process environment via `kubectl exec` are two *separate* RBAC permissions (`secrets:get` vs `pods/exec:create`). Restricting only the Secret-read leaves `pods/exec` as a complete bypass — anyone who can exec into a `catalog`/`orders` pod can just run `env | grep PASSWORD` regardless of Secret-level RBAC. Document this pairing explicitly if reimplementing rather than treating them as unrelated hardening items.
- **Neither role restricts anyone already holding cluster-admin** (via `bootstrap_cluster_creator_admin_permissions` in `03_EKS_with_addons`, or an EKS access entry with `AmazonEKSClusterAdminPolicy`/`AmazonEKSAdminPolicy` — e.g. the GitHub Actions Terraform CI role). RBAC restrictions never apply to cluster-admin; that's a separate, unaddressed access-scope question, not something these two roles solve.

## `02_NetworkPolicy/` — default-deny baseline + targeted allow rules

- **`01_default-deny.yaml`**: empty `podSelector` (matches every pod in `default`), both `Ingress` and `Egress` policy types. Every other policy in this folder is additive on top of this.
- **`02_allow-dns-egress.yaml`**: required alongside the default-deny or DNS resolution breaks cluster-wide — UDP/TCP port 53 egress to any namespace (CoreDNS). Apply this in the same batch as the default-deny, never one without the other.
- **`03_catalog-network-policy.yaml`** / **`04_orders-network-policy.yaml`**: per-service `podSelector` (`app.kubernetes.io/name: catalog`/`orders`, matching the actual chart-rendered selector labels). Egress: DB port (3306/5432) scoped to the VPC CIDR (`10.0.0.0/16`) — RDS's own security group is the primary control, this is defense-in-depth, not the only layer. Ingress: from `ui` (and, for Orders, also from `checkout`, matching the one confirmed direct service-to-service call — `RETAIL_CHECKOUT_ENDPOINTS_ORDERS: http://orders` in checkout's config) — **explicitly flagged as best-effort, not a verified full call graph**; confirm actual traffic patterns before ever enabling enforcement, and note that if the AWS Load Balancer Controller ever routes directly to `catalog`/`orders` (not just `ui`), these rules would also need to allow from the VPC CIDR, since ALB-to-pod traffic in IP-target mode doesn't originate from a Kubernetes pod that `NetworkPolicy` can select by label.

### Why HTTPS egress is `0.0.0.0/0`, not the VPC CIDR — don't "tighten" this without adding VPC endpoints first

This project has no VPC interface endpoints (PrivateLink) for Secrets Manager, STS, or SQS. Traffic to those AWS APIs leaves the VPC via NAT Gateway to AWS's public regional endpoints — it does **not** stay inside `10.0.0.0/16`. `NetworkPolicy` only understands IP/CIDR, not "AWS service" as a concept, so `443` egress can't be scoped tighter than "anywhere" without first adding VPC endpoints for those specific services. If asked to hardn egress further, adding VPC endpoints (a `02_VPC` or `08_AWS_managed_databases`-adjacent Terraform change) is the actual prerequisite, not a `NetworkPolicy` change alone.

## Critical dependency: none of this is enforced without `vpc-cni`'s network-policy feature enabled

Plain AWS VPC CNI does not enforce `NetworkPolicy` objects at all by default — the Kubernetes API accepts them regardless, with zero effect on actual traffic, unless a policy engine is running. This project's chosen mechanism: `03_EKS_with_addons`'s adoption of `vpc-cni` as a Terraform-managed `aws_eks_addon` with `configuration_values.enableNetworkPolicy = "true"` (deploys the AWS Network Policy Agent). **Apply order matters and both sides are required**: the Terraform addon change alone enforces nothing (no `NetworkPolicy` objects exist yet), and applying this folder's manifests alone without that addon change is exactly the "accepted but not enforced" state. Neither is sufficient on its own. See `03_EKS_with_addons.context.md` for the addon-adoption details (including the real CNI version bump that comes with it, and why Calico/Cilium were considered and not chosen).

## Repo-wide conventions

- Two numbered subfolders (`01_RBAC/`, `02_NetworkPolicy/`), numbered files within each reflecting apply order — same convention as this project's other manual-manifest folders.

## CI/CD

None — manual `kubectl apply -f` only.

## Explicitly out of scope

- Enabling `vpc-cni`'s network-policy feature itself — Terraform concern (`03_EKS_with_addons`), this folder only supplies the policy objects that feature then enforces.
- VPC interface endpoints for AWS APIs — not yet implemented anywhere in this project; a prerequisite for tightening the `0.0.0.0/0` HTTPS egress rule, not something to add inside this folder.
- RBAC/NetworkPolicy for `ui`, `cart`, `checkout` — currently only `catalog` and `orders` have dedicated `NetworkPolicy` objects (the two services with database credentials, the original motivating concern); extending the same pattern to the other three services is a reasonable next step but not yet done.
