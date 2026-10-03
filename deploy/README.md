# VPS demo preparation

This is a single-VPS **portfolio/demo** layout, not a production payment deployment. It serves three HTTPS hosts:

| Host | Purpose |
| --- | --- |
| `PORTFOLIO_DOMAIN` | Static backend-intern portfolio |
| `APP_DOMAIN` | Next.js app and same-origin `/api/v1/*` backend routes |
| `MEDIA_DOMAIN` | Signed MinIO object downloads; only GET/HEAD are proxied |

Only Caddy publishes ports 80/443. PostgreSQL, Redis, RabbitMQ, MinIO, the Java API and Next.js have no host port mapping. The default `Caddyfile.portfolio` serves only the portfolio; switch to `Caddyfile` after the app demo passes its checks. Next.js compiles `NEXT_PUBLIC_API_BASE_URL` into its browser bundle, so rebuild `frontend` whenever `APP_DOMAIN` changes. The API uses a separate public MinIO endpoint when signing browser URLs; keep `APP_MINIO_ENDPOINT` on the internal Docker network.

## Prerequisites

- Clone `smartevent-backend`, `smartevent-web` and `smartevent-infra` as sibling directories. Copy the prepared `smartevent-portfolio` folder alongside them; it does not have a remote repository yet.
- Point all three DNS names at the VPS. Allow inbound TCP 80 and 443. Install Docker Engine and Compose.
- Reserve enough RAM and disk for Java, Next.js, PostgreSQL, Redis, RabbitMQ, MinIO and Docker image builds; measure on the chosen VPS before committing to a size. Keep free space for database and object-storage backups.
- Use sandbox payment credentials only. Never use real payment data on this demo stack.

## Private bring-up

From `smartevent-infra/deploy` on the VPS:

```sh
cp .env.example .env
chmod 600 .env
# Edit every domain and secret in .env; remove all replace_with_* values.
docker compose --env-file .env -f compose.demo.yml config --quiet
docker compose --env-file .env -f compose.demo.yml up -d --build postgres redis rabbitmq minio backend frontend
docker compose --env-file .env -f compose.demo.yml ps
```

You may publish the static portfolio first, with `CADDYFILE=Caddyfile.portfolio` in `.env`:

```sh
docker compose --env-file .env -f compose.demo.yml --profile public up -d caddy
```

At this stage, only `PORTFOLIO_DOMAIN` is served. The app and media hosts are not configured in Caddy yet.

Wait for the backend to finish Flyway migration. Confirm it has started without errors before proceeding. The `caddy` service is in the `public` profile and stays off during this step.

The repository's V12 migration creates three well-known logins, including an admin. **Lock them before any public traffic reaches the app:**

```sh
docker compose --env-file .env -f compose.demo.yml exec -T postgres \
  sh -c 'psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB"' \
  < lock-seed-users.sql
```

Require the `Locked all 3 seeded users` notice. If the SQL exits with an error, keep Caddy stopped and investigate. Create separate, unique demo identities only after deciding which roles and actions visitors may use. Never re-enable the original seeded passwords.

## Before enabling the app host

1. Verify service health, backend startup and Flyway completion through the private Docker network. Public media URLs and VNPay callbacks need the app/media proxy to be available; test those after enabling HTTPS below.
2. Complete the seeded-account lock step above. Prepare unique identities for owner-controlled testing and the roles needed for the demo.
3. Publish approved terms/privacy pages before inviting public registration.
4. Add a backup job for PostgreSQL and MinIO, keep copies off the VPS, and test a restore. Choose how to monitor uptime, disk space and failed containers.

To expose the tested app, set `CADDYFILE=Caddyfile` in `.env`, then recreate the public proxy:

```sh
docker compose --env-file .env -f compose.demo.yml --profile public up -d --force-recreate caddy
```

Caddy obtains HTTPS certificates for the three DNS names. Verify `https://PORTFOLIO_DOMAIN`, `https://APP_DOMAIN` and an actual signed media URL in a browser. The signed media URL must use `https://MEDIA_DOMAIN`, not `http://minio:9000` or `localhost`.

## Validate the public demo before sharing

1. Upload actual event banners through the app. The seeded SQL rows contain sample metadata but do not place corresponding objects in MinIO. The public signing client can request the bucket region through `MEDIA_DOMAIN`, so that proxy must be working before testing signed media URLs.
2. Test event discovery, registration/login with a unique test identity, seat hold, VNPay sandbox callback, QR and check-in. Confirm the paid order and seat state in the database. Unit and integration tests do not replace this check.
3. Check the portfolio's GitHub links in a signed-out browser. Add a short recording once the complete demo flow is verified, then share the demo with recruiters.

`APP_MAIL_ENABLED=false` in this demo composition: email delivery is intentionally unavailable until SMTP is configured and checked. Do not present email delivery as a live demo feature before that work is done. Set VNPay sandbox credentials and confirm the public IPN URL before demonstrating payment.

## Updating

Build the affected application service and restart it. Rebuild `frontend` when the public app domain changes. Keep `caddy-data` across restarts so certificates persist. Never use `docker compose down -v` on a VPS with data to retain.
