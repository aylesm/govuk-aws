## Module: projects/infra-dev_vm

Creates an S3 bucket to store the development VMs used in govuk-puppet
Vagrantfile

Mifrated from:
https://github.com/alphagov/govuk-terraform-provisioning/tree/master/old-projects/dev_vm


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|:----:|:-----:|:-----:|
| aws_environment | AWS Environment | string | - | yes |
| aws_region | AWS region | string | `eu-west-1` | no |
| bucket_name |  | string | `govuk-dev-boxes` | no |
| stackname | Stackname | string | `` | no |
| team |  | string | `Infrastructure` | no |
| username |  | string | `govuk-dev-box-uploader` | no |
