variable "instance_type" {
  description = "EC2 Instance Type"
}

# 1. VPC (CIDR Block 172.16.1.0/16) with Internet Gateway
resource "aws_vpc" "main" {
  cidr_block           = "172.16.0.0/16"
  enable_dns_hostnames = true
  tags                 = { Name = "main-vpc" }
}

# 2. Subnets (Public & Private) in Two Availability Zones
resource "aws_subnet" "public_subnet_1" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "172.16.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "ap-south-1a"
  tags                    = { Name = "public-subnet-1" }
}

resource "aws_subnet" "public_subnet_2" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "172.16.2.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "ap-south-1b"
  tags                    = { Name = "public-subnet-2" }
}

resource "aws_subnet" "private_subnet_1" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "172.16.3.0/24"
  availability_zone = "ap-south-1a"
  tags              = { Name = "private-subnet-1" }
}

resource "aws_subnet" "private_subnet_2" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "172.16.4.0/24"
  availability_zone = "ap-south-1b"
  tags              = { Name = "private-subnet-2" }
}

# 3. Internet Gateway (IGW) for internet access
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "main-igw" }
}

# 4. NAT Gateways for Public Subnets
resource "aws_eip" "nat_eip_1" {
  domain = "vpc"
  tags = {
    Name = "nat-eip-1"
  }
}

resource "aws_nat_gateway" "nat_1" {
  allocation_id = aws_eip.nat_eip_1.id
  subnet_id     = aws_subnet.public_subnet_1.id
  tags          = { Name = "nat-gateway-1" }
}

resource "aws_eip" "nat_eip_2" {
  domain = "vpc"

  tags = {
    Name = "nat-eip-2"
  }
}

resource "aws_nat_gateway" "nat_2" {
  allocation_id = aws_eip.nat_eip_2.id
  subnet_id     = aws_subnet.public_subnet_2.id
  tags          = { Name = "nat-gateway-2" }
}

# 5. Route Tables
resource "aws_route_table" "public_rt_1" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = { Name = "public-rt-1" }
}

resource "aws_route_table_association" "public_assoc_1" {
  subnet_id      = aws_subnet.public_subnet_1.id
  route_table_id = aws_route_table.public_rt_1.id
}

resource "aws_route_table" "public_rt_2" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = { Name = "public-rt-2" }
}

resource "aws_route_table_association" "public_assoc_2" {
  subnet_id      = aws_subnet.public_subnet_2.id
  route_table_id = aws_route_table.public_rt_2.id
}

resource "aws_route_table" "private_rt_1" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_1.id
  }
  tags = { Name = "private-rt-1" }
}

resource "aws_route_table_association" "private_assoc_1" {
  subnet_id      = aws_subnet.private_subnet_1.id
  route_table_id = aws_route_table.private_rt_1.id
}

resource "aws_route_table" "private_rt_2" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_2.id
  }
  tags = { Name = "private-rt-2" }
}

resource "aws_route_table_association" "private_assoc_2" {
  subnet_id      = aws_subnet.private_subnet_2.id
  route_table_id = aws_route_table.private_rt_2.id
}

# 6. Security Groups (Allow SSH and HTTP)
resource "aws_security_group" "ec2_sg" {
  name   = "ec2-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Open for SSH Port-Forwarding
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "ec2-sg" }
}

resource "aws_security_group" "db_sg" {
  name        = "db-sg"
  description = "Allow DB traffic"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["172.16.0.0/16"] # Adjust to match your app subnet or CIDR
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "db-sg"
  }
}

# 7. EC2 Instance (SSM Host) for Developer SSH Port Forward Access
resource "aws_instance" "ssm_host1" {
  ami                         = "ami-03bb6d83c60fc5f7c" # Amazon Linux 2 in Mumbai
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.public_subnet_1.id
  vpc_security_group_ids      = [aws_security_group.ec2_sg.id]
  associate_public_ip_address = true

  tags = { Name = "ssm-host1" }
}

