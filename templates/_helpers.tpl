{{/*
Expand the name of the chart.
*/}}
{{- define "syncstorage-rs.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "syncstorage-rs.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "syncstorage-rs.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "syncstorage-rs.labels" -}}
helm.sh/chart: {{ include "syncstorage-rs.chart" . }}
{{ include "syncstorage-rs.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "syncstorage-rs.selectorLabels" -}}
app.kubernetes.io/name: {{ include "syncstorage-rs.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "syncstorage-rs.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "syncstorage-rs.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Validate chart configuration. Included by templates that render the server.
*/}}
{{- define "syncstorage-rs.checks" -}}
{{- if and .Values.postgresql.enabled .Values.mysql.enabled -}}
{{- fail "Enable at most one bundled database (postgresql.enabled / mysql.enabled)" -}}
{{- end -}}
{{- if and .Values.masterSecret .Values.masterSecretExistingSecret -}}
{{- fail "Set either masterSecret or masterSecretExistingSecret, not both" -}}
{{- end -}}
{{- if and (empty .Values.masterSecret) (empty .Values.masterSecretExistingSecret) -}}
{{- fail "Set masterSecret (or masterSecretExistingSecret): syncstorage-rs requires SYNC_MASTER_SECRET" -}}
{{- end -}}
{{- end -}}

{{/*
The database engine ("postgres" or "mysql"). It follows the bundled
database subchart when one is enabled, otherwise the database.type value.
*/}}
{{- define "syncstorage-rs.databaseType" -}}
{{- if .Values.mysql.enabled -}}
mysql
{{- else if .Values.postgresql.enabled -}}
postgres
{{- else -}}
{{- $type := lower (toString .Values.database.type) -}}
{{- if not (or (eq $type "postgres") (eq $type "mysql")) -}}
{{- fail (printf "database.type must be \"postgres\" or \"mysql\" (got %q)" $type) -}}
{{- end -}}
{{- $type -}}
{{- end -}}
{{- end -}}

{{/*
The server image. The variant follows database.type unless image.repository
is overridden.
*/}}
{{- define "syncstorage-rs.image" -}}
{{- $repository := default (printf "ghcr.io/mozilla-services/syncstorage-rs/syncserver-%s" (include "syncstorage-rs.databaseType" .)) .Values.image.repository -}}
{{- printf "%s:%s" $repository (default .Chart.AppVersion .Values.image.tag) -}}
{{- end -}}

{{/*
Hostname of the bundled PostgreSQL (matches the bitnami/postgresql naming
scheme). database.host overrides it for all database URLs.
*/}}
{{- define "syncstorage-rs.postgresql.host" -}}
{{- if .Values.database.host -}}
{{- .Values.database.host -}}
{{- else if .Values.postgresql.fullnameOverride -}}
{{- .Values.postgresql.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-postgresql" .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{/*
Hostname of the bundled MySQL (matches the bitnami/mysql naming scheme).
database.host overrides it for all database URLs.
*/}}
{{- define "syncstorage-rs.mysql.host" -}}
{{- if .Values.database.host -}}
{{- .Values.database.host -}}
{{- else if .Values.mysql.fullnameOverride -}}
{{- .Values.mysql.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-mysql" .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{/*
Compose the syncstorage and tokenserver database connection URLs.

Priority: database.*DatabaseUrl values > bundled postgresql/mysql subchart >
tokenserver shares the syncstorage database (the official Postgres setup
shares one database; MySQL URLs get a separate database name).

Emits the two entries (base64-encoded) for the chart-managed secret, which
the deployment references via secretKeyRef.
*/}}
{{- define "syncstorage-rs.databaseUrls" -}}
{{- $storageUrl := .Values.database.syncstorageDatabaseUrl -}}
{{- $tokenserverUrl := .Values.database.tokenserverDatabaseUrl -}}
{{- if and (not $storageUrl) .Values.postgresql.enabled -}}
{{- if .Values.postgresql.auth.existingSecret -}}
{{- fail "Cannot compose a database URL from the subchart secret: set database.syncstorageDatabaseUrl (and optionally database.tokenserverDatabaseUrl) explicitly" -}}
{{- end -}}
{{- $user := required "Set postgresql.auth.username or database.syncstorageDatabaseUrl" .Values.postgresql.auth.username -}}
{{- $pass := required "Set postgresql.auth.password or database.syncstorageDatabaseUrl" .Values.postgresql.auth.password -}}
{{- $db := required "Set postgresql.auth.database or database.syncstorageDatabaseUrl" .Values.postgresql.auth.database -}}
{{- $port := default 5432 .Values.postgresql.primary.service.ports.postgresql -}}
{{- $storageUrl = printf "postgres://%s:%s@%s:%v/%s" (urlquery $user) (urlquery $pass) (include "syncstorage-rs.postgresql.host" .) $port $db -}}
{{- else if and (not $storageUrl) .Values.mysql.enabled -}}
{{- if .Values.mysql.auth.existingSecret -}}
{{- fail "Cannot compose a database URL from the subchart secret: set database.syncstorageDatabaseUrl (and optionally database.tokenserverDatabaseUrl) explicitly" -}}
{{- end -}}
{{- $user := required "Set mysql.auth.username or database.syncstorageDatabaseUrl" .Values.mysql.auth.username -}}
{{- $pass := required "Set mysql.auth.password or database.syncstorageDatabaseUrl" .Values.mysql.auth.password -}}
{{- $db := required "Set mysql.auth.database or database.syncstorageDatabaseUrl" .Values.mysql.auth.database -}}
{{- $port := default 3306 .Values.mysql.primary.service.ports.mysql -}}
{{- $storageUrl = printf "mysql://%s:%s@%s:%v/%s" (urlquery $user) (urlquery $pass) (include "syncstorage-rs.mysql.host" .) $port $db -}}
{{- if not $tokenserverUrl -}}
{{- $tokenserverUrl = printf "mysql://%s:%s@%s:%v/%s" (urlquery $user) (urlquery $pass) (include "syncstorage-rs.mysql.host" .) $port (default "tokenserver" .Values.mysql.tokenserverDatabase) -}}
{{- end -}}
{{- end -}}
{{- if not $storageUrl -}}
{{- fail "No database configured: set database.syncstorageDatabaseUrl (and optionally database.tokenserverDatabaseUrl), database.existingSecret, or enable the postgresql/mysql subchart" -}}
{{- end -}}
{{- if not $tokenserverUrl -}}
{{- $tokenserverUrl = $storageUrl -}}
{{- end -}}
syncstorage-database-url: {{ $storageUrl | b64enc | quote }}
tokenserver-database-url: {{ $tokenserverUrl | b64enc | quote }}
{{- end -}}

{{/*
The storage node URL advertised to clients (SYNC_TOKENSERVER__INIT_NODE_URL).
Defaults to the first ingress host, then to the in-cluster service URL.
*/}}
{{- define "syncstorage-rs.initNodeUrl" -}}
{{- if .Values.tokenserver.initNodeUrl -}}
{{- .Values.tokenserver.initNodeUrl -}}
{{- else if and .Values.ingress.enabled (gt (len .Values.ingress.hosts) 0) -}}
{{- $host := first .Values.ingress.hosts -}}
{{- printf "%s://%s" (ternary "https" "http" (not (empty .Values.ingress.tls))) $host.host -}}
{{- else -}}
{{- printf "http://%s.%s.svc.%s:%v" (include "syncstorage-rs.fullname" .) .Release.Namespace (.Values.clusterDomain | default "cluster.local") .Values.service.port -}}
{{- end -}}
{{- end -}}

{{/*
Name of the secret holding the bundled MySQL credentials (matches the
bitnami/mysql naming scheme).
*/}}
{{- define "syncstorage-rs.mysql.secretName" -}}
{{- if .Values.mysql.auth.existingSecret -}}
{{- .Values.mysql.auth.existingSecret -}}
{{- else if .Values.mysql.fullnameOverride -}}
{{- .Values.mysql.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-mysql" .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
