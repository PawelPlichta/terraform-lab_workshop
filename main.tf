terraform {
  required_version = ">= 1.0"
  backend "s3" {}
}

provider "aws" {
  region = var.region
}

data "aws_ami" "debian" {
  owners      = ["136693071363"]
  most_recent = true

  filter {
    name   = "name"
    values = ["debian-11-amd64-*"]
  }
  filter {
    name   = "state"
    values = ["available"]
  }
}


module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "3.11.0"

  name = "eMASE"
  cidr = "10.0.0.0/16"

  azs             = ["eu-west-1a", "eu-west-1b", "eu-west-1c"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

  enable_nat_gateway = true
  single_nat_gateway = true
  enable_ipv6        = false
}

resource "aws_security_group" "lb_public_access" {
  name   = "lb-public-access"
  vpc_id = module.vpc.vpc_id

  ingress {
    from_port = 80
    to_port   = 80
    protocol  = "tcp"
    cidr_blocks = [
      "0.0.0.0/0"
    ]
  }

  egress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = module.vpc.private_subnets_cidr_blocks
  }
}


resource "aws_security_group" "lb_ec2_access" {
  name = "lb-ec2-access"
  #name = "Ec2SecurityGroup"
  vpc_id      = module.vpc.vpc_id
  description = "Security group for EC2 instance"

  ingress {
    from_port = 80
    to_port   = 80
    protocol  = "tcp"
    security_groups = [
      aws_security_group.lb_public_access.id
    ]
  }

  egress {
    from_port = 80
    to_port   = 80
    protocol  = "tcp"
    cidr_blocks = [
      "0.0.0.0/0"
    ]
  }

}

resource "aws_instance" "app" {
  count = var.instances_per_subnet * length(module.vpc.private_subnets)
  #count = 0
  #ami           = var.ami_id
  ami           = var.ami_id != "" ? var.ami_id : data.aws_ami.debian.id

  instance_type = "t2.micro"
  subnet_id     = module.vpc.private_subnets[count.index % length(module.vpc.private_subnets)]

  vpc_security_group_ids = [
    aws_security_group.lb_ec2_access.id
  ]
  associate_public_ip_address = false

  user_data = <<-EOF
    #!/bin/sh
    apt-get update
    apt-get install -y nginx-light
    echo 'Hello from instance app-${count.index}' > /var/www/html/index.html
  EOF

  tags = {
    "Name" = "app-${count.index}"
  }

depends_on = [
    module.vpc.natgw_ids
  ]

  lifecycle {
    ignore_changes = [
      ami
    ]
  }
}


resource "aws_lb" "app" {
  name               = "app"
  internal           = false
  load_balancer_type = "application"
  enable_http2       = true
  ip_address_type    = "ipv4"
  security_groups = [
    aws_security_group.lb_public_access.id
  ]
  subnets = module.vpc.public_subnets
}

resource "aws_lb_target_group" "app" {
  name     = "app"
  port     = 80
  protocol = "HTTP"
  vpc_id   = module.vpc.vpc_id

  health_check {
    healthy_threshold   = 3
    unhealthy_threshold = 10
    timeout             = 5
    interval            = 10
    path                = "/"
    port                = "80"
  }
}


resource "aws_lb_target_group_attachment" "app" {
  count            = length(aws_instance.app)
  target_group_arn = aws_lb_target_group.app.arn
  target_id        = aws_instance.app[count.index].id
}


resource "aws_lb_listener" "app-http" {
  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}
