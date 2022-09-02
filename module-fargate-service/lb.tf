# note that this creates the alb, target group, and access logs
# the listeners are defined in lb-http.tf and lb-https.tf
# delete either of these if your app doesn't need them
# but you need at least one


data "aws_alb" "main" {
  arn = var.alb_arn
}

resource "aws_alb" "main" {
  count = var.alb_arn == "" ? 0 : 1
  name = var.service_name

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

locals {
  alb = var.alb_arn == "" ? aws_alb.main[0] : data.aws_alb.main
}
resource "aws_alb_target_group" "main" {
  name                 = "${var.service_name}"
  port                 = var.lb_port
  protocol             = var.lb_protocol
  vpc_id               = var.service_vpc.id
  target_type          = "ip"
  deregistration_delay = var.deregistration_delay

  health_check {
    enabled             = var.health_check_enabled
    path                = var.health_check
    matcher             = var.health_check_matcher
    protocol            = var.lb_protocol
    interval            = var.health_check_interval
    timeout             = var.health_check_timeout
    healthy_threshold   = 5
    unhealthy_threshold = 5
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = var.tags
}

data "aws_elb_service_account" "main" {
}

# bucket for storing ALB access logs
resource "aws_s3_bucket" "lb_access_logs" {
  bucket_prefix = "${var.service_name}"
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
      days = var.lb_access_logs_expiration_days
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
  value = local.alb.dns_name
}

output "lb_arn" {
  value = local.alb.arn
}

output "lb_http_listener_arn" {
  value = try(aws_alb_listener.http.arn, null)
}

output "lb_zone_id" {
  value = local.alb.zone_id
}