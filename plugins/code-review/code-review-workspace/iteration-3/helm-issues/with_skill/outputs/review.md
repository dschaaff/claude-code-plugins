# Code Review: main
3 files changed | 2026-03-24

**Pre-review checks**: `helm lint` passes with one info-level note (missing icon in Chart.yaml). No test infrastructure found.

## Strengths
- Clean Chart.yaml with proper `apiVersion: v2` and semantic versioning
- Deployment template uses Helm best practices for label selectors and release naming
- Environment variables are properly quoted using `| quote` in the template

## Critical Issues

### Hardcoded secrets in values.yaml
- **Location**: `values.yaml:13-20`
- **Problem**: Production database credentials, JWT secret, and AWS access keys are hardcoded in plain text. These will be committed to version control and visible to anyone with repo access.
  ```yaml
  env:
    - name: DATABASE_URL
      value: "postgres://admin:P@ssw0rd123@prod-db.internal:5432/app"
    - name: JWT_SECRET
      value: "my-super-secret-jwt-key-do-not-share"
    - name: AWS_ACCESS_KEY_ID
      value: "AKIAIOSFODNN7EXAMPLE"
    - name: AWS_SECRET_ACCESS_KEY
      value: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
  ```
- **Fix**: Use Kubernetes Secrets (or an external secrets manager like AWS Secrets Manager / HashiCorp Vault with the External Secrets Operator). Replace the plain env vars with secret references in the deployment template and remove the values from `values.yaml`:

  In `templates/deployment.yaml`, replace the env block:
  ```yaml
  env:
    - name: DATABASE_URL
      valueFrom:
        secretKeyRef:
          name: {{ .Release.Name }}-secrets
          key: database-url
    - name: JWT_SECRET
      valueFrom:
        secretKeyRef:
          name: {{ .Release.Name }}-secrets
          key: jwt-secret
    - name: AWS_ACCESS_KEY_ID
      valueFrom:
        secretKeyRef:
          name: {{ .Release.Name }}-secrets
          key: aws-access-key-id
    - name: AWS_SECRET_ACCESS_KEY
      valueFrom:
        secretKeyRef:
          name: {{ .Release.Name }}-secrets
          key: aws-secret-access-key
    {{- range .Values.env }}
    - name: {{ .name }}
      value: {{ .value | quote }}
    {{- end }}
  ```

  In `values.yaml`, remove the secret values and keep only non-sensitive env vars:
  ```yaml
  env:
    - name: REDIS_URL
      value: "redis://cache.internal:6379"
  ```

### hostPath volume in deployment
- **Location**: `templates/deployment.yaml:31-34`
- **Problem**: `hostPath` volumes bind the pod to a specific node's filesystem, breaking portability and high availability. They also pose a security risk since a compromised container could access or modify host files. Most admission controllers (OPA/Gatekeeper, Kyverno) block `hostPath` in production.
  ```yaml
  volumes:
    - name: data
      hostPath:
        path: /var/data
  ```
- **Fix**: Use a PersistentVolumeClaim instead:
  ```yaml
  volumes:
    - name: data
      persistentVolumeClaim:
        claimName: {{ .Release.Name }}-data
  ```
  Add a corresponding PVC template or make it configurable via values:
  ```yaml
  # values.yaml
  persistence:
    enabled: true
    storageClass: ""
    size: 10Gi
  ```

### No container security context
- **Location**: `templates/deployment.yaml:18-27`
- **Problem**: The container runs as root by default with full Linux capabilities. A container escape or application vulnerability gives the attacker root on the node.
- **Fix**: Add a security context to the container and pod:
  ```yaml
  spec:
    securityContext:
      runAsNonRoot: true
      fsGroup: 1000
    containers:
      - name: api
        securityContext:
          runAsUser: 1000
          runAsGroup: 1000
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: true
          capabilities:
            drop:
              - ALL
  ```

## Important Issues

### No resource requests or limits
- **Location**: `values.yaml:27`
- **Problem**: `resources: {}` means no CPU/memory requests or limits. The scheduler cannot make informed placement decisions, and a single pod can consume all node resources, starving other workloads.
  ```yaml
  resources: {}
  ```
- **Fix**: Set sensible defaults:
  ```yaml
  resources:
    requests:
      cpu: 100m
      memory: 128Mi
    limits:
      cpu: 500m
      memory: 512Mi
  ```
  And wire them in the deployment template:
  ```yaml
  containers:
    - name: api
      ...
      resources:
        {{- toYaml .Values.resources | nindent 12 }}
  ```

### Image tag set to `latest`
- **Location**: `values.yaml:4`
- **Problem**: Using `latest` as the image tag means deployments are not reproducible. Kubernetes may not pull a new image if one with the `latest` tag is already cached (even with `pullPolicy: Always`, there are edge cases). Rollbacks become impossible because there is no way to identify which version was running.
  ```yaml
  tag: latest
  ```
- **Fix**: Pin to a specific version or digest:
  ```yaml
  tag: "1.0.0"  # or use a SHA digest
  ```

### No liveness or readiness probes
- **Location**: `templates/deployment.yaml:18-27`
- **Problem**: Without probes, Kubernetes cannot detect if the application has crashed or is unable to serve traffic. Failed pods will continue receiving requests, and rolling updates cannot verify the new version is healthy before proceeding.
- **Fix**: Add probes to the container spec:
  ```yaml
  containers:
    - name: api
      ...
      livenessProbe:
        httpGet:
          path: /healthz
          port: 8080
        initialDelaySeconds: 10
        periodSeconds: 15
      readinessProbe:
        httpGet:
          path: /readyz
          port: 8080
        initialDelaySeconds: 5
        periodSeconds: 10
  ```

### No Service template despite service values
- **Location**: `values.yaml:9-11`
- **Problem**: `values.yaml` defines `service.type: LoadBalancer` and `service.port: 80`, but there is no `templates/service.yaml`. These values are dead configuration -- they do nothing.
  ```yaml
  service:
    type: LoadBalancer
    port: 80
  ```
- **Fix**: Either add a Service template or remove the unused values. To add a service:
  ```yaml
  # templates/service.yaml
  apiVersion: v1
  kind: Service
  metadata:
    name: {{ .Release.Name }}-api
    labels:
      app: {{ .Release.Name }}
  spec:
    type: {{ .Values.service.type }}
    ports:
      - port: {{ .Values.service.port }}
        targetPort: 8080
        protocol: TCP
    selector:
      app: {{ .Release.Name }}
  ```

## Suggestions

### Add a helpers template
- **Location**: `templates/`
- **Problem**: Labels and names are manually constructed in each template. As the chart grows, this becomes inconsistent.
- **Fix**: Add a `templates/_helpers.tpl` with standard label and name helpers using `chart`, `release`, and `heritage` labels per Helm conventions.

## Next Steps
1. Remove all hardcoded secrets from `values.yaml` immediately -- these should never be committed
2. Replace `hostPath` with a PersistentVolumeClaim
3. Add security context to run as non-root
4. Set resource requests and limits
5. Pin the image to a specific version tag
6. Add liveness and readiness probes
7. Add a Service template or remove the unused service values
