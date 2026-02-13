{{/*
Chart name, truncated to 63 characters.
*/}}
{{- define "eks-logging.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Fully qualified app name. Uses release name + chart name, truncated to 63 chars.
If release name already contains chart name, just use release name.
*/}}
{{- define "eks-logging.fullname" -}}
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
Component name: <release>-<component>, truncated to 63 chars.
Usage: include "eks-logging.componentName" (dict "component" "elasticsearch" "context" $)
*/}}
{{- define "eks-logging.componentName" -}}
{{- printf "%s-%s" .context.Release.Name .component | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels applied to all resources.
*/}}
{{- define "eks-logging.commonLabels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: efk-stack
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- if .Values.global.environment }}
environment: {{ .Values.global.environment }}
{{- end }}
{{- if .Values.global.team }}
team: {{ .Values.global.team }}
{{- end }}
{{- end }}

{{/*
Component labels: common labels + component label.
Usage: include "eks-logging.componentLabels" (dict "component" "elasticsearch" "context" $)
*/}}
{{- define "eks-logging.componentLabels" -}}
{{ include "eks-logging.commonLabels" .context }}
app.kubernetes.io/name: {{ .context.Chart.Name }}
app.kubernetes.io/component: {{ .component }}
{{- end }}

{{/*
Selector labels for matchLabels (minimal, stable set).
Usage: include "eks-logging.selectorLabels" (dict "component" "elasticsearch" "context" $)
*/}}
{{- define "eks-logging.selectorLabels" -}}
app.kubernetes.io/instance: {{ .context.Release.Name }}
app.kubernetes.io/component: {{ .component }}
{{- end }}

{{/*
Elasticsearch labels — includes legacy "app: elasticsearch-master" for test-logging.sh compat.
*/}}
{{- define "eks-logging.elasticsearchLabels" -}}
{{ include "eks-logging.componentLabels" (dict "component" "elasticsearch" "context" .context) }}
app: elasticsearch-master
{{- end }}

{{/*
Kibana labels — includes legacy "app: kibana" for test-logging.sh compat.
*/}}
{{- define "eks-logging.kibanaLabels" -}}
{{ include "eks-logging.componentLabels" (dict "component" "kibana" "context" .context) }}
app: kibana
{{- end }}

{{/*
FluentD labels — includes legacy "app.kubernetes.io/name: fluentd" for test-logging.sh compat.
*/}}
{{- define "eks-logging.fluentdLabels" -}}
{{ include "eks-logging.componentLabels" (dict "component" "fluentd" "context" .context) }}
app.kubernetes.io/name: fluentd
{{- end }}

{{/*
Namespace to use.
*/}}
{{- define "eks-logging.namespace" -}}
{{- default .Release.Namespace .Values.namespace.name }}
{{- end }}
