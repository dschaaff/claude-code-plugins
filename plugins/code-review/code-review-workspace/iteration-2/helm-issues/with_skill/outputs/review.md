# Code Review: Helm Chart - api-server
3 files changed | 2026-03-24

**Pre-review checks**: No test infrastructure found. No `helm lint` or CI config present. Running `helm template` would validate rendering but helm may not be available in this environment.

## Strengths
- Clean Chart.yaml with correct apiVersion v2 and proper metadata
- Deployment template uses proper label selectors and templated release names
- Environment variables are properly quoted with `| quote`

## Critical Issues

### Hardcoded secrets in values.yaml
- **Location**: `values.yaml:13-20`
- **Problem**: Four secrets are committed in plaintext: a database password (`P@ssw0rd123`), a JWT signing key, an AWS access key ID, and an AWS secret access key. Even though these may be example/placeholder values, committing secrets in version control is a security risk. Anyone with repo access can read them, and they persist in git history even after removal.
- **Fix**: Remove all secret values from `values.yaml`. Use Kubernetes Secrets (referenced via `secretKeyRef`) or an external secrets manager (e.g., AWS Secrets Manager with External Secrets Operator, or Sealed Secrets). Example:
  ```yaml
  # values.yaml
  env:
    - name: REDIS_URL
      value: "redis://cache.internal:6379"

  # For secrets, reference a K8s Secret instead:
  secretEnv:
    - name: DATABASE_URL
      secretName: api-server-secrets
      secretKey: database-url
    - name: JWT_SECRET
      secretName: api-server-secrets
      secretKey: jwt-secret
    - name: AWS_ACCESS_KEY_ID
      secretName: api-server-secrets
      secretKey: aws-access-key-id
    - name: AWS_SECRET_ACCESS_KEY
      secretName: api-server-secrets
      secretKey: aws-secret-access-key
  ```
  Then in `deployment.yaml`, add a block for secret env vars:
  ```yaml
  {{- range .Values.secretEnv }}
  - name: {{ .name }}
    valueFrom:
      secretKeyRef:
        name: {{ .secretName }}
        key: {{ .secretKey }}
  {{- end }}
  ```

### hostPath volume is a security and reliability risk
- **Location**: `templates/deployment.yaml:33-34`
- **Problem**: Using `hostPath` with `/var/data` ties the pod to a specific node's filesystem, breaks portability across nodes, and exposes the host filesystem to the container. This is a security concern (container can read/write arbitrary host data) and a reliability concern (pod rescheduling to another node loses data).
- **Fix**: Replace with a PersistentVolumeClaim or remove if not needed:
  ```yaml
  volumes:
    - name: data
      persistentVolumeClaim:
        claimName: {{ .Release.Name }}-data
  ```
  Add a PVC template or allow configuring storage via values.

## Important Issues

### No resource requests or limits configured
- **Location**: `values.yaml:27`
- **Problem**: `resources: {}` means no CPU/memory requests or limits. Without requests, the scheduler cannot make informed placement decisions. Without limits, a single pod can consume all node resources and starve other workloads.
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
  And reference them in `deployment.yaml`:
  ```yaml
  resources:
    {{- toYaml .Values.resources | nindent 12 }}
  ```

### No security context on the container
- **Location**: `templates/deployment.yaml:19`
- **Problem**: The container runs as root by default. This violates the principle of least privilege and is flagged by most cluster admission policies (e.g., Pod Security Standards).
- **Fix**: Add a security context:
  ```yaml
  containers:
    - name: api
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
        readOnlyRootFilesystem: true
        allowPrivilegeEscalation: false
        capabilities:
          drop:
            - ALL
  ```

### Image tag `latest` is unreliable
- **Location**: `values.yaml:4`
- **Problem**: Using `latest` as the default tag means deployments are not reproducible. Different deploys can pull different images, and rollbacks become impossible since there is no specific version to roll back to.
- **Fix**: Default to a specific version tag (e.g., `1.0.0`) and use `pullPolicy: IfNotPresent`:
  ```yaml
  image:
    repository: mycompany/api-server
    tag: "1.0.0"
    pullPolicy: IfNotPresent
  ```

### No health checks (liveness/readiness probes)
- **Location**: `templates/deployment.yaml:19-26`
- **Problem**: Without probes, Kubernetes cannot detect if the application is healthy or ready to receive traffic. Failed containers will continue receiving requests, and rolling updates cannot verify new pods are working.
- **Fix**: Add probes:
  ```yaml
  livenessProbe:
    httpGet:
      path: /healthz
      port: 8080
    initialDelaySeconds: 10
    periodSeconds: 15
  readinessProbe:
    httpGet:
      path: /ready
      port: 8080
    initialDelaySeconds: 5
    periodSeconds: 10
  ```

### Service defined in values but no Service template exists
- **Location**: `values.yaml:9-11`
- **Problem**: `values.yaml` defines `service.type: LoadBalancer` and `service.port: 80`, but there is no `templates/service.yaml`. These values are unused, and the deployment has no way to receive external traffic.
- **Fix**: Either create a Service template that references these values, or remove the unused `service` block from values.yaml to avoid confusion.

## Suggestions

### Add a templates/_helpers.tpl for reusable labels
- **Location**: `templates/deployment.yaml:5-6`
- **Problem**: Labels are defined inline and only include `app`. Standard Helm charts use a helpers file with `app.kubernetes.io/name`, `app.kubernetes.io/instance`, `app.kubernetes.io/version`, etc.
- **Fix**: Add `templates/_helpers.tpl` with standard label helpers and reference them via `include`.

### containerPort should be configurable
- **Location**: `templates/deployment.yaml:22`
- **Problem**: Port 8080 is hardcoded in the template. If the application port changes, the template must be edited directly.
- **Fix**: Add a `containerPort` value and reference it: `containerPort: {{ .Values.containerPort | default 8080 }}`

## Next Steps
1. Remove all hardcoded secrets from values.yaml immediately and rotate any real credentials that may have been exposed
2. Replace hostPath volume with a PersistentVolumeClaim
3. Add security context with non-root user
4. Set resource requests and limits
5. Pin a specific image tag instead of `latest`
6. Add liveness and readiness probes
7. Create a Service template or remove unused service values
