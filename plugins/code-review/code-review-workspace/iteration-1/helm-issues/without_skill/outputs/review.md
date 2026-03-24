# Helm Chart Code Review: api-server

## Critical Issues

### 1. Hardcoded secrets in values.yaml (values.yaml:13-20)

**Severity: Critical**

Plain-text credentials are committed directly in `values.yaml`:

```yaml
- name: DATABASE_URL
  value: "postgres://admin:P@ssw0rd123@prod-db.internal:5432/app"
- name: JWT_SECRET
  value: "my-super-secret-jwt-key-do-not-share"
- name: AWS_ACCESS_KEY_ID
  value: "AKIAIOSFODNN7EXAMPLE"
- name: AWS_SECRET_ACCESS_KEY
  value: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
```

This is the most severe issue in this chart. Secrets checked into version control are effectively public to anyone with repo access and persist in git history even after removal.

**Recommendation:** Remove all secret values immediately. Use Kubernetes Secrets (referenced via `secretKeyRef` in the deployment env spec) or an external secrets operator (e.g., External Secrets Operator, Sealed Secrets, or Vault). The `env` block in the deployment template should distinguish between plain config and secret references:

```yaml
env:
  - name: DATABASE_URL
    valueFrom:
      secretKeyRef:
        name: api-server-secrets
        key: database-url
```

After fixing, scrub the secrets from git history using `git filter-repo` or `BFG Repo-Cleaner`, and rotate every exposed credential.

---

### 2. hostPath volume usage (templates/deployment.yaml:32-34)

**Severity: Critical**

```yaml
volumes:
  - name: data
    hostPath:
      path: /var/data
```

`hostPath` volumes are a significant security and reliability problem:

- **Security:** Grants the container access to the host filesystem, which is a container escape vector. Most Pod Security Standards (Restricted profile) and admission controllers (OPA/Gatekeeper, Kyverno) will reject this.
- **Portability:** Ties the workload to a specific node. If the pod is rescheduled to another node, it loses its data.
- **Multi-replica:** With `replicaCount > 1`, replicas on different nodes would see different data.

**Recommendation:** Use a PersistentVolumeClaim with a proper StorageClass, or remove the volume entirely if persistent local data is not actually needed for an API server. If you truly need local node storage, use a `local` PersistentVolume with node affinity constraints.

---

## High Severity Issues

### 3. No securityContext defined (templates/deployment.yaml)

The deployment has no pod-level or container-level `securityContext`. By default, the container may run as root, which violates the principle of least privilege.

**Recommendation:** Add both pod and container security contexts:

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

### 4. No resource requests or limits (values.yaml:26)

```yaml
resources: {}
```

Without resource requests, the scheduler cannot make informed placement decisions. Without limits, a single pod can consume all node resources, starving other workloads. The pod will also have a `BestEffort` QoS class, making it the first to be evicted under memory pressure.

**Recommendation:** Set meaningful defaults:

```yaml
resources:
  requests:
    cpu: 100m
    memory: 128Mi
  limits:
    cpu: 500m
    memory: 256Mi
```

### 5. Image tag `latest` (values.yaml:4)

```yaml
tag: latest
```

Using `latest` means deployments are not reproducible. Rollbacks become unreliable because you cannot determine which image version is running. Two pods in the same deployment could end up running different image versions.

**Recommendation:** Pin to a specific immutable tag or digest (e.g., `v1.0.0` or `sha256:abc123...`).

### 6. No health probes (templates/deployment.yaml)

The container defines no `livenessProbe`, `readinessProbe`, or `startupProbe`. Without these:

- Kubernetes cannot detect if the application has crashed or become unresponsive.
- The pod will receive traffic immediately, even before the application is ready.
- Rolling updates cannot verify the new version is healthy before terminating old pods.

**Recommendation:** Add at minimum a readiness probe and a liveness probe:

```yaml
readinessProbe:
  httpGet:
    path: /healthz
    port: 8080
  initialDelaySeconds: 5
  periodSeconds: 10
livenessProbe:
  httpGet:
    path: /healthz
    port: 8080
  initialDelaySeconds: 15
  periodSeconds: 20
```

---

## Medium Severity Issues

### 7. No Service template

`values.yaml` defines `service.type: LoadBalancer` and `service.port: 80`, but there is no `templates/service.yaml`. These values are unused, which is misleading. Either add a Service template or remove the dead config from `values.yaml`.

### 8. Service type LoadBalancer exposed externally (values.yaml:9-10)

```yaml
service:
  type: LoadBalancer
  port: 80
```

`LoadBalancer` provisions a public-facing cloud load balancer by default. If this API is internal, use `ClusterIP` and expose it through an Ingress with TLS termination instead. Exposing on port 80 without TLS is also a concern for production workloads.

### 9. Single replica (values.yaml:1)

```yaml
replicaCount: 1
```

A single replica means zero availability during node failures, deployments, or pod evictions. For a production API server, run at least 2 replicas and add a PodDisruptionBudget.

### 10. No `automountServiceAccountToken: false`

If the API server does not need to talk to the Kubernetes API, explicitly disable automatic mounting of the service account token. This reduces the blast radius if the container is compromised.

---

## Low Severity / Best Practice Issues

### 11. Missing templates

A production-quality Helm chart should also include:

- `templates/serviceaccount.yaml` -- dedicated service account rather than using `default`
- `templates/_helpers.tpl` -- standard Helm label/name helpers for consistency
- `templates/NOTES.txt` -- post-install user guidance

### 12. Labels are minimal

Only `app: {{ .Release.Name }}` is used. The standard Helm recommended labels provide better observability and management:

```yaml
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
```

### 13. Chart.yaml is minimal

Consider adding `maintainers`, `home`, and `sources` fields for traceability. The `appVersion` should match the actual application version being deployed, not a placeholder.

---

## Summary

| Severity | Count | Key Themes |
|----------|-------|------------|
| Critical | 2 | Hardcoded secrets, hostPath volume |
| High | 4 | No securityContext, no resource limits, `latest` tag, no health probes |
| Medium | 4 | Missing Service template, external LoadBalancer, single replica, service account token |
| Low | 3 | Missing helpers/templates, minimal labels, sparse Chart.yaml |

This chart should not be deployed in its current state. The hardcoded credentials in `values.yaml` must be removed and rotated before this code is merged. The hostPath volume and lack of security context represent container security risks that most admission controllers will reject. After addressing the critical and high issues, the medium items should be resolved before any production use.
