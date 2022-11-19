terraform {
  required_version = ">= 0.13.1"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 3.73"
    }
  }
}

locals {
  images = {
    us-east-1      = "ami-037ff6453f0855c46"
    eu-central-1   = "ami-0764964fdfe99bc31"
    ap-northeast-1 = "ami-04f47c2ec43830d77"
  }
}
################################################################################
# VPC
################################################################################

resource "aws_vpc" "myvpc" {
  count = var.create_vpc ? 1 : 0

  cidr_block          = var.use_ipam_pool ? null : var.cidr
  ipv4_ipam_pool_id   = var.ipv4_ipam_pool_id
  ipv4_netmask_length = var.ipv4_netmask_length

  assign_generated_ipv6_cidr_block = var.enable_ipv6
  ipv6_cidr_block                  = var.ipv6_cidr
  ipv6_ipam_pool_id                = var.ipv6_ipam_pool_id
  ipv6_netmask_length              = var.ipv6_netmask_length

  instance_tenancy               = var.instance_tenancy
  enable_dns_hostnames           = var.enable_dns_hostnames
  enable_dns_support             = var.enable_dns_support
  enable_classiclink             = null 
  enable_classiclink_dns_support = null

  tags = {
    Name = "Network-Prod-E1-VPC001"
  }
}

################################################################################
# MyPublic Subnet
################################################################################

resource "aws_subnet" "MyPublicSubnet" {
  count = var.create_vpc ? length(var.public_subnets) : 0
  vpc_id     = aws_vpc.myvpc[0].id
  cidr_block = element(var.public_subnets,count.index)
  availability_zone               = length(regexall("^[a-z]{2}-", element(var.azs, count.index))) > 0 ? element(var.azs, count.index) : null
  map_public_ip_on_launch         = var.map_public_ip_on_launch
  assign_ipv6_address_on_creation = var.assign_ipv6_address_on_creation
  ipv6_cidr_block = var.enable_ipv6 && length(var.public_subnet_ipv6_prefixes) > 0 ? cidrsubnet(aws_vpc.myvpc[0].ipv6_cidr_block, 8, var.public_subnet_ipv6_prefixes[count.index]) : null
  tags = {
    Name = "Network-Prod-E1-Public-SNET00${count.index +1}"
  }
}

################################################################################
# MyPrivate Subnet
################################################################################

resource "aws_subnet" "MyPrivateSubnet" {
  count = var.create_vpc ? length(var.private_subnets) : 0
  vpc_id     = aws_vpc.myvpc[0].id
  cidr_block = element(var.private_subnets,count.index)
  availability_zone               = length(regexall("^[a-z]{2}-", element(var.azs, count.index))) > 0 ? element(var.azs, count.index) : null
  assign_ipv6_address_on_creation = var.assign_ipv6_address_on_creation
  ipv6_cidr_block = var.enable_ipv6 && length(var.private_subnet_ipv6_prefixes) > 0 ? cidrsubnet(aws_vpc.myvpc[0].ipv6_cidr_block, 8, var.private_subnet_ipv6_prefixes[count.index]) : null
  tags = {
    Name =  "Network-Prod-E1-Private-SNET00${count.index +1}"
  }
}

################################################################################
# Internet Gateway Creation
################################################################################

resource "aws_internet_gateway" "MyIGW" {
  count = var.create_vpc && var.create_igw && length(var.public_subnets) > 0 ? 1 : 0
  vpc_id = aws_vpc.myvpc[0].id

  tags = {
    Name = "Network-Prod-E1-IGW001" 
  }
  
}

################################################################################
# NatGateway
################################################################################

resource "aws_eip" "MyEIP" {
vpc = true
tags = {
  Name ="Network-Prod-E1-NGW001" 
  }
}

resource "aws_nat_gateway" "MyNat" {
allocation_id = aws_eip.MyEIP.id
subnet_id = aws_subnet.MyPublicSubnet[0].id
tags = {
  Name ="Network-Prod-E1-NGW001" }
depends_on = [aws_internet_gateway.MyIGW]
}
################################################################################
# Default Route Table
################################################################################
resource "aws_route_table" "DefaultRT" {
  count = var.create_vpc && length(var.public_subnets) > 0 ? 1 : 0

  vpc_id = aws_vpc.myvpc[0].id

  tags = {
    Name = "Network-Prod-E1-Public-RT001" }
}
################################################################################
# Private Route Table
################################################################################
resource "aws_route_table" "PrivateRT" {
  count = var.create_vpc && length(var.private_subnets) > 0 ? 1 : 0

  vpc_id = aws_vpc.myvpc[0].id

  tags = {
    Name = "Network-Prod-E1-Private-RT001" }
}
################################################################################
# Adding Routes to the Route Tables
################################################################################
resource "aws_route" "public_internet_gateway" {
  count = var.create_vpc && var.create_igw && length(var.public_subnets) > 0 ? 1 : 0

  route_table_id         = aws_route_table.DefaultRT[0].id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.MyIGW[0].id
}

