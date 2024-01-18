##################################################################################
# DATA SOURCES
##################################################################################

data "aws_ssm_parameter" "amzn2_linux" {
  name = "/aws/service/ami-amazon-linux-latest/amzn2-ami-hvm-x86_64-gp2"
}

data "tfe_outputs" "networking" {
  organization = var.tfe_organization
  workspace    = var.tfe_workspace_name
}