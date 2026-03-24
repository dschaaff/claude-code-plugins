# Terraform Code Review: Production Analytics Platform

**File:** `main.tf`
**Verdict:** Do not merge. This configuration contains multiple critical security vulnerabilities that would expose production data and infrastructure to the public internet.

---

## Critical Issues

### 1. S3 bucket is publicly readable (main.tf:19-46)

The public access block is fully disabled and a bucket policy grants `s3:GetObject` and `s3:ListBucket` to `Principal = "*"`. This means anyone on the internet can list and download every object in the production analytics data bucket.

**Fix:** Set all four `block_public_*` / `ignore_public_*` / `restrict_public_*` fields to `true`. Remove the public bucket policy. Grant access only to specific IAM roles or accounts that need it.

### 2. IAM role has unrestricted admin privileges (main.tf:62-72)

```hcl
Action   = "*"
Resource = "*"
```

This grants full AWS account access to any EC2 instance that assumes this role. A single compromised instance gives an attacker control over the entire AWS account (billing, IAM, other services, data destruction).

**Fix:** Follow least-privilege. Scope `Action` and `Resource` to only the specific services and resources the application needs (e.g., `s3:GetObject` on the analytics bucket, specific DynamoDB tables, etc.).

### 3. Database password is hardcoded in plaintext (main.tf:82)

```hcl
password = "SuperSecret123!"
```

This password will be stored in Terraform state (unencrypted by default), version control history, and plan output. Anyone with access to the repo or state file has the production database credentials.

**Fix:** Use AWS Secrets Manager or SSM Parameter Store. Alternatively, use `random_password` with `aws_secretsmanager_secret_version` and reference it. At minimum, use a variable marked `sensitive = true` and supply it at plan time, but a secrets manager is strongly preferred.

### 4. RDS instance is publicly accessible with no encryption (main.tf:75-92)

- `publicly_accessible = true` exposes the database endpoint to the internet.
- `storage_encrypted = false` means data at rest is unencrypted.

For a production database holding analytics data, both are unacceptable.

**Fix:** Set `publicly_accessible = false`, `storage_encrypted = true`, and specify a KMS key via `kms_key_id`. Place the RDS instance in private subnets (requires `db_subnet_group_name`).

### 5. Security group allows database access from the entire internet (main.tf:95-110)

```hcl
cidr_blocks = ["0.0.0.0/0"]
```

Port 5432 (PostgreSQL) is open to all IP addresses. Combined with the publicly accessible RDS instance, the database is directly attackable from anywhere.

**Fix:** Restrict `cidr_blocks` to only the application subnets or reference a security group ID for the application tier using `security_groups` instead of `cidr_blocks`.

### 6. Security group is not attached to the RDS instance (main.tf:75-110)

The `aws_security_group.db` resource is defined but never referenced by `aws_db_instance.main` (no `vpc_security_group_ids` argument). The security group has no effect, and the RDS instance will use the VPC default security group instead.

**Fix:** Add `vpc_security_group_ids = [aws_security_group.db.id]` to the `aws_db_instance` resource.

---

## High-Severity Issues

### 7. No backup retention for production database (main.tf:91)

`backup_retention_period = 0` disables all automated backups. A data loss event (accidental deletion, corruption, ransomware) is unrecoverable.

**Fix:** Set `backup_retention_period` to at least `7` (days). For production, 14-35 days is common.

### 8. Deletion protection is disabled (main.tf:90)

`deletion_protection = false` means a `terraform destroy` or accidental resource removal will immediately delete the production database without any guard.

**Fix:** Set `deletion_protection = true`.

### 9. Final snapshot is skipped (main.tf:89)

`skip_final_snapshot = true` means no snapshot is taken if the database is deleted. Combined with no backups, this guarantees data loss on deletion.

**Fix:** Set `skip_final_snapshot = false` and provide `final_snapshot_identifier`.

---

## Best Practice Issues

### 10. No Terraform backend configured (main.tf:1-9)

There is no `backend` block. State will be stored locally, which means:
- No state locking (concurrent applies can corrupt state).
- No shared access for team members.
- State file (containing the plaintext DB password) sits on a local disk.

**Fix:** Configure a remote backend (e.g., S3 + DynamoDB for locking).

### 11. No VPC or subnet configuration

The RDS instance and security group have no `vpc_id` or `subnet_group_name`. Everything lands in the default VPC, which typically has public subnets. Production infrastructure should use a dedicated VPC with private subnets.

### 12. Hardcoded region and bucket name (main.tf:13, 16)

The provider region and S3 bucket name are hardcoded. Use variables so this configuration can be reused across environments and regions without editing the source.

### 13. S3 bucket lacks versioning and lifecycle rules

For a production analytics data bucket, object versioning protects against accidental overwrites/deletes. Lifecycle rules manage storage costs. Neither is configured.

### 14. S3 bucket lacks server-side encryption configuration

No `aws_s3_bucket_server_side_encryption_configuration` resource is defined. Objects will be stored unencrypted unless the uploader specifies encryption per-object.

**Fix:** Add an `aws_s3_bucket_server_side_encryption_configuration` resource with SSE-S3 or SSE-KMS.

### 15. No logging or monitoring

There are no CloudWatch alarms, CloudTrail references, S3 access logging, or RDS enhanced monitoring configurations. Production infrastructure should have observability from day one.

---

## Summary

| # | Severity | Issue |
|---|----------|-------|
| 1 | Critical | S3 bucket publicly readable |
| 2 | Critical | IAM role with `*/*` admin access |
| 3 | Critical | Plaintext database password in code |
| 4 | Critical | RDS publicly accessible and unencrypted |
| 5 | Critical | PostgreSQL port open to 0.0.0.0/0 |
| 6 | Critical | Security group not attached to RDS |
| 7 | High | No automated backups |
| 8 | High | Deletion protection disabled |
| 9 | High | Final snapshot skipped |
| 10 | Medium | No remote backend |
| 11 | Medium | No VPC/subnet configuration |
| 12 | Low | Hardcoded region and bucket name |
| 13 | Medium | No S3 versioning or lifecycle rules |
| 14 | Medium | No S3 encryption configuration |
| 15 | Medium | No logging or monitoring |

This configuration should not be applied to any environment. Every critical issue must be resolved before this is safe to plan, let alone apply.
