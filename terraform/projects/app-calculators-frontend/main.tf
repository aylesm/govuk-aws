/**
* ## Project: app-calculators-frontend
*
* Calculators Frontend application servers
*/
variable "aws_region" {
  type        = "string"
  description = "AWS region"
  default     = "eu-west-1"
}

variable "stackname" {
  type        = "string"
  description = "Stackname"
}

variable "aws_environment" {
  type        = "string"
  description = "AWS Environment"
}

variable "instance_ami_filter_name" {
  type        = "string"
  description = "Name to use to find AMI images"
  default     = ""
}

variable "elb_internal_certname" {
  type        = "string"
  description = "The ACM cert domain name to find the ARN of"
}

variable "asg_size" {
  type        = "string"
  description = "The autoscaling groups desired/max/min capacity"
  default     = "10"
}

variable "app_service_records" {
  type        = "list"
  description = "List of application service names that get traffic via this loadbalancer"
  default     = []
}

variable "root_block_device_volume_size" {
  type        = "string"
  description = "The size of the instance root volume in gigabytes"
  default     = "60"
}

variable "instance_type" {
  type        = "string"
  description = "Instance type used for EC2 resources"
  default     = "c5.xlarge"
}

variable "enable_alb" {
  type        = "string"
  description = "Use application specific target groups and healthchecks based on the list of services in the cname variable."
  default     = false
}

variable "internal_zone_name" {
  type        = "string"
  description = "The name of the Route53 zone that contains internal records"
}

variable "internal_domain_name" {
  type        = "string"
  description = "The domain name of the internal DNS records, it could be different from the zone name"
}

# Resources
# --------------------------------------------------------------
terraform {
  backend          "s3"             {}
  required_version = "= 0.11.14"
}

data "aws_route53_zone" "internal" {
  name         = "${var.internal_zone_name}"
  private_zone = true
}

provider "aws" {
  region  = "${var.aws_region}"
  version = "2.46.0"
}

data "aws_acm_certificate" "elb_cert" {
  domain   = "${var.elb_internal_certname}"
  statuses = ["ISSUED"]
}

resource "aws_elb" "calculators-frontend_elb" {
  name            = "${var.stackname}-calculators-frontend"
  subnets         = ["${data.terraform_remote_state.infra_networking.private_subnet_ids}"]
  security_groups = ["${data.terraform_remote_state.infra_security_groups.sg_calculators-frontend_elb_id}"]
  internal        = "true"

  access_logs {
    bucket        = "${data.terraform_remote_state.infra_monitoring.aws_logging_bucket_id}"
    bucket_prefix = "elb/${var.stackname}-calculators-frontend-internal-elb"
    interval      = 60
  }

  listener {
    instance_port     = 80
    instance_protocol = "http"
    lb_port           = 443
    lb_protocol       = "https"

    ssl_certificate_id = "${data.aws_acm_certificate.elb_cert.arn}"
  }

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 3

    target   = "TCP:80"
    interval = 30
  }

  cross_zone_load_balancing   = true
  idle_timeout                = 400
  connection_draining         = true
  connection_draining_timeout = 400

  tags = "${map("Name", "${var.stackname}-calculators-frontend", "Project", var.stackname, "aws_environment", var.aws_environment, "aws_migration", "calculators_frontend")}"
}

