# =============================================================================
#  modules/aws_webserver/main.tf
#  Provisions: VPC • IGW • Public Subnet • Route Table • Security Group
#              EC2 t2.micro (Ubuntu 22.04) • NGINX • Elastic IP
# =============================================================================

# ── Data: Availability Zones ──────────────────────────
data "aws_availability_zones" "available" {
  state = "available"
}

# ── VPC ───────────────────────────────────────────────
resource "aws_vpc" "main" {
  cidr_block           = "10.10.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = { Name = "${var.project_name}-vpc" }
}

# ── Internet Gateway ──────────────────────────────────
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.project_name}-igw" }
}

# ── Public Subnet ─────────────────────────────────────
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.10.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true
  tags                    = { Name = "${var.project_name}-public-subnet" }
}

# ── Route Table ───────────────────────────────────────
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = { Name = "${var.project_name}-rt-public" }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# ── Security Group ────────────────────────────────────
resource "aws_security_group" "web" {
  name        = "${var.project_name}-web-sg"
  description = "Allow HTTP, HTTPS, ICMP, SSH"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH (restrict to your IP in production)"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_cidr]
  }

  ingress {
    description = "ICMP Ping"
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-web-sg" }
}

# ── EC2 Instance ──────────────────────────────────────
resource "aws_instance" "web" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.web.id]
  key_name               = var.key_name

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 8
    delete_on_termination = true
    encrypted             = true
  }

  user_data = base64encode(templatefile("${path.module}/templates/userdata.sh.tpl", {
    cloud       = "AWS"
    region      = var.aws_region
    cloud_color = "#FF9900"
    text_color  = "#232F3E"
    bg_gradient = "linear-gradient(135deg,#FF9900,#232F3E)"
  }))

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"   # IMDSv2 enforced
    http_put_response_hop_limit = 1
  }

  monitoring = true

  tags = {
    Name  = "${var.project_name}-aws-web"
    Cloud = "AWS"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ── Elastic IP ────────────────────────────────────────
resource "aws_eip" "web" {
  instance = aws_instance.web.id
  domain   = "vpc"
  tags     = { Name = "${var.project_name}-eip" }

  depends_on = [aws_internet_gateway.igw]
}

# ── CloudWatch: CPU Alarm ─────────────────────────────
resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  alarm_name          = "${var.project_name}-aws-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 120
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "CPU utilization > 80%"

  dimensions = {
    InstanceId = aws_instance.web.id
  }
}
