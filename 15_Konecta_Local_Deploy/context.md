# Konecta deployment - context

Living doc. Edit this whenever something changes - it's meant to be pasted
into a fresh session so a new conversation can pick up without re-deriving
everything below.

## Why this exists

`../14_Konecta` (AWS/EKS/ArgoCD) is the real production path, but the AWS
account behind it is currently **suspended** and Azure's free trial expired.
While in that state, the whole stack runs locally via `docker-compose`
instead, exposed to the internet with a free Cloudflare Tunnel - on the
SAME domain (`konecta.dercioanselmo.com`) already registered as the Google
OAuth redirect URI, so nothing OAuth-related needed to change.

`../14_Konecta`'s Terraform/Helm/ArgoCD manifests are untouched and still
the plan for when a paid AWS account is available again. These two paths
are parallel, not one replacing the other.

Domain `dercioanselmo.com` is registered at **GoDaddy** (independent of
AWS) - its nameservers were switched to Cloudflare to make the tunnel work.

## Current status - local deploy (this directory)

- `docker-compose.yml`: frontend + 6 backend services + Mailpit. **No
  Postgres container** - it runs natively on the host machine already,
  with the `konecta-*` databases and real data already there (trust auth,
  user `apple`, no password). Every backend service reaches it via
  `host.docker.internal:5432`, database names use **hyphens**
  (`konecta-security`, `konecta-cart`, etc - confirmed against the actual
  local instance), NOT the underscore names used in the AWS RDS setup.
- `orders` shares `checkout`'s database (`konecta-checkout`) - an
  application-level decision (order-service reads/writes checkout's own
  schema directly), not an infra shortcut. Same in both AWS and local.
- S3 uploads (product photos, shop logos) are being replaced with
  local-disk storage in the app code itself. `MEDIA_STORAGE_PATH=/data/media`
  in `docker-compose.yml` (backed by a shared `media-data` volume across
  `store-stock`/`cart`/`checkout`/`orders`/`courier`) is a **placeholder** -
  swap it for whatever real env var the app ends up using once that lands.
- Cloudflare Tunnel: tunnel name `konecta-local`, tunnel ID
  `9d174e2f-97cc-41a7-999f-61fd2b3658a9`. Credentials file lives at
  `~/.cloudflared/<tunnel-id>.json` - **cloudflared always writes it next
  to the origin cert, ignoring cwd** at the time `tunnel create` was run,
  not into this project's `cloudflared/` folder. `config.yml`'s
  `credentials-file:` points at the absolute path for this reason.
- `config.yml` does path-based routing on `konecta.dercioanselmo.com`:
  `/oauth2/authorization/google` and `/login/oauth2/code/google` go to
  `security` (port 8091), everything else goes to `frontend` (port 3000) -
  mirrors the exact same routing decision made on the AWS ALB (see below).
  `mailpit.dercioanselmo.com` routes to Mailpit's UI (port 8025).
