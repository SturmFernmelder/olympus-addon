# Olympus Link on Google Cloud

This is the production-shaped Google Cloud adapter for the existing Olympus Link core. It uses:

- **Cloud Run** for the HTTPS routes and Discord interaction;
- **Firestore** as the durable append-only journal;
- the container's in-memory SQLite only as a replayable cache for the already reviewed D1/SQLite core;
- **Secret Manager** values injected by Cloud Run, never credentials in this repository.

It needs no VPS and no Cloudflare service. It is intentionally **off** until the real endpoint,
Discord application, public key and secrets are configured. Do not put secret values in
`service.template.yaml`, `web/public/config.js` or `Olympus/Link.lua`.

## Why one Cloud Run instance

`link-core.mjs` already has the transaction and replay rules the Link tests exercise. The adapter
appends each accepted SQL mutation to Firestore before committing it to the local SQLite cache, and
replays the journal on every cold start. The deploy template therefore fixes **max instances = 1**
and **container concurrency = 1**. Raising either without replacing the journal adapter with a
multi-writer native Firestore repository is unsupported and fails the architecture review.

## Prepare a project

1. Select a Google Cloud project with billing enabled and enable Cloud Run, Cloud Build, Artifact
   Registry, Firestore and Secret Manager.
2. Create a Firestore database in Native mode in the same region as Cloud Run.
3. Create a dedicated `olympus-link` service account. Grant only Firestore user and access to the
   four secrets named in `service.template.yaml`.
4. Generate the backend Ed25519 key offline with `python3 scripts/link-keys.py backend`. Keep the
   seed in `olympus-link-backend-seed`; put only its public hex in the service template and, after
   live verification, `ns.LINK_BACKEND_KEYS` in `Olympus/Link.lua`.
5. Generate at least 32 random bytes for `olympus-link-identity-secret`. It makes a stable opaque
   person id for consented identity snapshots; changing it invalidates continuity, so rotate it
   only as a migration.
6. Add the Discord bot token and a separate random admin token of at least 32 bytes to Secret
   Manager. Set the non-secret Discord ids and public key in a private copy of the template.

## Build and deploy

From the repository root, after replacing only the placeholders in a private copy:

```sh
gcloud builds submit --tag REGION-docker.pkg.dev/PROJECT_ID/olympus/olympus-link:TAG -f web/gcp/Dockerfile .
gcloud run services replace /path/to/private-service.yaml --region REGION
```

Then:

1. Set Discord's interactions endpoint to `/api/discord/interactions` and register `/verify`.
2. Put Cloud Run's `/api/link/proof` URL and the Discord client id in `web/public/config.js`; add
   the exact Cloud Run origin to the page CSP `connect-src`.
3. Exercise `/healthz`, a test Discord account, one code, one in-game proof, role grant, explicit
   identity publication/import, removal, and key revocation before enabling the addon key.
4. Call `POST /internal/prune` daily from Cloud Scheduler with the admin bearer token.

The service account uses Application Default Credentials for Firestore. Secret Manager injects
the four secret environment variables at container start; the application never downloads or
logs them. The reference Cloudflare Worker remains under `web/worker/` as tested documentation,
but Google Cloud is the intended deployment for 1.2.4.

