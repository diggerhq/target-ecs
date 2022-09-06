# note that this creates the alb, target group, and access logs
# the listeners are defined in lb-http.tf and lb-https.tf
# delete either of these if your app doesn't need them
# but you need at least one


data aws_alb "main" {
  arn = var.alb_arn
}

resource "aws_alb_target_group" "main" {
  name                 = var.service_name
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

data "aws_lb_listener" "listener" {
  arn = var.listener_arn
}

resource "aws_lb_listener_rule" "static" {
  listener_arn = data.aws_lb_listener.listener.arn
  priority     = 99

  action {
    type             = "forward"
    target_group_arn = aws_alb_target_group.main.arn
  }

  condition {
    path_pattern {
      values = [var.listener_rule_path]
    }
  }
}

# The load balancer DNS name
output "lb_dns" {
  value = data.aws_alb.main.dns_name
}

output "lb_arn" {
  value = data.aws_alb.main.arn
}

output "lb_zone_id" {
  value = data.aws_alb.main.zone_id
}