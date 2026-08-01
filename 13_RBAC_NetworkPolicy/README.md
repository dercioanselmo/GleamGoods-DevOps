# 13 — RBAC & NetworkPolicy

Plain Kubernetes manifests, same pattern as `09_KARPENTER_k8s-manifests/` and `12_Open_Telemetry/` — **no Terraform, no CI workflow, applied by hand** via `kubectl apply -f`. Nothing in this folder has been applied yet.

Grew out of the Secrets architecture discussion in [`SECRETS.md`](../SECRETS.md): after reverting the `catalog`/`orders` DB-credential delivery model back to the K8s-Secret + Reloader approach, the follow-up question was how to reduce that Secret's exposure without giving up the automatic rotation-pickup. The answer landed on RBAC (who can read the Secret / exec into the pod) plus NetworkPolicy (what the pod can talk to), rather than avoiding a K8s Secret object entirely.

## 01_RBAC/

Two narrowly-scoped `Role`s, each with a commented-out example `RoleBinding` (left commented so applying these grants nobody access until you decide who should actually be bound):

- **`01_db-secrets-reader-role.yaml`** — read-only (`get`/`list`/`watch`) on exactly `catalog-db` and `orders-db`, via `resourceNames`. Bind this to whoever genuinely needs to inspect those two Secrets, instead of handing them a broader admin/edit grant that happens to include Secrets as a side effect.
- **`02_pod-exec-limited-role.yaml`** — `pods/exec` + `pods/log`, scoped to the `default` namespace (can't be scoped to a specific pod name here — Argo Rollouts generates a new pod name every deploy).

**Why both:** reading a Secret via the API and reading the same value out of a running pod's environment via `kubectl exec` are two different RBAC permissions (`secrets:get` vs `pods/exec:create`). Restricting only one leaves the other as a complete bypass — anyone who can exec into a `catalog`/`orders` pod can just run `env | grep PASSWORD`, no Secret-read permission required.

**These Roles do nothing for anyone who already has cluster-admin** (e.g. via `bootstrap_cluster_creator_admin_permissions`, or an EKS access entry with `AmazonEKSClusterAdminPolicy` — like the GitHub Actions Terraform CI role from `01_remote_backend_s3bucket`). RBAC restrictions never apply to cluster-admin; that's a separate access-scope question, not addressed here.

## 02_NetworkPolicy/

- **`01_default-deny.yaml`** — default-deny ingress+egress for the whole `default` namespace. Every other policy here is additive on top of this baseline.
- **`02_allow-dns-egress.yaml`** — required alongside the default-deny, or DNS breaks for every pod in the namespace.
- **`03_catalog-network-policy.yaml`** / **`04_orders-network-policy.yaml`** — scoped egress (DB port to the VPC CIDR, HTTPS to `0.0.0.0/0` for AWS API calls — see note below on why that's not scoped tighter) and best-effort ingress (from `ui`, and for orders also from `checkout`, matching the one documented direct service-to-service call in this project).

### ⚠️ Enforcement — now implemented in Terraform, not yet applied

When this was first written, this cluster ran plain AWS VPC CNI (`aws-node` DaemonSet only) with no policy engine, so any `NetworkPolicy` object here would have been accepted by the API with zero actual effect.

That's now addressed: `03_EKS_with_addons/c21-01-vpccni-eksaddon.tf` adopts `vpc-cni` as a Terraform-managed EKS addon (it was previously running unmanaged, untracked by Terraform) with `configuration_values.enableNetworkPolicy = "true"`, which deploys the AWS Network Policy Agent alongside the existing CNI. Chosen over Calico/Cilium since it's the native AWS-provided option and this project is AWS-native throughout.

**Apply order matters:** that Terraform change needs to be applied *before* (or at the same time as) the policies in `02_NetworkPolicy/` for them to have any effect — applying the addon alone changes nothing (no `NetworkPolicy` objects exist yet to enforce), and applying the policies alone without the addon is exactly the "accepted but not enforced" state described above. Neither has been applied yet — see `03_EKS_with_addons/README.md` for that module's own apply process.

One real side effect worth knowing: adopting `vpc-cni` under Terraform also bumps its version (it was running self-managed at `v1.21.2-eksbuild.2`; the pinned Terraform version is `v1.22.3-eksbuild.1`, AWS's current default for this cluster's Kubernetes version) — this is a genuine CNI upgrade, not just a config flag flip, so it's worth watching the node/pod networking closely on whichever apply run picks it up.

### Why HTTPS egress is `0.0.0.0/0`, not the VPC CIDR

This project has no VPC interface endpoints (PrivateLink) for Secrets Manager, STS, or SQS. Traffic to those AWS APIs leaves the VPC via the NAT Gateway to AWS's public regional endpoints — it does not stay inside `10.0.0.0/16`. `NetworkPolicy` only understands IP/CIDR, not "AWS service," so without VPC endpoints this can't be scoped tighter than "port 443 to anywhere." Adding VPC endpoints for these services would let this be narrowed later.

### Ingress rules are best-effort — verify before ever enabling enforcement

The `ui`/`checkout` → `catalog`/`orders` ingress rules are based on the documented architecture (ui aggregates calls to the other services; checkout calls orders directly per its `RETAIL_CHECKOUT_ENDPOINTS_ORDERS` config), not a verified full call graph. If the AWS Load Balancer Controller ever routes directly to `catalog`/`orders` (not just to `ui`), these policies would also need to allow from the VPC CIDR on the relevant port — ALB-to-pod traffic (IP target mode) doesn't originate from a Kubernetes pod that `NetworkPolicy` can select by label.
