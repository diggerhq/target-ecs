resource "aws_security_group" "nsg_lb" {
  name        = var.security_group_name
  description = "For ${var.alb_name}"
  vpc_id      = var.vpc_id
  tags = var.tags
}

resource "aws_alb" "main" {
  name = var.alb_name

  # launch lbs in public or private subnets based on "internal" variable
  internal        = var.internal
  subnets         = var.subnet_ids
  security_groups = [aws_security_group.nsg_lb.id]
  tags            = var.tags

  # enable access logs in order to get support from aws
  access_logs {
    enabled = true
    bucket  = aws_s3_bucket.lb_access_logs.bucket
  }
}



data "aws_elb_service_account" "main" {
}

# bucket for storing ALB access logs
resource "aws_s3_bucket" "lb_access_logs" {
  bucket_prefix = var.alb_name
  tags          = var.tags
  force_destroy = true
}

resource "aws_s3_bucket_acl" "lb_access_logs_acl" {
  bucket = aws_s3_bucket.lb_access_logs.id
  acl    = "private"
}

resource "aws_s3_bucket_lifecycle_configuration" "lb_access_logs_lifecycle_rule" {
  bucket = aws_s3_bucket.lb_access_logs.id

  rule {
    id     = "cleanup"
    status = "Enabled"

    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
    expiration {
      days = var.access_logs_expiration_days
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "lb_access_logs_server_side_encryption" {
  bucket = aws_s3_bucket.lb_access_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}


# give load balancing service access to the bucket
resource "aws_s3_bucket_policy" "lb_access_logs" {
  bucket = aws_s3_bucket.lb_access_logs.id

  policy = <<POLICY
{
  "Id": "Policy",
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "s3:PutObject"
      ],
      "Effect": "Allow",
      "Resource": [
        "${aws_s3_bucket.lb_access_logs.arn}",
        "${aws_s3_bucket.lb_access_logs.arn}/*"
      ],
      "Principal": {
        "AWS": [ "${data.aws_elb_service_account.main.arn}" ]
      }
    }
  ]
}
POLICY
}

# The load balancer DNS name
output "lb_dns" {
  value = aws_alb.main.dns_name
}

output "lb_arn" {
  value = aws_alb.main.arn
}

output "lb_zone_id" {
  value = aws_alb.main.zone_id
}