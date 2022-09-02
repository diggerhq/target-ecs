# Tags for the infrastructure
variable "tags" {
  type = map(string)
}


variable "subnet_ids" {}

variable "alb_name" {}

variable "internal" {}

variable "vpc_id" {}

variable "security_group_name" {}

variable "access_logs_expiration_days" {
  default = "3"
}