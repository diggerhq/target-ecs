aws_key = "{{aws_key}}"
aws_secret = "{{aws_secret}}"
digger_aws_key = "{{digger_aws_key}}"
digger_aws_secret = "{{digger_aws_secret}}"
app = "{{app_name}}"

aws_app_identifier = "{{aws_app_identifier}}"
# ecs derived name (doing checks for backward compatability)
ecs_cluster_name = "{{aws_app_identifier}}"

region = "{{region}}"

alarms_sns_topic_arn = "{{alarms_sns_topic_arn}}"
monitoring_enabled = {{monitoring_enabled | lower}}

# aws_profile = "default"
# container_port = "{{container_port}}"
# replicas = "1"
# health_check = "{{health_check}}"
tags = {
  application   = "{{app_name}}"
  team          = "{{app_name}}-team"
  customer      = "{{app_name}}-customer"
  contact-email = "me@domain.com"
}

public_subnets = {{public_subnets}}
private_subnets = {{private_subnets}}
