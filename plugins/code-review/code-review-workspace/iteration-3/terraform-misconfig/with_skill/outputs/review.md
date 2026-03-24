# Code Review: main

1 file changed | 2026-03-24

**Pre-review checks**: `tofu validate` failed (provider not initialized -- expected without `tofu init`). tflint failed to initialize plugins. tfsec found 20 issues: 3 CRITICAL, 6 HIGH, 9 MEDIUM, 2 LOW.

## Strengths

- Pins the AWS provider version (`~> 5.0`) and sets a minimum Terraform version (`>= 1.5`), which prevents accidental upgrades.
- Uses `jsonencode()` for IAM and bucket policies instead of raw heredocs, keeping them type-safe and readable.
- RDS resource specifies an explicit engine version rather than defaulting.

## Critical Issues

### 1. Hardcoded database password in plaintext

- **Location**: `main.tf:84`
- **Problem**: The RDS password is committed as a plaintext string. Anyone with repo access can read it, and it will persist in git history forever.
  ```hcl
  password = "SuperSecret123!"
  ```
- **Fix**: Use a variable marked `sensitive`, or pull from AWS Secrets Manager / SSM Parameter Store. At minimum:
  ```hcl
  variable "db_password" {
    type      = string
    sensitive = true
  }

  resource "aws_db_instance" "main" {
    # ...
    password = var.db_password
    # ...
  }
  ```
  Supply the value via `TF_VAR_db_password` environment variable or a secrets manager data source. Rotate the exposed password immediately.

### 2. IAM policy grants full access to all AWS resources

- **Location**: `main.tf:65-73`
- **Problem**: The app role policy uses `Action = "*"` and `Resource = "*"`, granting unrestricted access to every AWS service and resource in the account. This violates least-privilege and means a compromised EC2 instance can do anything -- delete databases, exfiltrate S3 data, create new IAM users.
  ```hcl
  {
    Effect   = "Allow"
    Action   = "*"
    Resource = "*"
  }
  ```
- **Fix**: Scope the policy to only the services and resources the application actually needs. For an analytics platform that reads from S3 and queries RDS:
  ```hcl
  {
    Effect = "Allow"
    Action = [
      "s3:GetObject",
      "s3:ListBucket",
    ]
    Resource = [
      aws_s3_bucket.data.arn,
      "${aws_s3_bucket.data.arn}/*",
    ]
  }
  ```
  Add separate statements for other required permissions (CloudWatch logs, etc.).

### 3. Production S3 bucket is publicly readable

- **Location**: `main.tf:19-26` (public access block) and `main.tf:29-46` (bucket policy)
- **Problem**: The public access block has all four protections set to `false`, and the bucket policy grants `s3:GetObject` and `s3:ListBucket` to `Principal = "*"`. This means anyone on the internet can list and download all objects in the production analytics data bucket.
  ```hcl
  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
  ```
  ```hcl
  Principal = "*"
  Action    = ["s3:GetObject", "s3:ListBucket"]
  ```
- **Fix**: Block all public access and remove the public bucket policy. If internal services need access, use IAM roles instead:
  ```hcl
  resource "aws_s3_bucket_public_access_block" "data" {
    bucket = aws_s3_bucket.data.id

    block_public_acls       = true
    block_public_policy     = true
    ignore_public_acls      = true
    restrict_public_buckets = true
  }
  ```
  Remove the `aws_s3_bucket_policy.data` resource entirely, and grant access through the app role's IAM policy instead.

### 4. RDS instance is publicly accessible with an open security group

- **Location**: `main.tf:89` and `main.tf:99-104`
- **Problem**: The database has `publicly_accessible = true` and the security group allows inbound PostgreSQL traffic from `0.0.0.0/0`. This exposes the production database directly to the internet.
  ```hcl
  publicly_accessible    = true
  ```
  ```hcl
  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ```
- **Fix**: Place the database in a private subnet and restrict the security group to application traffic only:
  ```hcl
  resource "aws_db_instance" "main" {
    # ...
    publicly_accessible = false
    db_subnet_group_name = aws_db_subnet_group.private.name
    vpc_security_group_ids = [aws_security_group.db.id]
    # ...
  }

  resource "aws_security_group" "db" {
    name        = "db-sg"
    description = "Database security group"
    vpc_id      = aws_vpc.main.id

    ingress {
      description     = "PostgreSQL from app instances"
      from_port       = 5432
      to_port         = 5432
      protocol        = "tcp"
      security_groups = [aws_security_group.app.id]
    }
  }
  ```
  This requires defining a VPC, subnets, and an app security group, which are missing from this configuration entirely.

