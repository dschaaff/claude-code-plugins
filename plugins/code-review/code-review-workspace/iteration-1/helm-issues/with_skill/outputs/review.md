# Code Review Summary
**Branch**: main
**Files Changed**: 3 files (70 lines added)
- `Chart.yaml`
- `templates/deployment.yaml`
- `values.yaml`

**Review Date**: 2026-03-24

## Overall Assessment

This is a new Helm chart for deploying an API server to Kubernetes. The chart structure is minimal but functional. However, there are critical security vulnerabilities that must be resolved before this chart is used in any environment -- hardcoded secrets including database credentials, JWT keys, and AWS access keys are committed in plaintext in `values.yaml`. The deployment also uses `hostPath` volumes and lacks resource limits, health checks, and a Service template.

## Strengths

- `Chart.yaml` follows the Helm v2 API spec correctly with appropriate metadata fields
- The deployment template properly uses `.Release.Name` for naming and label consistency, which avoids collisions in multi-release clusters
- Environment variables are injected via a clean `range` loop over `.Values.env`, making them configurable per-release
- Image tag and pull policy are parameterized through values, supporting different environments

## Critical Issues (Must Fix)

### 1. Hardcoded Secrets in values.yaml

- **Location**: `values.yaml:13-20`
- **Problem**: Production database credentials, a JWT signing key, and AWS access keys are hardcoded in plaintext in the values file. This file will be committed to version control.
- **Impact**: Anyone with repository access gains full database access, can forge JWTs, and has AWS API credentials. This is a credential leak and a direct path to full compromise of the application and cloud account.
- **Fix**: Remove all secret values from `values.yaml`. Use Kubernetes Secrets (referenced via `secretKeyRef` in the deployment) and manage them through a secrets manager (e.g., AWS Secrets Manager, HashiCorp Vault, sealed-secrets, or external-secrets-operator).

```yaml
# In deployment.yaml, replace env value references for secrets:
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
```

For non-secret env vars like `REDIS_URL`, keeping them in values is acceptable as long as they contain no credentials.

### 2. hostPath Volume is a Security and Portability Risk

- **Location**: `templates/deployment.yaml:32-34`
- **Problem**: The volume uses `hostPath: /var/data`, which mounts a directory from the host node's filesystem directly into the pod. This bypasses Kubernetes storage abstractions.
- **Impact**: (1) Pods are pinned to specific nodes -- if the node goes down, data is lost or inaccessible. (2) In multi-replica deployments, each replica writes to a different node's `/var/data`, causing data divergence. (3) `hostPath` volumes are a security concern because they can expose host filesystem contents to containers. Many clusters restrict or forbid them via PodSecurityPolicies or admission controllers.
- **Fix**: Use a PersistentVolumeClaim (PVC) instead. If shared storage is needed, use a ReadWriteMany-capable StorageClass.

```yaml
# In deployment.yaml, replace the volumes section:
volumes:
  - name: data
    persistentVolumeClaim:
      claimName: {{ .Release.Name }}-data

# Add a new template: templates/pvc.yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: {{ .Release.Name }}-data
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: {{ .Values.persistence.size | default "10Gi" }}
```

### 3. Using `latest` as Default Image Tag

- **Location**: `values.yaml:4`
- **Problem**: The default image tag is `latest`, which is mutable and non-deterministic. Combined with `imagePullPolicy: Always`, every pod restart may pull a different image.
- **Impact**: Deployments are not reproducible. Rollbacks become unreliable because `latest` may have already been overwritten. Debugging production issues is harder when you cannot determine which exact image is running.
- **Fix**: Default to a placeholder that forces users to set an explicit version, or use a digest.

```yaml
image:
  repository: mycompany/api-server
  tag: ""  # Required: set to a specific version (e.g., "1.2.3" or a SHA digest)
  pullPolicy: IfNotPresent
```

Add a validation check in `templates/_helpers.tpl` or a `required` call:
```yaml
image: "{{ .Values.image.repository }}:{{ required "image.tag is required" .Values.image.tag }}"
```

## Important Issues (Should Fix)

### 4. No Resource Requests or Limits

- **Location**: `values.yaml:24` and `templates/deployment.yaml`
- **Problem**: `resources: {}` means no CPU or memory requests/limits are set. The deployment template does not reference `.Values.resources` at all.
- **Impact**: Without resource requests, the Kubernetes scheduler cannot make informed placement decisions. Without limits, a single pod can consume all node resources, causing evictions of other workloads. Many clusters enforce resource quotas and will reject pods without requests.
- **Fix**: Add resource defaults in `values.yaml` and reference them in the deployment template.

```yaml
# values.yaml
resources:
  requests:
    cpu: 100m
    memory: 128Mi
  limits:
    cpu: 500m
    memory: 512Mi
```

