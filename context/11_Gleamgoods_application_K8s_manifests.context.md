# Context: `11_Gleamgoods_application_K8s_manifests`

You are senior devops engineer, and bellow is the complete brief for understanding (and correctly re-implementing only the live parts of) this folder in the GleamGoods-DevOps project.

## Read this first — this folder mixes live and historical content; know which is which

This folder contains **three subfolders with very different status**:

1. **`02_argocd-helm-manifests/` — LIVE, authoritative.** 5 ArgoCD `Application` resources. This is what's actually deployed and actively syncing.
2. **`03_Verification_Pods/` — LIVE, actively useful.** Diagnostic client pods for manually verifying each microservice's connectivity to its AWS-managed dependency. Genuinely used during development/incident response.
3. **`01_microservices/` — HISTORICAL / NOT the deployment source of truth, and confirmed out of sync with what's actually live.** Contains, per service, both a `01_K8s_manifests/` (raw, pre-Helm YAML: ServiceAccount/ConfigMap/Deployment/Service) and a `02_helm_chart/` (a **mirror copy** of the application repo's Helm chart). **Neither is what ArgoCD actually deploys** — see below.

If asked to reimplement "the application K8s manifests," implement only #1 and #2 as genuinely belonging to this repo. The actual Helm charts (#3's intended subject) live and are maintained in a **separate GitHub repository** (`dercioanselmo/GleamGoods`, `src/<service>/chart`) — that's what `02_argocd-helm-manifests/` points ArgoCD at directly. Don't treat `01_microservices/*/02_helm_chart/` as something to keep in sync; if reimplementing cleanly, it's a strong candidate for deletion (confirm with the repo owner first, per the same caution as `10_Secret_provider_class`).

### Concrete evidence these mirror copies are already stale, not just theoretically at risk of drifting

The mirrored charts here (`01_microservices/01_catalog/02_helm_chart/templates/deployment.yaml`, etc.) use a plain Kubernetes `Deployment`. **The live application repo converted every microservice (catalog, orders, ui, cart, checkout) from `Deployment` to Argo `Rollout` months ago** (canary strategy, `argoproj.io/Rollout` — see `SECRETS.md` and this project's other context files for how central that conversion is to the whole zero-downtime design). These mirror copies were never updated to reflect that change. This is exactly the kind of drift that happens when a "reference copy" folder exists alongside the real source — another argument for not maintaining it going forward.

## What's actually live: `02_argocd-helm-manifests/`

5 ArgoCD `Application` resources, one per microservice, all following the identical pattern:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: <service>
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/dercioanselmo/GleamGoods.git
    targetRevision: main
    path: src/<service>/chart
    helm:
      valueFiles:
        - values-<service>.yaml
  destination:
    server: https://kubernetes.default.svc
    namespace: default
  syncPolicy:
    automated:
      prune: true      # auto-delete resources removed from Git
      selfHeal: true    # auto-revert manual/out-of-band cluster changes
    syncOptions:
      - CreateNamespace=true
```

Key points if reimplementing:
- `repoURL` points at the **separate application repo**, not this one — this Terraform/DevOps repo has no direct connection to what actually gets deployed beyond these 5 pointer objects.
- `targetRevision: main` — deploys whatever is on the app repo's `main` branch; no per-environment branch/tag strategy currently.
- `selfHeal: true` means any manual `kubectl edit`/`kubectl patch` against a live resource gets silently reverted by ArgoCD on its next reconcile — a deliberate GitOps-purity choice, but worth knowing before debugging "why did my manual fix disappear."
- All 5 deploy into the same `default` namespace — no per-service namespace isolation in this project.
- ArgoCD needs the app repo registered as a Git source with credentials before any of these can sync (private repo) — that step lives in `07_ArgoCD_Install`'s context, not here.

## What's actually live: `03_Verification_Pods/`

A documented (`Verification-Pods.md`) set of 5 throwaway diagnostic pods, one per AWS-managed dependency, used to manually confirm a microservice can actually reach and use its AWS backend after any infrastructure change. Pattern, consistent across all 5:

- **Reuse the real microservice's own `ServiceAccountName`** (e.g. `serviceAccountName: catalog`) — this is what makes the diagnostic pod authenticate via the exact same Pod Identity role the real application uses, so a successful connection genuinely proves the production auth path works, not just that credentials exist somewhere.
- Pull connection details (host, db name, queue name) from the **same ConfigMap/Secret the real deployment uses** (`configMapKeyRef`/`secretKeyRef` against the live `catalog`/`catalog-db` objects) — never hardcode credentials into the diagnostic pod.
- A generic client image for the target (`mysql:8.0`, `postgres` client, `redis-cli`-capable image, `amazon/aws-cli`) with `command: sleep infinity` (or similar) so it stays up for interactive `kubectl exec`, `restartPolicy: Never`.
- Documented, copy-pasteable verification commands per service in `Verification-Pods.md` (connect, list tables/keys/queues, run a real query, exit) plus an explicit cleanup step (`kubectl delete -f <pod-file>`) — these are meant to be applied, used, and torn down, not left running.

If reimplementing this pattern for a new AWS-backed dependency in the future, follow this same shape: reuse the real service account, pull config from the real ConfigMap/Secret, document the exact verification commands rather than assuming they're obvious.

## Repo-wide conventions

- Numbered folders/files reflecting build order (`01_microservices` was the earliest phase per the project's own README history — raw manifests, then Helm, then ArgoCD wiring — followed by `02_argocd-helm-manifests`, then `03_Verification_Pods` added later for operational testing).

## CI/CD

None for this folder — everything here is either informational/historical (`01_microservices`) or applied manually once (`02_argocd-helm-manifests`, a one-time bootstrap of the ArgoCD `Application` objects — after which ArgoCD itself takes over continuous sync from the app repo) or applied/deleted ad hoc as needed (`03_Verification_Pods`).

## Explicitly out of scope

- The actual Helm chart templates/values — maintained in the separate `dercioanselmo/GleamGoods` repo, not here. Don't treat this repo as the place to make application-chart changes.
- Anything implying `01_microservices/*/02_helm_chart/` should be kept updated — explicitly not the goal; it's stale reference material at best.
