
module "monitoring-{{service_name}}" {
  count = var.monitoring_enabled ? 1 : 0
  source = "./monitoring"
  ecs_cluster_name = aws_ecs_cluster.app.name
  ecs_service_name = "{{service_name}}"
  alarms_sns_topic_arn = var.alarms_sns_topic_arn
  tags = var.tags
}

{% if environment_config.tcp_service %}
  
  module "service-{{service_name}}" {
    source = "../fargate-service-tcp"

    ecs_cluster = aws_ecs_cluster.app
    service_name = "{{service_name}}"
    region = var.region
    service_vpc = aws_vpc.vpc
    service_security_groups = [aws_security_group.ecs_service_sg.id]
    subnet_ids = var.public_subnets
    vpcCIDRblock = var.vpcCIDRblock

    {% if environment_config.internal is sameas True %}
      internal = true
    {% elif internal is sameas True %}
      internal = true
    {% else %}
      internal = false
    {% endif %}

    health_check = "{{health_check}}"
    {% if environment_config.health_check_interval %}
    health_check_interval = "{{environment_config.health_check_interval}}"
    {% endif %}

    container_port = "{{container_port}}"
    container_name = "{{app_name}}-{{environment}}-{{service_name}}"
    launch_type = "{{launch_type}}"

    default_backend_image = "quay.io/turner/turner-defaultbackend:0.2.0"
    {% if task_cpu %}task_cpu = "{{task_cpu}}" {% endif %}
    {% if task_memory %}task_memory = "{{task_memory}}" {% endif %}
  }


  output "{{service_name}}_docker_registry" {
    value = module.service-{{service_name}}.docker_registry
  }

  output "{{service_name}}_lb_dns" {
    value = module.service-{{service_name}}.lb_dns
  }

{% elif load_balancer %}
  module "service-{{service_name}}" {
    source = "../module-fargate-service"

    ecs_cluster = aws_ecs_cluster.app
    service_name = "{{service_name}}"
    region = var.region
    service_vpc = local.vpc
    service_security_groups = [aws_security_group.ecs_service_sg.id]
    subnet_ids = var.public_subnets

    {% if environment_config.internal is sameas True %}
      internal = true
    {% elif internal is sameas True %}
      internal = true
    {% else %}
      internal = false
    {% endif %}

    health_check = "{{health_check}}"

    {% if environment_config.health_check_disabled %}
    health_check_enabled = false
    {% endif %}

    {% if environment_config.health_check_grace_period_seconds %}
    health_check_grace_period_seconds = "{{environment_config.health_check_grace_period_seconds}}"
    {% endif %}

    {% if environment_config.lb_protocol %}
    lb_protocol = "{{environment_config.lb_protocol}}"
    {% endif %}

    {% if health_check_matcher %}
    health_check_matcher = "{{health_check_matcher}}"
    {% endif %}

    {% if environment_config.ecs_autoscale_min_instances %}
      ecs_autoscale_min_instances = "{{environment_config.ecs_autoscale_min_instances}}"
    {% endif %}

    {% if environment_config.ecs_autoscale_max_instances %}
      ecs_autoscale_max_instances = "{{environment_config.ecs_autoscale_max_instances}}"
    {% endif %}

    container_port = "{{container_port}}"
    container_name = "{{app_name}}-{{environment}}-{{service_name}}"
    launch_type = "{{launch_type}}"

    default_backend_image = "quay.io/turner/turner-defaultbackend:0.2.0"
    tags = var.tags

    {% if environment_config.lb_ssl_certificate_arn %}
      lb_ssl_certificate_arn = "{{environment_config.lb_ssl_certificate_arn}}"
    {% endif %}

    # for *.dggr.app listeners
    {% if environment_config.dggr_acm_certificate_arn %}
      dggr_acm_certificate_arn = "{{environment_config.dggr_acm_certificate_arn}}"
    {% endif %}

    {% if task_cpu %}task_cpu = "{{task_cpu}}" {% endif %}
    {% if task_memory %}task_memory = "{{task_memory}}" {% endif %}
  }


  {% if environment_config.create_dns_record %} 
    resource "aws_route53_record" "{{service_name}}_r53" {
      zone_id = "{{environment_config.dns_zone_id}}"
      name    = "{{environment}}-{{service_name}}.{{environment_config.hostname}}"
      type    = "A"

      alias {
        name                   = module.service-{{service_name}}.lb_dns
        zone_id                = module.service-{{service_name}}.lb_zone_id
        evaluate_target_health = false
      }
    }

    output "{{service_name}}_custom_domain" {
        value = aws_route53_record.{{service_name}}_r53.fqdn
    }

  {% endif %}


  # *.dggr.app domains
  {% if environment_config.use_dggr_domain %} 
    resource "aws_route53_record" "{{service_name}}_dggr_r53" {
      provider = aws.digger
      zone_id = "{{environment_config.dggr_zone_id}}"
      name    = "{{app_name}}-{{environment}}-{{service_name}}.{{environment_config.dggr_hostname}}"
      type    = "A"

      alias {
        name                   = module.service-{{service_name}}.lb_dns
        zone_id                = module.service-{{service_name}}.lb_zone_id
        evaluate_target_health = false
      }
    }

    output "{{service_name}}_dggr_domain" {
        value = aws_route53_record.{{service_name}}_dggr_r53.fqdn
    }
  {% endif %}

  output "{{service_name}}_docker_registry" {
    value = module.service-{{service_name}}.docker_registry
  }

  output "{{service_name}}_lb_dns" {
    value = module.service-{{service_name}}.lb_dns
  }

  output "{{service_name}}_lb_arn" {
    value = module.service-{{service_name}}.lb_arn
  }

  output "{{service_name}}_lb_http_listener_arn" {
    value = module.service-{{service_name}}.lb_http_listener_arn
  }

  output "{{service_name}}" {
    value = ""
  }
{% else %}
  module "service-{{service_name}}" {
    source = "../module-fargate-service-nolb"

    ecs_cluster = aws_ecs_cluster.app
    service_name = "{{service_name}}"
    region = var.region
    service_vpc = local.vpc
    subnet_ids = var.public_subnets
    internal = false
    container_name = "{{app_name}}-{{environment}}-{{service_name}}"
    launch_type = "{{launch_type}}"
    default_backend_image = "quay.io/turner/turner-defaultbackend:0.2.0"
    tags = var.tags
    {% if task_cpu %}
    task_cpu = "{{task_cpu}}"
    {% endif %}
    {% if task_memory %}
    task_memory = "{{task_memory}}"
    {% endif %}

    {% if environment_config.ecs_autoscale_min_instances %}
      ecs_autoscale_min_instances = "{{environment_config.ecs_autoscale_min_instances}}"
    {% endif %}

    {% if environment_config.ecs_autoscale_max_instances %}
      ecs_autoscale_max_instances = "{{environment_config.ecs_autoscale_max_instances}}"
    {% endif %}
  }

  output "{{service_name}}_docker_registry" {
    value = module.service-{{service_name}}.docker_registry
  }

  output "{{service_name}}_lb_dns" {
    value = ""
  }

{% endif %}

