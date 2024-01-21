##################################################################################
# PROVIDERS
##################################################################################

provider "aws" {
  region = var.region
}

##################################################################################
# LOCALS
##################################################################################

locals {

  common_tags = {
    Environment = var.environment
    BillingCode = var.billing_code
  }

  name_prefix = "${var.prefix}-${var.environment}"

}

##################################################################################
# RESOURCES
##################################################################################

resource "aws_iam_instance_profile" "main" {
  name = "${local.name_prefix}-webapp"
  role = var.ec2_role_name
  tags = local.common_tags
}

resource "aws_instance" "main" {
  count                = length(data.tfe_outputs.networking.nonsensitive_values.public_subnet)
  ami                  = nonsensitive(data.aws_ssm_parameter.amzn2_linux.value)
  iam_instance_profile = aws_iam_instance_profile.main.name
  instance_type        = var.instance_type
  subnet_id            = data.tfe_outputs.networking.nonsensitive_values.public_subnet[count.index]
  vpc_security_group_ids = [
    aws_security_group.webapp_http_inbound_sg.id,
    aws_security_group.webapp_ssh_inbound_sg.id,
    aws_security_group.webapp_outbound_sg.id,
  ]

  key_name = module.ssh_keys.key_pair_name

  tags = merge(local.common_tags, {
    "Name" = "${local.name_prefix}-webapp-${count.index}"
  })


  user_data_replace_on_change = true

  user_data = templatefile("./templates/userdata.sh", {
    playbook_repository = var.playbook_repository
    secret_id           = var.api_key_secret_id
    host_list_ssm_name  = local.host_list_ssm_name
    site_name_ssm_name  = local.site_name_ssm_name
  })

  /*
  # Provisioner Stuff
  connection {
    type        = "ssh"
    user        = "ec2-user"
    port        = "22"
    host        = self.public_ip
    private_key = module.ssh_keys.private_key_openssh
  }

  provisioner "file" {
    source      = "./templates/userdata.sh"
    destination = "/home/ec2-user/userdata.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /home/ec2-user/userdata.sh",
      "sh /home/ec2-user/userdata.sh",
    ]
    on_failure = continue
  }
*/
}

/*
resource "terraform_data" "webapp" {
  triggers_replace = [
    length(aws_instance.main.*.id),
    join(",", aws_instance.main.*.id)
  ]
  provisioner "file" {
    content = templatefile("./templates/application.config.tpl", {
      hosts     = aws_instance.main.*.private_dns
      site_name = "${local.name_prefix}-taco-wagon"
      api_key   = var.api_key
    })
    destination = "/home/ec2-user/application.config"
  }
  connection {
    type        = "ssh"
    user        = "ec2-user"
    port        = "22"
    host        = aws_instance.main[0].public_ip
    private_key = module.ssh_keys.private_key_openssh
  }
}
*/

resource "aws_lb" "main" {
  name               = "${local.name_prefix}-webapp"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.webapp_http_inbound_sg.id]
  subnets            = data.tfe_outputs.networking.nonsensitive_values.public_subnet

  enable_deletion_protection = false

  tags = local.common_tags
}

resource "aws_lb_listener" "main" {
  load_balancer_arn = aws_lb.main.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.main.arn
  }
}

resource "aws_lb_target_group" "main" {
  name        = "${local.name_prefix}-webapp"
  port        = 80
  target_type = "instance"
  protocol    = "HTTP"
  vpc_id      = data.tfe_outputs.networking.nonsensitive_values.vpc_id
}

resource "aws_alb_target_group_attachment" "main" {
  count            = length(aws_instance.main.*.id)
  target_group_arn = aws_lb_target_group.main.arn
  target_id        = aws_instance.main[count.index].id
}