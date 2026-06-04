# Kanban Docker and Portainer Rollout

Use this runbook to deploy the Kanban fork into the existing Docker Swarm-style Portainer stack without replacing PostgreSQL, Redis, volumes, networks, or Traefik routing.

Target stack services:

- `chatwoot_app`
- `chatwoot_sidekiq`
- `chatwoot_redis`

External dependencies:

- PostgreSQL service host: `pgvector`
- Docker network: `SobralNet`

Do not deploy from `latest`. Always deploy an immutable image tag.

## Image Build and Publish

Build the production image from `docker/Dockerfile`. This Dockerfile compiles production frontend assets during the image build when `RAILS_ENV=production`, so the Kanban UI should be embedded in the image.

Use GHCR for the custom image registry.

Tag format:

```text
kanban-YYYYMMDD-<short_sha>
```

Example:

```text
ghcr.io/<org-or-user>/chatwoot-kanban:kanban-20260604-a1b2c3d
```

Login to GHCR:

```sh
docker login ghcr.io -u <github-user>
```

Build and push for a linux/amd64 VPS:

```sh
docker buildx build \
  --platform linux/amd64 \
  -f docker/Dockerfile \
  --build-arg RAILS_ENV=production \
  --build-arg BUNDLE_WITHOUT=development:test \
  -t ghcr.io/<org-or-user>/chatwoot-kanban:kanban-YYYYMMDD-<short_sha> \
  --push \
  .
```

If the image was built locally without `--push`, push it explicitly:

```sh
docker push ghcr.io/<org-or-user>/chatwoot-kanban:kanban-YYYYMMDD-<short_sha>
```

Never update Portainer to `latest`, `main`, or any mutable tag.

## Services to Update

Change the image tag to the same immutable custom image in:

- `chatwoot_app`
- `chatwoot_sidekiq`

Use exactly the same custom image tag for both services so web code, jobs, migrations, and compiled UI assets stay in sync.

Keep unchanged:

- `chatwoot_redis`
- `pgvector` / PostgreSQL service
- Redis volumes
- PostgreSQL volumes
- `SobralNet`
- `chatwoot_storage:/app/storage`
- Traefik labels

Do not add a production `vite` service. Production frontend assets are compiled into the image.

## Public Assets Volume Audit

The current stack mounts:

```yaml
chatwoot_public:/app/public
```

This can override `/app/public` from the custom image and may hide the compiled frontend assets that include the Kanban UI.

Before rollout:

- Inspect the `chatwoot_public` volume contents.
- Back up the `chatwoot_public` volume before changing anything.
- Confirm whether it contains only deliberate custom public files, such as logos, or whether it contains application assets copied from an older image.

Choose one safe strategy after inspection:

- Strategy A: remove the `/app/public` mount if it is unnecessary and the deployment can rely on assets embedded in the image.
- Strategy B: synchronize compiled assets from the custom image into the `chatwoot_public` volume before starting the updated app service.

Do not silently delete the volume. Preserve it until the operator has confirmed what it contains and has a verified backup.

After deployment, validate the Kanban UI in the browser. If the page loads old JavaScript or Kanban routes/components are missing, treat the `/app/public` mount as the first suspect.

The mailer mounts also override files from the image:

```yaml
chatwoot_mailer:/app/app/views/devise/mailer
chatwoot_mailers:/app/app/views/mailers
```

Preserve these mounts only deliberately. If this fork changes mailer templates later, these volumes may mask those changes too.

## Temporary Migration Service

Run migrations and Kanban backfill from a temporary one-off Portainer service using the same custom image tag as the rollout.

Temporary service requirements:

- Image: `ghcr.io/<org-or-user>/chatwoot-kanban:kanban-YYYYMMDD-<short_sha>`
- Environment: same variables as `chatwoot_app`
- Network: `SobralNet`
- Volume: `chatwoot_storage:/app/storage`
- Replicas: `1`
- Restart policy: disabled / do not restart after completion

Use placeholders for sensitive environment values in documentation and examples:

```text
SECRET_KEY_BASE=<SECRET_KEY_BASE>
POSTGRES_PASSWORD=<POSTGRES_PASSWORD>
SMTP_PASSWORD=<SMTP_PASSWORD>
GOOGLE_OAUTH_CLIENT_SECRET=<GOOGLE_OAUTH_CLIENT_SECRET>
```

Run commands in this order from the temporary service/container:

```sh
bundle exec rails db:chatwoot_prepare
DRY_RUN=true bundle exec rake kanban_cards:backfill
bundle exec rake kanban_cards:backfill
bundle exec rake kanban_cards:audit_parity
```

Review the dry-run, backfill, and parity output before updating long-running services. Remove the temporary migration service after the commands finish and the output is captured.

## Safe Rollout Order

1. Record the current image tags for `chatwoot_app` and `chatwoot_sidekiq`.
2. Take and verify a PostgreSQL backup before schema changes.
3. Run the preflight SQL from `docs/kanban-production-preflight.md` against the production database.
4. Resolve unexpected preflight rows manually before continuing.
5. Pull or verify availability of the custom image tag on the Swarm node.
6. Stop the old `chatwoot_sidekiq` service first so old workers cannot process new or migrated Kanban jobs.
7. Enable the maintenance window for `chatwoot_app`.
8. Run the temporary migration service using the custom image tag.
9. Review `kanban_cards:backfill` and `kanban_cards:audit_parity` output.
10. Update `chatwoot_app` to the custom immutable image tag.
11. Update `chatwoot_sidekiq` to the same custom immutable image tag.
12. Validate Sidekiq queues, retries, dead set, and logs.
13. Run browser smoke tests from `docs/kanban-production-preflight.md`.

Sidekiq is required for automatic Kanban card creation from `conversation.created`, because the listener enqueues `KanbanCards::AutoCreateFromConversationJob`.

## Rollback

1. Stop `chatwoot_sidekiq` first.
2. Restore the previous immutable image tag on `chatwoot_app`.
3. Restore the previous immutable image tag on `chatwoot_sidekiq`.
4. If rollback happens after live Kanban writes, restore the PostgreSQL backup or run an explicit reverse-reconciliation procedure.
5. Start `chatwoot_app`.
6. Start `chatwoot_sidekiq`.
7. Validate logs, queues, core Chatwoot flows, and Kanban-related data visibility.

Redeploying the old image alone may expose stale legacy Kanban ordering/data after live Kanban writes because dual-write to legacy state was removed.

Keep these legacy artifacts during the rollback window:

- `conversation_kanban_states` table
- legacy model
- sync service
- retained switch column
- `kanban_cards` rake tasks

Do not drop legacy database artifacts until the rollback window closes.

## Security

Use placeholders only in documentation, tickets, screenshots, and shared snippets:

```text
<SECRET_KEY_BASE>
<POSTGRES_PASSWORD>
<SMTP_PASSWORD>
<GOOGLE_OAUTH_CLIENT_SECRET>
```

Rotate any credential exposed outside the VPS, including credentials pasted into chat, issue trackers, logs, screenshots, shell history, or public/private documentation.

## Remaining Risks

- `chatwoot_public:/app/public` can mask compiled Kanban frontend assets from the image.
- Updating only `chatwoot_app` or only `chatwoot_sidekiq` creates a web/worker version mismatch.
- Running old Sidekiq workers during migration can process jobs with stale code.
- Rollback after live Kanban writes may require database restore, not only image rollback.
- Extra app services not listed in this runbook must be updated if they run Rails, rake, or Sidekiq from the Chatwoot image.
- Mailer mounts may mask future mailer template changes from the custom image.
