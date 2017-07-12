# == Manifest: projects::app-docker_management
#
# Docker node from the 'management' VDC
#
# === Variables:
#
# aws_region
# remote_state_govuk_vpc_key
# remote_state_govuk_vpc_bucket
# stackname
#
# === Outputs:
#

variable "aws_region" {
  type        = "string"
  description = "AWS region"
  default     = "eu-west-1"
}

variable "remote_state_govuk_vpc_key" {
  type        = "string"
  description = "VPC TF remote state key"
}

variable "remote_state_govuk_vpc_bucket" {
  type        = "string"
  description = "VPC TF remote state bucket"
}

variable "remote_state_govuk_networking_key" {
  type        = "string"
  description = "VPC TF remote state key"
}

variable "remote_state_govuk_networking_bucket" {
  type        = "string"
  description = "VPC TF remote state bucket"
}

variable "remote_state_govuk_internal_dns_zone_key" {
  type        = "string"
  description = "VPC TF remote state key"
}

variable "remote_state_govuk_internal_dns_zone_bucket" {
  type        = "string"
  description = "VPC TF remote state bucket"
}

variable "remote_state_govuk_security_groups_key" {
  type        = "string"
  description = "VPC TF remote state key"
}

variable "remote_state_govuk_security_groups_bucket" {
  type        = "string"
  description = "VPC TF remote state bucket"
}

variable "stackname" {
  type        = "string"
  description = "Stackname"
}

variable "ssh_public_key" {
  type        = "string"
  description = "Default public key material"
}

# Resources
# --------------------------------------------------------------
terraform {
  backend          "s3"             {}
  required_version = "= 0.9.10"
}

provider "aws" {
  region = "${var.aws_region}"
}

data "terraform_remote_state" "govuk_vpc" {
  backend = "s3"

  config {
    bucket = "${var.remote_state_govuk_vpc_bucket}"
    key    = "${var.remote_state_govuk_vpc_key}"
    region = "eu-west-1"
  }
}

data "terraform_remote_state" "govuk_networking" {
  backend = "s3"

  config {
    bucket = "${var.remote_state_govuk_networking_bucket}"
    key    = "${var.remote_state_govuk_networking_key}"
    region = "eu-west-1"
  }
}

data "terraform_remote_state" "govuk_internal_dns_zone" {
  backend = "s3"

  config {
    bucket = "${var.remote_state_govuk_internal_dns_zone_bucket}"
    key    = "${var.remote_state_govuk_internal_dns_zone_key}"
    region = "eu-west-1"
  }
}

data "terraform_remote_state" "govuk_security_groups" {
  backend = "s3"

  config {
    bucket = "${var.remote_state_govuk_security_groups_bucket}"
    key    = "${var.remote_state_govuk_security_groups_key}"
    region = "eu-west-1"
  }
}

resource "aws_elb" "docker_management_etcd_elb" {
  name            = "${var.stackname}-docker-management-etcd"
  subnets         = ["${data.terraform_remote_state.govuk_networking.private_subnet_ids}"]
  security_groups = ["${data.terraform_remote_state.govuk_security_groups.sg_docker_management_etcd_elb_id}"]
  internal        = "true"

  listener {
    instance_port     = 2379
    instance_protocol = "tcp"
    lb_port           = 2379
    lb_protocol       = "tcp"
  }

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 3

    target   = "TCP:2379"
    interval = 30
  }

  cross_zone_load_balancing   = true
  idle_timeout                = 400
  connection_draining         = true
  connection_draining_timeout = 400

  tags = "${map("Name", "${var.stackname}-docker_management_etcd", "Project", var.stackname, "aws_migration", "docker_management_etcd")}"
}

resource "aws_route53_record" "docker_management_etcd_service_record" {
  zone_id = "${data.terraform_remote_state.govuk_internal_dns_zone.internal_service_zone_id}"
  name    = "etcd"
  type    = "A"

  alias {
    name                   = "${aws_elb.docker_management_etcd_elb.dns_name}"
    zone_id                = "${aws_elb.docker_management_etcd_elb.zone_id}"
    evaluate_target_health = true
  }
}

# TODO: Add external record when we have the external zones working

module "docker_management" {
  source                               = "../../modules/aws/node_group"
  name                                 = "${var.stackname}-docker_management"
  vpc_id                               = "${data.terraform_remote_state.govuk_vpc.vpc_id}"
  default_tags                         = "${map("Project", var.stackname, "aws_stackname", var.stackname, "aws_migration", "docker_management", "aws_hostname", "docker-management-1")}"
  instance_subnet_ids                  = "${data.terraform_remote_state.govuk_networking.private_subnet_ids}"
  instance_security_group_ids          = ["${data.terraform_remote_state.govuk_security_groups.sg_docker_management_id}", "${data.terraform_remote_state.govuk_security_groups.sg_management_id}"]
  instance_type                        = "t2.medium"
  create_instance_key                  = true
  instance_key_name                    = "${var.stackname}-docker_management"
  instance_public_key                  = "${var.ssh_public_key}"
  instance_additional_user_data_script = "${file("${path.module}/additional_user_data.txt")}"
  instance_elb_ids                     = ["${aws_elb.docker_management_etcd_elb.id}"]
}

# Outputs
# --------------------------------------------------------------

output "docker_management_etcd_elb_dns_name" {
  value       = "${aws_elb.docker_management_etcd_elb.dns_name}"
  description = "DNS name to access the docker_management service"
}

output "etcd_service_dns_name" {
  value       = "${aws_route53_record.docker_management_etcd_service_record.fqdn}"
  description = "DNS name to access the node service"
}