/**
 * Elastic Container Service (ecs)
 * This component is required to create the ECS service. It will create a cluster
 * based on the application name and enironment. It will create a "Task Definition", which is required
 * to run a Docker container, https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task_definitions.html.
 * Next it creates a ECS Service, https://docs.aws.amazon.com/AmazonECS/latest/developerguide/ecs_services.html
 * It attaches the Load Balancer created in `lb.tf` to the service, and sets up the networking required.
 * It also creates a role with the correct permissions. And lastly, ensures that logs are captured in CloudWatch.
 *
 * When building for the first time, it will install a "default backend", which is a simple web service that just
 * responds with a HTTP 200 OK. It's important to uncomment the lines noted below after you have successfully
 * migrated the real application containers to the task definition.
 */

locals {
  awsloggroup = "/ecs/service/${var.service_name}"
}

resource "aws_appautoscaling_target" "app_scale_target" {
  service_namespace  = "ecs"
  resource_id        = "service/${var.ecs_cluster.name}/${aws_ecs_service.app.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  max_capacity       = var.ecs_autoscale_max_instances
  min_capacity       = var.ecs_autoscale_min_instances
}

resource "aws_ecs_task_definition" "app" {
  family                   = var.container_name
  requires_compatibilities = [var.launch_type]
  network_mode             = "awsvpc"
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = aws_iam_role.ecsTaskExecutionRole.arn

  # defined in role.tf
  # task_role_arn = aws_iam_role.app_role.arn

  container_definitions = <<EOT
[
  {
    "name": "${var.container_name}",
    "image": "${var.default_backend_image}",
    "essential": true,
    "portMappings": [
      {
        "protocol": "tcp",
        "containerPort": ${var.container_port},
        "hostPort": ${var.container_port}
      }
    ],
    "environment": [
      {
        "name": "PORT",
        "value": "${var.container_port}"
      },
      {
        "name": "HEALTHCHECK",
        "value": "${var.health_check}"
      }
    ],
    "logConfiguration": {

%{ if var.datadog_logs_enabled }
      "logDriver": "awsfirelens",
      "options": {
        "Name": "datadog",
        "compress": "gzip",
        "Host": "${var.datadog_logs_host}",
        "TLS": "on",
        "dd_service": "${var.ecs_cluster.name}",
        "dd_source": "httpd",
        "provider": "ecs",
        "retry_limit": "2",
        "net.keepalive": "false"
    },
    "secretOptions": [{
      "name": "apikey",
      "valueFrom": "${var.datadog_key_ssm_arn}"
    }]
%{ else }
      "logDriver": "awslogs",
      "options": {
        "awslogs-group": "${local.awsloggroup}",
        "awslogs-region": "${var.region}",
        "awslogs-stream-prefix": "ecs"
      }
%{ endif }
    },
    "mountPoints": [
    %{for mountPoint in var.mountPoints}
      {
        "containerPath": "${mountPoint.path}",
        "sourceVolume": "${mountPoint.volume}"
      }
    %{endfor}
    ]
  }
%{ if var.datadog_logs_enabled }
  ,
  {
    "essential": true,
    "image": "amazon/aws-for-fluent-bit:stable",
    "name": "log_router",
    "firelensConfiguration": {
	    "type": "fluentbit",
	    "options": {
		    "enable-ecs-log-metadata": "true"
	    }
    },
    "logConfiguration": {
      "logDriver" : "awslogs",
      "options" : {
        "awslogs-group" : "${local.awsloggroup}",
        "awslogs-region" : "${var.region}",
        "awslogs-stream-prefix" : "fluentbit"
      }
    }
  }
%{ endif }
%{ if var.datadog_metrics_enabled }
  ,
  {
    "essential": true,
    "name": "datadog_agent",
    "image": "public.ecr.aws/datadog/agent:latest",
    "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
            "awslogs-group": "${local.awsloggroup}",
            "awslogs-region": "${var.region}",
            "awslogs-stream-prefix": "ddagent"
        }
    },
    "environment": [
        {
            "name": "ECS_FARGATE",
            "value": "true"
        },
        {
            "name": "DD_PROCESS_AGENT_ENABLED",
            "value": "true"
        },
        {
            "name": "DD_SITE",
            "value": "${var.datadog_site}"
        }
    ],
    "secrets": [
        {
            "name": "DD_API_KEY",
            "valueFrom": "${var.datadog_key_ssm_arn}"
        }
    ]
}
%{ endif }
]
EOT

  dynamic "volume" {
    for_each = var.volumes
    content {
      name = volume.value.name

      efs_volume_configuration {
        file_system_id     = volume.value.file_system_id
        root_directory     = "/"
        transit_encryption = "ENABLED"
      }
    }
  }

  tags = var.tags
}

resource "aws_ecs_service" "app" {
  name                              = var.service_name
  cluster                           = var.ecs_cluster.id
  launch_type                       = var.launch_type
  task_definition                   = aws_ecs_task_definition.app.arn
  desired_count                     = var.ecs_autoscale_min_instances
  health_check_grace_period_seconds = var.health_check_grace_period_seconds

  network_configuration {
    security_groups  = concat([aws_security_group.nsg_task.id], var.service_security_groups)
    subnets          = var.subnet_ids
    assign_public_ip = true
    # subnets         = split(",", var.private_subnets)
  }

  load_balancer {
    target_group_arn = aws_alb_target_group.main.id
    container_name   = var.container_name
    container_port   = var.container_port
  }

  # requires manual opt-in
  # tags                    = var.tags
  # enable_ecs_managed_tags = true
  # propagate_tags          = "SERVICE"

  # workaround for https://github.com/hashicorp/terraform/issues/12634
  depends_on = [aws_alb_listener.http]

  # [after initial apply] don't override changes made to task_definition
  # from outside of terraform (i.e.; fargate cli)
  lifecycle {
    ignore_changes = [task_definition]
  }
}

# https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task_execution_IAM_role.html
resource "aws_iam_role" "ecsTaskExecutionRole" {
  name               = "${var.ecs_cluster.name}-${var.service_name}-ecs"
  assume_role_policy = data.aws_iam_policy_document.assume_role_policy.json
}

data "aws_iam_policy_document" "assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy_attachment" "ecsTaskExecutionRole_policy" {
  role       = aws_iam_role.ecsTaskExecutionRole.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# provide access to read SSM secrets
resource "aws_iam_role_policy_attachment" "ecsTaskExecutionRole_ssm_policy" {
  role       = aws_iam_role.ecsTaskExecutionRole.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMReadOnlyAccess"
}


resource "aws_cloudwatch_log_group" "logs" {
  name              = local.awsloggroup
  retention_in_days = var.logs_retention_in_days
  tags              = var.tags
}