resource "aws_route" "nat_gateway" {
  route_table_id         = aws_route_table.PrivateRT[0].id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_nat_gateway.MyNat.id
}

resource "aws_route_table_association" "public_subnet_asso" {
 count = length(var.public_subnets)
 subnet_id      = element(aws_subnet.MyPublicSubnet[*].id, count.index)
 route_table_id = aws_route_table.DefaultRT[0].id
}

resource "aws_route_table_association" "private_subnet_asso" {
 count = length(var.private_subnets)
 subnet_id      = element(aws_subnet.MyPrivateSubnet[*].id, count.index)
 route_table_id = aws_route_table.PrivateRT[0].id
}
################################################################################
# Enabling VPC Flow Logs
################################################################################

resource "aws_flow_log" "flowlogs" {
  iam_role_arn    = aws_iam_role.vpc_flow_logs.arn
  log_destination = aws_cloudwatch_log_group.loggroup.arn
  traffic_type    = "ALL"
  vpc_id          = aws_vpc.myvpc[0].id
}

resource "aws_cloudwatch_log_group" "loggroup" {
  name = "Network-Prod-E1-CW001"
}

resource "aws_iam_role" "vpc_flow_logs" {
  name = "Network-Prod-E1-FlowLogs-IAM001"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "",
      "Effect": "Allow",
      "Principal": {
        "Service": "vpc-flow-logs.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "log_group_permission" {
  name = "log_group_permission"
  role = aws_iam_role.vpc_flow_logs.id

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams"
      ],
      "Effect": "Allow",
      "Resource": "*"
    }
  ]
}
EOF
}

################################################################################
# Creating VPN Server (OpenVPN)
################################################################################

resource "aws_instance" "openvpn" {
  ami                    = local.images[var.server_region]
  instance_type          = "t2.micro"
  vpc_security_group_ids = [aws_security_group.instance.id]
  subnet_id = aws_subnet.MyPublicSubnet[0].id

  user_data = <<-EOF
              admin_user=${var.server_username}
              admin_pw=${var.server_password}
              EOF

  tags = {
    Name = "Network-Prod-E1-VPN001"
  }
}
resource "aws_security_group" "instance" {
  name        = "Network-Prod-E1-SG001"
  description = "OpenVPN security group"
  vpc_id = aws_vpc.myvpc[0].id
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 943
    to_port     = 943
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 945
    to_port     = 945
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 1194
    to_port     = 1194
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "Network-Prod-E1-SGVPN001"
  }
}

output "access_vpn_url" {
  value       = "https://${aws_instance.openvpn.public_ip}:943/admin"
  description = "The public url of the vpn server"
}

################################################################################
# Creating Transit Gateway
################################################################################
resource "aws_ec2_transit_gateway" "network-transit" {
  description = "network-transit"
  tags = {
    Name = "Network-Prod-E1-TG001"
  }
}

################################################################################
# Creating Reachability Analyzer
################################################################################

resource "aws_ec2_network_insights_path" "test" {
  source      = aws_instance.openvpn.id
  destination = aws_internet_gateway.MyIGW[0].id
  protocol    = "tcp"
  tags = {
    Name = "Network-Prod-E1-RA001"
  }
}

################################################################################
# Creating NetworkACL
################################################################################
resource "aws_default_network_acl" "default" {
  default_network_acl_id = aws_vpc.myvpc[0].default_network_acl_id

  ingress {
    protocol   = -1
    rule_no    = 100
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }

  egress {
    protocol   = -1
    rule_no    = 100
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }
  tags = {
    Name = "Network-Prod-E1-NACL001"
  }
}
################################################################################
# Creating Security Group
################################################################################
resource "aws_default_security_group" "default" {
  vpc_id = aws_vpc.myvpc[0].id

  ingress {
    protocol  = -1
    self      = true
    from_port = 0
    to_port   = 0
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "Network-Prod-E1-SG001"
}
}
################################################################################
# Creating Route 53 Hosted Zone
################################################################################
resource "aws_route53_zone" "main" {
  name = "flinkaws.com"
  tags = {
    Name = "Network-Prod-E1-Route001"
}
}