## Important Issues

### 5. RDS storage encryption is disabled

- **Location**: `main.tf:88`
- **Problem**: Production database storage is unencrypted. Data at rest is exposed if the underlying storage is compromised.
  ```hcl
  storage_encrypted = false
  ```
- **Fix**:
  ```hcl
  storage_encrypted = true
  kms_key_id        = aws_kms_key.rds.arn  # or use default aws/rds key by omitting this
  ```

### 6. No backups, no deletion protection, no final snapshot

- **Location**: `main.tf:90-92`
- **Problem**: Three separate data-loss risks stacked together. `backup_retention_period = 0` means no automated backups. `deletion_protection = false` means a `tofu destroy` deletes the database immediately. `skip_final_snapshot = true` means no snapshot is taken on deletion.
  ```hcl
  skip_final_snapshot    = true
  deletion_protection    = false
  backup_retention_period = 0
  ```
- **Fix**: For a production database:
  ```hcl
  skip_final_snapshot     = false
  final_snapshot_identifier = "prod-database-final"
  deletion_protection     = true
  backup_retention_period = 7
  ```

### 7. S3 bucket missing encryption, versioning, and logging

- **Location**: `main.tf:15-17`
- **Problem**: The production analytics data bucket has no server-side encryption configuration, no versioning (accidental deletes are permanent), and no access logging.
- **Fix**: Add these companion resources:
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

  resource "aws_s3_bucket_logging" "data" {
    bucket        = aws_s3_bucket.data.id
    target_bucket = aws_s3_bucket.logs.id
    target_prefix = "s3-access-logs/data/"
  }
  ```

### 8. No VPC definition -- resources have no network isolation

- **Location**: `main.tf` (entire file)
- **Problem**: There is no VPC, subnet, or network architecture defined. The security group has no `vpc_id`, so it defaults to the default VPC. The RDS instance has no `db_subnet_group_name`. For a production analytics platform, this means no network segmentation between public and private resources.
- **Fix**: Define a VPC with public and private subnets. Place the database and application instances in private subnets. Use a NAT gateway for outbound internet access from private subnets if needed.

### 9. Security group not attached to the RDS instance

- **Location**: `main.tf:76-93` and `main.tf:95-112`
- **Problem**: The `aws_security_group.db` is defined but never referenced by the `aws_db_instance.main` resource. The database will use the default VPC security group instead, which may have different rules than intended.
- **Fix**: Add `vpc_security_group_ids` to the RDS instance:
  ```hcl
  resource "aws_db_instance" "main" {
    # ...
    vpc_security_group_ids = [aws_security_group.db.id]
    # ...
  }
  ```

## Suggestions

### 10. No Terraform backend configured

- **Location**: `main.tf:1-9`
- **Problem**: State will be stored locally by default. For production infrastructure, this means no state locking, no shared access, and state loss if the local file is deleted.
- **Fix**: Add a remote backend (e.g., S3 + DynamoDB for locking).

### 11. No tags on any resources

- **Problem**: None of the resources have tags. Tags are essential for cost allocation, ownership tracking, and automated operations in production.
- **Fix**: Add a `default_tags` block in the provider:
  ```hcl
  provider "aws" {
    region = "us-east-1"
    default_tags {
      tags = {
        Environment = "production"
        Project     = "analytics-platform"
        ManagedBy   = "terraform"
      }
    }
  }
  ```

### 12. Hardcoded region and bucket name

- **Location**: `main.tf:12` and `main.tf:16`
- **Problem**: The region and bucket name are hardcoded strings. This makes it impossible to deploy to another region or environment without modifying the code.
- **Fix**: Use variables for both.

## Next Steps

1. **Immediately** remove the hardcoded password from source control and rotate it. Even after removal, it will remain in git history -- consider using `git filter-repo` to purge it, or rotate the credential.
2. Fix all Critical issues (public S3 bucket, wildcard IAM policy, public RDS + open security group) before this goes anywhere near a production account.
3. Add VPC infrastructure with private subnets for the database.
4. Enable encryption, backups, versioning, and deletion protection on data stores.
5. Configure a remote backend for state management.
