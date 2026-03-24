# Code Review: Staged Changes (main)
1 file changed | 2026-03-24

**Pre-review checks**: No test or lint infrastructure found. No `tflint.hcl`, CI config, or `CLAUDE.md` in the repo. Recommend adding `tflint` and `tfsec` as a baseline.

## Strengths
- Uses `required_version` and pinned provider version constraints (`main.tf:1-9`), which prevents accidental provider drift.
- S3 bucket public access block resource is explicitly declared rather than relying on defaults, showing awareness that these settings should be managed as code.

## Critical Issues

### 1. Hardcoded database password in plaintext
- **Location**: `main.tf:88`
- **Problem**: The RDS password `SuperSecret123!` is committed in plaintext. Anyone with repo access has production database credentials. This will also appear in Terraform state, plan output, and CI logs.
- **Fix**: Use AWS Secrets Manager or SSM Parameter Store. Pass the secret ARN/reference at apply time:
  ```hcl
  variable "db_password" {
    type      = string
    sensitive = true
  }

  resource "aws_db_instance" "main" {
    # ...
    password = var.db_password
    # Or better: manage_master_user_password = true
    # which lets RDS manage the secret in Secrets Manager automatically
  }
  ```

### 2. IAM policy grants full admin access (`Action: *, Resource: *`)
- **Location**: `main.tf:66-75`
- **Problem**: The `app-role` IAM policy allows every AWS API call on every resource. A compromised EC2 instance with this role can delete accounts, exfiltrate data from any service, or pivot to other environments. This violates least-privilege.
- **Fix**: Scope the policy to only the actions and resources the application needs:
  ```hcl
  resource "aws_iam_role_policy" "app" {
    name = "app-policy"
    role = aws_iam_role.app.id
    policy = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Effect   = "Allow"
          Action   = [
            "s3:GetObject",
            "s3:PutObject",
          ]
          Resource = "${aws_s3_bucket.data.arn}/*"
        }
      ]
    })
  }
  ```

### 3. S3 bucket is publicly readable (data exfiltration risk)
- **Location**: `main.tf:19-46`
- **Problem**: The public access block is fully disabled and a bucket policy grants `s3:GetObject` and `s3:ListBucket` to `Principal: *`. For a production analytics data bucket, this exposes all objects to the internet. Anyone can enumerate and download every file.
- **Fix**: Enable all four public access block flags and remove the public bucket policy. If external access is genuinely needed, use pre-signed URLs or CloudFront with OAC:
  ```hcl
  resource "aws_s3_bucket_public_access_block" "data" {
    bucket = aws_s3_bucket.data.id

    block_public_acls       = true
    block_public_policy     = true
    ignore_public_acls      = true
    restrict_public_buckets = true
  }
  ```

### 4. RDS instance is publicly accessible with 0.0.0.0/0 ingress
- **Location**: `main.tf:91` and `main.tf:99-105`
- **Problem**: `publicly_accessible = true` gives the database a public IP, and the security group allows port 5432 from any IP on the internet. Combined with the hardcoded password, this is a direct path to data breach.
- **Fix**: Set `publicly_accessible = false`, place the database in a private subnet, and restrict the security group to the application's CIDR or security group:
  ```hcl
  resource "aws_db_instance" "main" {
    # ...
    publicly_accessible = false
    db_subnet_group_name = aws_db_subnet_group.private.name
    vpc_security_group_ids = [aws_security_group.db.id]
  }

  resource "aws_security_group" "db" {
    # ...
    ingress {
      from_port       = 5432
      to_port         = 5432
      protocol        = "tcp"
      security_groups = [aws_security_group.app.id]
    }
  }
  ```

### 5. RDS storage is unencrypted
- **Location**: `main.tf:90`
- **Problem**: `storage_encrypted = false` means data at rest on the production database is not encrypted. This fails most compliance frameworks (SOC 2, HIPAA, PCI-DSS) and is a regulatory risk.
- **Fix**: Enable encryption:
  ```hcl
  storage_encrypted = true
  ```

## Important Issues

### 6. No backups configured and no deletion protection
- **Location**: `main.tf:93-94`
- **Problem**: `backup_retention_period = 0` disables automated backups entirely. `deletion_protection = false` means a `terraform destroy` or accidental removal from state deletes the production database with no recovery path. `skip_final_snapshot = true` compounds this -- even a manual destroy won't produce a snapshot.
- **Fix**:
  ```hcl
  backup_retention_period = 7     # or longer
  deletion_protection     = true
  skip_final_snapshot     = false
  final_snapshot_identifier = "prod-database-final"
  ```

### 7. Security group not attached to VPC or RDS instance
- **Location**: `main.tf:97-112`
- **Problem**: The `aws_security_group.db` resource is defined but never referenced by the `aws_db_instance.main` resource (no `vpc_security_group_ids` attribute). The security group also lacks a `vpc_id`, so it defaults to the default VPC. The database has no explicit network controls applied.
- **Fix**: Add `vpc_id` to the security group and reference it from the RDS instance:
  ```hcl
  resource "aws_security_group" "db" {
    name   = "db-sg"
    vpc_id = aws_vpc.main.id
    # ...
  }

  resource "aws_db_instance" "main" {
    # ...
    vpc_security_group_ids = [aws_security_group.db.id]
  }
  ```

### 8. S3 bucket missing versioning and server-side encryption
- **Location**: `main.tf:15-17`
- **Problem**: No `aws_s3_bucket_versioning` or `aws_s3_bucket_server_side_encryption_configuration` resources. For a production analytics data bucket, accidental overwrites or deletions are unrecoverable, and data at rest is unencrypted.
- **Fix**: Add versioning and encryption resources:
  ```hcl
  resource "aws_s3_bucket_versioning" "data" {
    bucket = aws_s3_bucket.data.id
    versioning_configuration {
      status = "Enabled"
    }
  }

  resource "aws_s3_bucket_server_side_encryption_configuration" "data" {
    bucket = aws_s3_bucket.data.id
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "aws:kms"
      }
    }
  }
  ```

## Suggestions

### 9. No Terraform backend configured
- **Location**: `main.tf:1-9`
- **Problem**: Without a remote backend, state is stored locally. This blocks team collaboration and risks state loss.
- **Fix**: Add an S3 + DynamoDB backend (or Terraform Cloud).

### 10. Hardcoded region and bucket name
- **Location**: `main.tf:13`, `main.tf:16`
- **Problem**: The region and bucket name are hardcoded. This makes reuse across environments impossible.
- **Fix**: Extract into variables.

## Next Steps
1. **Immediately** remove the hardcoded password from `main.tf:88` and rotate the credential if it was ever applied. Use `manage_master_user_password = true` or a `sensitive` variable.
2. Replace the `Action: *` / `Resource: *` IAM policy with scoped permissions.
3. Lock down the S3 bucket: enable the public access block, remove the public policy, add encryption and versioning.
4. Make the RDS instance private: set `publicly_accessible = false`, restrict the security group, attach it to the instance.
5. Enable RDS encryption, backups, and deletion protection.
6. Add `tflint` and `tfsec` to catch these classes of issues automatically going forward.