- Secrets live in `.env` (gitignored) - `JWT_SECRET`, `MAILPIT_UI_AUTH`
  (`admin:<password>`), `GOOGLE_CLIENT_ID`/`SECRET` (the same already-
  registered Google OAuth app, reused since the domain didn't change).
- Two things must run at once, in separate terminals: `docker compose up
  --build` and `cloudflared tunnel --config cloudflared/config.yml run`.
  Both only work while your machine is on - this is a demo setup, not
  production.

### Known working / fixed so far
- Killed a stray local `next dev` process that was squatting on port 3000
  and answering with dev-mode HMR websocket errors instead of the
  container.
- Recreated the Cloudflare tunnel once already (credentials-file path
  confusion) - if you ever delete/recreate the tunnel again, remember the
  DNS CNAME records from the OLD tunnel don't get cleaned up automatically
  and will conflict with `cloudflared tunnel route dns` for the new one;
  delete or repoint them manually in the Cloudflare dashboard first.

## Current status - AWS/EKS path (`../14_Konecta`)

Built but **repeatedly lost to `git reset --hard origin/main`** during this
work (happened 3+ times) - if you're resuming this path, check what's
actually committed vs what these notes claim exists, don't assume:

- Helm charts for frontend + all 6 backend services
  (`02_services_K8s_manifests/`), ArgoCD `Application` manifests for each
  (`04_argocd-helm-manifests/`), Mailpit chart (`08_mailpit`).
- DB auth uses the **shared master secret** (`konecta-db-secret`) across
  all 5 RDS databases - the per-service secrets drafted in
  `03_AWS_managed_databases/c9_*.tf` are NOT applied/populated yet
  (blocked on an unresolved rotation-Lambda design question - see that
  module's README).
- `orders` runs under the `checkout` ServiceAccount (reuses its Pod
  Identity binding) rather than getting its own, since it shares
  checkout's DB/secret.
- `security-service` has a narrow Ingress on the shared ALB (`group.name:
  gleamgoods`, `group.order: "10"`) for exactly `/oauth2/authorization/google`
  and `/login/oauth2/code/google` - the frontend's catch-all Ingress uses
  `group.order: "100"` so it doesn't shadow those two paths. This is the
  same routing trick replicated in the local Cloudflare Tunnel config.
- Fixed bugs worth knowing about if they resurface:
  - `Deployment.spec.selector` is immutable - changing `nameOverride`
    (which changes `app.kubernetes.io/name`) on an already-deployed chart
    requires deleting the Deployment so ArgoCD recreates it; it can't
    patch in place.
  - All 6 backend services need a `startupProbe` (not just
    `initialDelaySeconds` on liveness/readiness) - cold Spring Boot start
    was observed taking 70+ seconds, longer than a fixed delay tolerates.
  - Health probes must hit `/actuator/health/readiness` and
    `/actuator/health/liveness`, not bare `/actuator/health` - Spring Boot
    auto-enables those two subpaths when it detects it's running in
    Kubernetes.
  - Mailpit's `/` requires basic auth once `MP_UI_AUTH` is set - probes
    (and the ALB health check) must use `/readyz`/`/livez` instead, which
    are unauthenticated by design.
- The Next.js OAuth-redirect bug (see below) applies identically here -
  same fix, same files, in the `konecta-frontend` repo.

## App-code bugs fixed (in `konecta-frontend`, not infra)

`app/api/auth/google/start/route.ts` and `app/auth/callback/route.ts` used
to build absolute redirect URLs from the incoming request
(`new URL(path, request.url)` / `url.origin`). Next.js's standalone server
falls back to its own bind address (`HOSTNAME`/`PORT` from the Dockerfile -
`0.0.0.0:3000`) when it can't confidently resolve a public host from the
request (neither the AWS ALB nor Cloudflare Tunnel guarantee
`X-Forwarded-Host`), so users got redirected to `https://0.0.0.0:3000/...`
mid-OAuth-flow. Fixed by building all such redirects from
`process.env.NEXT_PUBLIC_APP_URL` explicitly instead of the request.

## Where things are, quick reference

- Local deploy: `GleamGoods-DevOps/15_Konecta_Local_Deploy/` (this dir)
- AWS/EKS path: `GleamGoods-DevOps/14_Konecta/`
- Frontend source: `konecta/konecta-frontend/`
- Backend sources: `konecta/backend/konecta-<service>-service/`
- Domain DNS: Cloudflare (nameservers moved from GoDaddy's default)
- Mailpit UI: https://mailpit.dercioanselmo.com (creds in `.env`)
- App: https://konecta.dercioanselmo.com

## Open items

- [ ] Get the real `MEDIA_STORAGE_PATH`-equivalent env var name(s) once the
      app's local-disk storage code exists, and update `docker-compose.yml`
      (and eventually the AWS Helm charts, if that path is revived before
      S3 access comes back).
- [ ] AWS account still suspended - S3 uploads non-functional either way
      until it's reinstated or the app fully moves off S3.
- [ ] Per-service DB secrets (`14_Konecta/03_AWS_managed_databases/c9_*`)
      still blocked on the rotation-Lambda design question if/when the AWS
      path resumes.
