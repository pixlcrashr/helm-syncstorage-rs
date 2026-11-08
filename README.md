# helm-syncstorage-rs

A Helm chart for [syncstorage-rs](https://github.com/mozilla-services/syncstorage-rs), the Rust implementation of the Mozilla Sync storage server, for self-hosting Firefox Sync.

The chart deploys the syncstorage-rs server (syncstorage + tokenserver combined) and optionally bundles a PostgreSQL or MySQL database from the [Bitnami charts](https://github.com/bitnami/charts). Alternatively, point it at any external database via connection URLs - no database dependency is required then.

## Quickstart

Requirements: Helm 3.8+ and Kubernetes 1.19+.

```console
git clone https://github.com/pixlcrashr/helm-syncstorage-rs
cd helm-syncstorage-rs
helm dependency update   # downloads the bitnami postgresql/mysql charts
```

Instead of the `--set` flags below you can also use the bundled example values file: copy [values.example.yaml](values.example.yaml), pick exactly one database mode inside, replace the `change-me` secrets, and run `helm install syncstorage-rs . -f values.example.yaml` (it ships with the bundled PostgreSQL enabled).

Then install with **one** of the database options below.

### Option A: bundled PostgreSQL (simplest)

```console
helm install syncstorage-rs . \
  --set masterSecret=change-me \
  --set postgresql.enabled=true \
  --set postgresql.auth.password=change-me
```

Syncstorage and tokenserver share one PostgreSQL database.

### Option B: bundled MySQL

```console
helm install syncstorage-rs . \
  --set masterSecret=change-me \
  --set mysql.enabled=true \
  --set mysql.auth.rootPassword=change-me \
  --set mysql.auth.password=change-me
```

MySQL uses separate databases for syncstorage and tokenserver; the chart creates the extra `tokenserver` database automatically.

### Option C: external database (no bundled dependencies)

```console
helm install syncstorage-rs . \
  --set masterSecret=change-me \
  --set database.type=postgres \
  --set database.syncstorageDatabaseUrl='postgres://sync:secret@my-postgres.my-namespace.svc.cluster.local:5432/syncstorage'
```

When `database.tokenserverDatabaseUrl` is omitted, tokenserver uses the same database as syncstorage (recommended for PostgreSQL; for MySQL pass a separate URL, e.g. `...@my-mysql...:3306/tokenserver`). Set `database.type=mysql` accordingly, or provide both URLs from an existing secret via `database.existingSecret`.

### Try it locally

```console
kubectl port-forward deployment/syncstorage-rs 8080:8000
curl http://127.0.0.1:8080/__heartbeat__   # -> {"status":"ok",...}
```

For a local end-to-end test, the storage node URL handed to clients must be
reachable from your machine, so install with
`--set tokenserver.initNodeUrl=http://127.0.0.1:8080` added to any option above.

### Connect Firefox

Set `identity.sync.tokenserver.uri` in `about:config` to
`https://<your-server>/1.0/sync/1.5` and restart the browser. For Firefox on
Android, see the [upstream how-to](https://mozilla-services.github.io/syncstorage-rs/how-to/how-to-run-with-docker.html#connect-firefox).

That URL is the storage node URL registered with tokenserver
(`tokenserver.initNodeUrl`). It defaults to the first ingress host when
`ingress.enabled=true` (use HTTPS/TLS for anything beyond local testing), and
to the in-cluster service URL otherwise - so when syncing from outside the
cluster, either enable an ingress or set `tokenserver.initNodeUrl` to a
publicly reachable address.

### Upgrade and uninstall

```console
helm upgrade syncstorage-rs . --reuse-values        # plus any changed --set flags
helm uninstall syncstorage-rs                       # bundled database PVCs are kept
```

## Configuration

A ready-made, fully commented example values file is provided in [values.example.yaml](values.example.yaml) - it covers all database modes, ingress, resources, and extra environment variables.

| Key | Default | Description |
| --- | --- | --- |
| `replicaCount` | `1` | Number of server replicas |
| `image.repository` | `""` | Override the image; defaults to the `syncserver-postgres`/`syncserver-mysql` variant on ghcr.io |
| `image.tag` | `.Chart.appVersion` | Image tag |
| `masterSecret` | `""` | `SYNC_MASTER_SECRET`; or use `masterSecretExistingSecret` (+ `...Key`) |
| `database.type` | `postgres` | `postgres` or `mysql`; follows the bundled database when one is enabled |
| `database.*DatabaseUrl` | `""` | Full connection URLs (external database mode) |
| `database.existingSecret` | `""` | Secret with connection URLs (existing-secret mode) |
| `tokenserver.enabled` | `true` | `SYNC_TOKENSERVER__ENABLED` |
| `tokenserver.runMigrations` | `true` | `SYNC_TOKENSERVER__RUN_MIGRATIONS` |
| `tokenserver.initNodeUrl` | `""` | Storage node URL advertised to clients; defaults to the ingress URL, else the in-cluster service URL |
| `config.host` / `config.port` | `0.0.0.0` / `8000` | `SYNC_HOST` / `SYNC_PORT` |
| `extraEnv` | `[]` | Additional environment variables (e.g. `RUST_LOG`, `SENTRY_DSN`) |
| `service.port` | `8000` | Service port |
| `ingress.enabled` | `false` | Ingress for the server (tokenserver is served from the same host under `/1.0/sync/1.5`) |
| `resources`, `nodeSelector`, `tolerations`, `affinity`, `volumes`, `volumeMounts` | `{}`/`[]` | Standard deployment tuning |

For the full list of bundled database options, see the [bitnami/postgresql](https://github.com/bitnami/charts/tree/main/bitnami/postgresql) and [bitnami/mysql](https://github.com/bitnami/charts/tree/main/bitnami/mysql) charts.

## Database configuration details

The server connects to two logical databases: one for syncstorage and one for tokenserver. Configure them in one of three ways (checked in this order of precedence):

| Mode | Values | Notes |
| --- | --- | --- |
| External URLs | `database.syncstorageDatabaseUrl`, `database.tokenserverDatabaseUrl` | No bundled database. For PostgreSQL both may point at the same database; for MySQL use separate databases. |
| Existing secret | `database.existingSecret` (+ `existingSecretSyncstorageKey` / `existingSecretTokenserverKey`) | Secret must contain the full connection URLs. The chart then manages no database secret itself. |
| Bundled database | `postgresql.enabled=true` or `mysql.enabled=true` | Bitnami subcharts; URLs are composed automatically from the subchart's `auth.*` values (which is why `auth.password` must be set). |

Enable at most one bundled database. When one is enabled, `database.type` (postgres/mysql) follows it automatically; otherwise `database.type` selects the server image variant (`syncserver-postgres` / `syncserver-mysql`) and the composed URL scheme.

### Bundled PostgreSQL

```yaml
postgresql:
  enabled: true
  auth:
    username: syncstorage
    password: change-me
    database: syncstorage
```

Syncstorage and tokenserver share a single database, mirroring the upstream `docker-compose.one-shot.postgres.yaml` setup.

### Bundled MySQL

```yaml
mysql:
  enabled: true
  auth:
    rootPassword: change-me
    username: syncstorage
    password: change-me
    database: syncstorage
```

MySQL requires separate databases for syncstorage and tokenserver. The chart creates the additional `tokenserver` database (`mysql.tokenserverDatabase`) and grants it to the configured user via an init container that runs before the server starts. It uses the MySQL root credentials from the Bitnami chart's secret - this assumes the chart-created user allows connections from any host (`@'%'`), which is how the Bitnami chart creates it.

> Since the Bitnami catalog changes of August 2025, `docker.io/bitnami/mysql` no longer carries pullable tags; the chart defaults the database image to `bitnamilegacy/mysql:9.4.0-debian-12-r1`. Adjust `mysql.image.*` if you use Bitnami Secure Images or your own mirror.

## Health probes

- Readiness: `GET /__heartbeat__` (queries the syncstorage database)
- Liveness and startup: `GET /__lbheartbeat__` (no database query, but returns 500 when the connection pool is exhausted for a sustained period - the server's deadman switch); the startup probe allows up to three minutes for initial database migrations

Note that `/__heartbeat__` only covers the syncstorage database: the tokenserver has its own heartbeat handler, which upstream only exposes in tokenserver-only deployments. Other endpoints: `/__version__` (build info) and `/__error__` (test hook).