```yaml
# deployment.yaml, under the container spec:
resources:
  {{- toYaml .Values.resources | nindent 12 }}
```

### 5. No Health Checks (Liveness/Readiness Probes)

- **Location**: `templates/deployment.yaml`
- **Problem**: The container definition has no `livenessProbe` or `readinessProbe`.
- **Impact**: Kubernetes cannot detect if the application is hung or not ready to serve traffic. Dead pods will continue receiving traffic. Rolling updates will not wait for readiness before proceeding, risking downtime.
- **Fix**: Add probes appropriate for the API server.

```yaml
livenessProbe:
  httpGet:
    path: /healthz
    port: 8080
  initialDelaySeconds: 15
  periodSeconds: 10
readinessProbe:
  httpGet:
    path: /readyz
    port: 8080
  initialDelaySeconds: 5
  periodSeconds: 5
```

### 6. No Service Template

- **Location**: Missing file `templates/service.yaml`
- **Problem**: `values.yaml` defines `service.type: LoadBalancer` and `service.port: 80`, but there is no Service template to use these values. The deployment creates pods with `containerPort: 8080` but there is no way to route traffic to them within the cluster or externally.
- **Impact**: The chart deploys pods that are unreachable. The service-related values are dead configuration that misleads users.
- **Fix**: Add a Service template.

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

### 7. No Security Context

- **Location**: `templates/deployment.yaml`
- **Problem**: No `securityContext` is set on either the pod or container level. The container will run as root by default.
- **Impact**: Running as root inside a container increases the blast radius of any container escape vulnerability. Many clusters enforce policies that reject pods running as root.
- **Fix**: Add a security context.

```yaml
# Pod-level
securityContext:
  runAsNonRoot: true
  runAsUser: 1000
  fsGroup: 1000

# Container-level
securityContext:
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: true
  capabilities:
    drop:
      - ALL
```

## Suggestions (Nice to Have)

### 8. Add a `templates/_helpers.tpl` for Reusable Labels

- **Location**: `templates/`
- **Problem**: Labels like `app: {{ .Release.Name }}` are duplicated across the deployment (and will be in the Service). Standard Helm charts use a helpers template for consistent label sets including `app.kubernetes.io/name`, `app.kubernetes.io/instance`, `app.kubernetes.io/version`, etc.
- **Impact**: Without standardized labels, monitoring, log aggregation, and cluster tooling (e.g., `kubectl` label selectors) are harder to use consistently.
- **Fix**: Add `templates/_helpers.tpl` with common label definitions.

### 9. Expose containerPort as a Value

- **Location**: `templates/deployment.yaml:22`
- **Problem**: The container port `8080` is hardcoded in the template.
- **Impact**: If the application port changes, the template must be edited directly instead of overriding a value.
- **Fix**: Add `containerPort: 8080` to `values.yaml` and reference it in the template.

### 10. Add a `NOTES.txt` Template

- **Location**: Missing `templates/NOTES.txt`
- **Problem**: After `helm install`, users get no post-install instructions.
- **Fix**: Add a `templates/NOTES.txt` that prints how to access the deployed service.

## Quality Metrics

- **Test Coverage**: No `tests/` directory or Helm test templates present. No validation of template rendering.
- **Security**: FAIL -- hardcoded credentials in values, no security context, hostPath volume, container runs as root.
- **Performance**: No resource requests/limits defined; scheduler cannot optimize placement.
- **Documentation**: Minimal -- `Chart.yaml` has a description but there is no README or NOTES.txt.

## Review Checklist

- [ ] All tests pass -- no tests exist
- [ ] No security vulnerabilities -- FAIL: hardcoded secrets, hostPath, no securityContext
- [ ] Error handling is comprehensive -- N/A for Helm templates
- [ ] Documentation updated -- no documentation present
- [ ] Breaking changes documented -- N/A (initial chart)
- [ ] Performance acceptable -- no resource limits defined
- [ ] Code follows project conventions -- missing standard Helm patterns (helpers, NOTES.txt)
- [ ] No TODO/FIXME left unaddressed -- none found

## Next Steps

1. **Remove all secrets from `values.yaml` immediately** -- replace with Kubernetes Secret references using `secretKeyRef`. Never commit credentials to version control.
2. **Replace hostPath volume** with a PersistentVolumeClaim.
3. **Set image tag to a specific version** and change `pullPolicy` to `IfNotPresent`.
4. **Add resource requests and limits** in both `values.yaml` and the deployment template.
5. **Add liveness and readiness probes** to the container spec.
6. **Create `templates/service.yaml`** so traffic can reach the pods.
7. **Add a security context** to run as non-root with dropped capabilities.
8. Consider adding `_helpers.tpl`, parameterizing the container port, and adding `NOTES.txt`.
