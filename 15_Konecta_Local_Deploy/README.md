# Konecta - local, zero-cost deployment

Runs the whole Konecta stack (frontend + 6 backend services + Mailpit) on your
machine via `docker-compose`, exposed to the internet with a free Cloudflare
Tunnel on the same domain already registered for Google OAuth
(`konecta.dercioanselmo.com`) - no re-registration needed.

Postgres is NOT part of this compose file - it runs natively on your machine
already, with the `konecta-*` databases and their data already there. Every
backend service reaches it via `host.docker.internal` (trust auth, user
`apple`, no password) instead of a containerized DB.

This exists because the AWS account behind `../14_Konecta` is suspended. That
Terraform is untouched and still there for when you're ready to go back to a
paid AWS account for production - this is a separate, parallel deployment
path, not a replacement of it.

Repo layout assumption: this directory lives in `GleamGoods-DevOps`, a
sibling of the konecta source repos - `docker-compose.yml`'s build paths
expect `../../../konecta/konecta-frontend` and
`../../../konecta/backend/<service>` to exist. Adjust them if your clones
are laid out differently.

Product photo / shop logo uploads use S3 in the AWS deployment - here, the
app is being changed to store those files on local disk instead
(`MEDIA_STORAGE_PATH` in `docker-compose.yml` is a placeholder for whatever
env var that code ends up using).

## One-time setup

### 1. Point your domain at Cloudflare (free, no card)

1. Sign up at https://dash.cloudflare.com (free plan).
2. Add site `dercioanselmo.com`. Cloudflare scans existing DNS records and
   shows you the nameservers to use.
3. In GoDaddy, replace the domain's nameservers with the two Cloudflare
   gives you. This moves ALL DNS for the domain to Cloudflare - if you had
   other records on Route53 you still care about, recreate them in
   Cloudflare's dashboard first. (`argocd.dercioanselmo.com` /
   `gleamgoods.dercioanselmo.com` don't matter right now since that
   infrastructure is down anyway.)
4. Wait for propagation (Cloudflare's dashboard shows when the domain is
   "active" - usually well under an hour).

### 2. Install and authenticate cloudflared

```bash
brew install cloudflared
cloudflared tunnel login
```

This opens a browser to authorize `cloudflared` against your Cloudflare
account/domain and saves a cert to `cloudflared/cert.pem` (gitignored).

### 3. Create the tunnel and route the two hostnames

```bash
cd cloudflared
cloudflared tunnel create konecta-local
```

This prints a `<TUNNEL_ID>` and writes `<TUNNEL_ID>.json` in this directory
(gitignored - it's a credential). Edit `config.yml` and replace
`<TUNNEL_ID>.json` in `credentials-file:` with the real filename.

```bash
cloudflared tunnel route dns konecta-local konecta.dercioanselmo.com
cloudflared tunnel route dns konecta-local mailpit.dercioanselmo.com
```

### 4. Fill in secrets

```bash
cd ..
cp .env.example .env
```

Edit `.env`:
- `JWT_SECRET`, `MAILPIT_UI_AUTH` - already generated for you in the real
  `.env` (if you're reading this after that step ran, it's already there -
  don't regenerate unless you want to invalidate existing sessions/data).
- `GOOGLE_CLIENT_ID` / `GOOGLE_CLIENT_SECRET` - the existing registered
  Google OAuth app, reused since the domain doesn't change.

## Running it

Two things need to be running at the same time, in two terminals:

```bash
# Terminal 1 - the app stack
docker compose up --build

# Terminal 2 - the tunnel
cloudflared tunnel --config cloudflared/config.yml run
```

Then visit https://konecta.dercioanselmo.com

Mailpit (captured emails, e.g. OTP codes) is at https://mailpit.dercioanselmo.com
- login is whatever you set in `MAILPIT_UI_AUTH`.

## Stopping / restarting

```bash
docker compose down        # stop everything - Postgres is untouched, it's not part of this compose file
docker compose down -v     # same, plus wipes the media-data volume (uploaded files, once local storage lands)
```

Both the app stack and the tunnel only run while your machine is on and these
two commands are active - this is a demo setup, not a production one.

## pgAdmin / direct DB access

Nothing to forward - Postgres already runs on your machine. Connect pgAdmin
to `localhost:5432`, user `apple`, no password, one of: `konecta-security`,
`konecta-store-stock`, `konecta-cart`, `konecta-checkout` (also used by
orders), `konecta-courier`.
