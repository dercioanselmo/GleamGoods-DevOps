# Context: `07_ArgoCD_Install`

You are senior devops engineer, and bellow is the complete brief for implementing (or re-implementing) the ArgoCD/Argo Rollouts install step of the GleamGoods-DevOps project.

## Purpose

**Not a Terraform module** — this is a set of shell scripts + plain Kubernetes manifests, applied by hand, that bootstrap the GitOps layer on top of the EKS cluster: ArgoCD itself (the GitOps sync engine) and Argo Rollouts (the canary/progressive-delivery controller every application workload in this project uses as its deployment primitive). Both are `argoproj.io` tools but serve completely different purposes — don't conflate them into one install step or one write-up; keep them as clearly separate concerns even though they live in the same folder.

This folder only *installs the platform*. It does **not** define what ArgoCD manages — the actual `Application` custom resources pointing at the application repo's Helm charts live in a different folder (`11_Gleamgoods_application_K8s_manifests/02_argocd-helm-manifests/`), applied separately, after this. Don't fold Application definitions into this step.

## ArgoCD install — required sequence

1. Create namespace `argocd`.
2. Install ArgoCD's own upstream manifests directly from the project's official release URL (`https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml`), applied with `--server-side --force-conflicts` — not `helm install`. This project intentionally installs ArgoCD from its raw upstream manifest, not a Helm chart, unlike almost everything else in this project (which prefers Helm). Preserve this choice unless there's a specific reason to switch to the Helm chart.
3. Wait for `argocd-server` to roll out before doing anything else.
4. Retrieve the auto-generated initial admin password from the `argocd-initial-admin-secret` Kubernetes Secret (`kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 --decode`) and print it — **the script's job ends at printing it to the terminal.** It does not persist this password anywhere durable.
5. **A required follow-up step not currently in this folder's scripts at all**: register this repo with ArgoCD as a Git source (`argocd repo add https://github.com/dercioanselmo/GleamGoods-DevOps.git --username <gh-user> --password <PAT> --name GleamGoods-DevOps`) — needed because this is a private repo. Currently only documented as a manual note in the project's root README, not scripted here; worth scripting if reimplementing this cleanly.

### What happens to the admin password after step 4 — don't assume auto-persistence

A copy of this password exists in AWS Secrets Manager (`gleamgoods/argocd/admin-password`) in the live account, but **that was created manually, out-of-band, by an operator copying the script's printed output** — not by any code in this folder. If reimplementing this install step and durable password storage is wanted, that has to be added explicitly (e.g. `aws secretsmanager put-secret-value` as an additional script step) — don't assume a Secrets Manager entry appears automatically just because one currently exists in the live account.

## Argo Rollouts install — separate tool, separate script

1. Add/update the `argo` Helm repo (`https://argoproj.github.io/argo-helm`).
2. Create namespace `argo-rollouts`.
3. `helm upgrade --install argo-rollouts argo/argo-rollouts --namespace argo-rollouts --set dashboard.enabled=true` — **the dashboard must be explicitly enabled**, it's not on by default in the chart. This is what makes `kubectl argo rollouts dashboard` / the web UI on port 3100 available.
4. Wait for both the controller and dashboard deployments to roll out (the dashboard wait should tolerate failure gracefully — `|| true` — since not every environment necessarily needs it to block the install).

This is a Helm-based install (unlike ArgoCD's raw-manifest install above) — the two tools deliberately use different install mechanisms in this project; that's not an inconsistency to "fix."

## Ingress

`03_argocd-ingress.yaml` is the real, live ArgoCD ingress: ALB, `internet-facing`, `target-type: ip`, health check on `/healthz`, ExternalDNS annotation producing `argocd.dercioanselmo.com`. **Notice `alb.ingress.kubernetes.io/group.name: gleamgoods`** — this ingress deliberately shares one ALB with other ingresses carrying the same group name (a cost-saving pattern: one ALB serving multiple hostnames/ingresses via listener rules, rather than one ALB per ingress). Preserve the shared group name if reimplementing additional ingresses in this project rather than defaulting to a dedicated ALB per service.

**`02_argocd_ingress_https.yaml` is not actually an ArgoCD resource and appears to be stale/misplaced** — it's an ingress for the `ui` service (retail-store UI), referencing an ACM certificate ARN under a *different* AWS account ID (`180789647333`) than every other live resource in this project (`564956047797`). Almost certainly a leftover example or an earlier draft from before this project settled on its current account, sitting in the wrong folder. Don't treat this file's content as current, required architecture if reimplementing — verify against whatever the live UI ingress actually is (likely defined in the application Helm chart itself, not standalone here) before reproducing anything from it.

## Repo-wide conventions this step follows

- File naming: numbered scripts/manifests (`01_`, `02_`, `03_`, `04_`) in apply order — same numbering-as-sequence convention used by this project's other non-Terraform manifest folders (`09_KARPENTER_k8s-manifests`, `12_Open_Telemetry`, `13_RBAC_NetworkPolicy`), just predating them and mixing scripts with YAML rather than being pure YAML.
- `set -e` in both scripts — fail fast, don't continue past a failed step.

## CI/CD

**None.** No `.github/workflows/` entry exists for this folder, and none should be added casually — this is a one-time (or rare, deliberate re-run) cluster bootstrap step run by a human with `kubectl`/`helm` access to the cluster, not something that should auto-run on every push. Same "manual by design" character as `01_remote_backend_s3bucket`, for a different reason (there it's a chicken-and-egg bootstrap constraint; here it's simply that GitOps-platform installation isn't a "deploy on every commit" kind of operation).

## Explicitly out of scope

- ArgoCD `Application` custom resources (what ArgoCD actually syncs) — live in `11_Gleamgoods_application_K8s_manifests/02_argocd-helm-manifests/`, a separate, later step.
- Any Terraform — this entire step is intentionally outside Terraform's management. If asked to "Terraform-ify" ArgoCD's own install, that's a deliberate architectural change to discuss first, not an assumed improvement (installing ArgoCD via a `helm_release` Terraform resource is possible and common elsewhere, but isn't how this project currently does it).
- The stale `02_argocd_ingress_https.yaml` file's content — don't treat it as a real requirement; flag it for cleanup/removal if asked to tidy this folder.