# 8. EC2 Instance (Server) in Private Subnet
resource "aws_instance" "app_server1" {
  ami                    = "ami-03bb6d83c60fc5f7c" # Amazon Linux 2 in Mumbai
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.private_subnet_2.id
  vpc_security_group_ids = [aws_security_group.ec2_sg.id]

  tags = { Name = "app-server1" }
}

# 9. RDS MariaDB (Master & Replica) in Private Subnet
resource "aws_db_subnet_group" "rds_subnet" {
  name       = "rds-subnet"
  subnet_ids = [aws_subnet.private_subnet_1.id, aws_subnet.private_subnet_2.id]
  tags       = { Name = "rds-subnet-group" }
}

resource "aws_db_instance" "rds_master" {
  identifier              = "mariadb-master"
  engine                  = "mariadb"
  instance_class          = "db.t3.micro"
  username                = "admin"
  password                = "password123"
  allocated_storage       = 20
  db_subnet_group_name    = aws_db_subnet_group.rds_subnet.name
  vpc_security_group_ids  = [aws_security_group.db_sg.id]
  skip_final_snapshot     = true
  publicly_accessible     = false
  multi_az                = false
  backup_retention_period = 1 # ✅ Required for replicas

  tags = {
    Name = "rds-master"
  }
}

resource "aws_db_instance" "rds_replica" {
  identifier           = "mariadb-replica"
  engine               = "mariadb"
  instance_class       = "db.t3.micro"
  replicate_source_db  = aws_db_instance.rds_master.arn # ✅ ARN is required
  db_subnet_group_name = aws_db_subnet_group.rds_subnet.name
  publicly_accessible  = false
  skip_final_snapshot  = true

  tags = { Name = "rds-replica" }

  depends_on = [aws_db_instance.rds_master] # Recommended
}

# 10. Auto Scaling Group (ASG) with Public NLB & CloudFront
resource "aws_lb" "nlb" {
  name               = "app-nlb"
  internal           = false
  load_balancer_type = "network"
  security_groups    = [aws_security_group.ec2_sg.id]
  subnets            = [aws_subnet.public_subnet_1.id, aws_subnet.public_subnet_2.id]

  enable_deletion_protection = false
  tags                       = { Name = "app-nlb" }
}

resource "aws_lb_target_group" "nlb_target" {
  name     = "app-target-group"
  port     = 80
  protocol = "TCP"
  vpc_id   = aws_vpc.main.id

  health_check {
    port     = "traffic-port"
    protocol = "TCP"
  }
}

resource "aws_lb_listener" "nlb_listener" {
  load_balancer_arn = aws_lb.nlb.arn
  port              = "80"
  protocol          = "TCP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.nlb_target.arn
  }
}

resource "aws_s3_bucket" "web_bucket" {
  bucket = "my-web-static-bucket-123456" # Must be globally unique
  tags = {
    Name = "Web Hosting Bucket"
  }
}

resource "aws_s3_bucket_ownership_controls" "web_bucket_ownership" {
  bucket = aws_s3_bucket.web_bucket.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_cloudfront_origin_access_identity" "oai" {
  comment = "OAI for CloudFront to access S3"
}

resource "aws_cloudfront_distribution" "cdn" {
  origin {
    domain_name = aws_s3_bucket.web_bucket.bucket_regional_domain_name
    origin_id   = "s3Origin"

    s3_origin_config {
      origin_access_identity = "origin-access-identity/cloudfront/${aws_cloudfront_origin_access_identity.oai.id}"
    }
  }

  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"

  default_cache_behavior {
    target_origin_id       = "s3Origin"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  depends_on = [aws_cloudfront_origin_access_identity.oai]
}

# 11. SSM VPC Endpoint for Port Forwarding Access
resource "aws_vpc_endpoint" "ssm" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.ap-south-1.ssm"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.private_subnet_1.id, aws_subnet.private_subnet_2.id]
  security_group_ids  = [aws_security_group.ec2_sg.id]
  private_dns_enabled = true
  tags = {
    Name = "ssm-endpoint"
  }
}