resource "aws_route53_record" "service_record" {
  zone_id = "${data.aws_route53_zone.internal.zone_id}"
  name    = "calculators-frontend.${var.internal_domain_name}"
  type    = "A"

  alias {
    name                   = "${var.enable_alb ? module.internal_lb.lb_dns_name : aws_elb.calculators-frontend_elb.dns_name}"
    zone_id                = "${var.enable_alb ? module.internal_lb.lb_zone_id : aws_elb.calculators-frontend_elb.zone_id}"
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "app_service_records" {
  count   = "${length(var.app_service_records)}"
  zone_id = "${data.aws_route53_zone.internal.zone_id}"
  name    = "${element(var.app_service_records, count.index)}.${var.internal_domain_name}"
  type    = "CNAME"
  records = ["calculators-frontend.${var.internal_domain_name}."]
  ttl     = "300"
}

module "internal_lb" {
  source                                     = "../../modules/aws/lb"
  name                                       = "${var.stackname}-calculators-frontend-int"
  internal                                   = true
  vpc_id                                     = "${data.terraform_remote_state.infra_vpc.vpc_id}"
  access_logs_bucket_name                    = "${data.terraform_remote_state.infra_monitoring.aws_logging_bucket_id}"
  access_logs_bucket_prefix                  = "elb/${var.stackname}-calculators-frontend-internal-elb"
  listener_certificate_domain_name           = "${var.elb_internal_certname}"
  listener_secondary_certificate_domain_name = ""
  listener_action                            = "${map("HTTPS:443", "HTTP:80")}"
  subnets                                    = ["${data.terraform_remote_state.infra_networking.private_subnet_ids}"]
  security_groups                            = ["${data.terraform_remote_state.infra_security_groups.sg_calculators-frontend_elb_id}"]
  alarm_actions                              = ["${data.terraform_remote_state.infra_monitoring.sns_topic_cloudwatch_alarms_arn}"]
  default_tags                               = "${map("Project", var.stackname, "aws_environment", var.aws_environment, "aws_migration", "calculators_frontend")}"
}

module "internal_lb_rules" {
  source                 = "../../modules/aws/lb_listener_rules"
  name                   = "calculators-front-i"
  autoscaling_group_name = "${module.calculators-frontend.autoscaling_group_name}"
  rules_host_domain      = "*"
  vpc_id                 = "${data.terraform_remote_state.infra_vpc.vpc_id}"
  listener_arn           = "${module.internal_lb.load_balancer_ssl_listeners[0]}"
  rules_host             = ["${var.app_service_records}"]
  default_tags           = "${map("Project", var.stackname, "aws_migration", "calculators_frontend", "aws_environment", var.aws_environment)}"
}

module "calculators-frontend" {
  source                            = "../../modules/aws/node_group"
  name                              = "${var.stackname}-calculators-frontend"
  default_tags                      = "${map("Project", var.stackname, "aws_stackname", var.stackname, "aws_environment", var.aws_environment, "aws_migration", "calculators_frontend", "aws_hostname", "calculators-frontend-1")}"
  instance_subnet_ids               = "${data.terraform_remote_state.infra_networking.private_subnet_ids}"
  instance_security_group_ids       = ["${data.terraform_remote_state.infra_security_groups.sg_calculators-frontend_id}", "${data.terraform_remote_state.infra_security_groups.sg_management_id}"]
  instance_type                     = "${var.instance_type}"
  instance_additional_user_data     = "${join("\n", null_resource.user_data.*.triggers.snippet)}"
  instance_elb_ids_length           = "1"
  instance_elb_ids                  = ["${aws_elb.calculators-frontend_elb.id}"]
  instance_target_group_arns_length = "1"
  instance_target_group_arns        = ["${module.internal_lb.target_group_arns[0]}"]
  instance_ami_filter_name          = "${var.instance_ami_filter_name}"
  asg_max_size                      = "${var.asg_size}"
  asg_min_size                      = "${var.asg_size}"
  asg_desired_capacity              = "${var.asg_size}"
  asg_notification_topic_arn        = "${data.terraform_remote_state.infra_monitoring.sns_topic_autoscaling_group_events_arn}"
  root_block_device_volume_size     = "${var.root_block_device_volume_size}"
}

module "alarms-elb-calculators-frontend-internal" {
  source                         = "../../modules/aws/alarms/elb"
  name_prefix                    = "${var.stackname}-calculators-frontend-internal"
  alarm_actions                  = ["${data.terraform_remote_state.infra_monitoring.sns_topic_cloudwatch_alarms_arn}"]
  elb_name                       = "${aws_elb.calculators-frontend_elb.name}"
  httpcode_backend_4xx_threshold = "0"
  httpcode_backend_5xx_threshold = "50"
  httpcode_elb_4xx_threshold     = "0"
  httpcode_elb_5xx_threshold     = "50"
  surgequeuelength_threshold     = "0"
  healthyhostcount_threshold     = "0"
}

# Outputs
# --------------------------------------------------------------

output "calculators-frontend_elb_dns_name" {
  value       = "${aws_elb.calculators-frontend_elb.dns_name}"
  description = "DNS name to access the calculators-frontend service"
}

output "service_dns_name" {
  value       = "${aws_route53_record.service_record.name}"
  description = "DNS name to access the node service"
}
