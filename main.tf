provider "aws" {
  region = "us-west-2"
}

resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name = "MainVPC"
  }
}

# Define subnets
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "us-west-2a"
  tags = {
    Name = "PublicSubnet"
  }
}

resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-west-2c"
  tags = {
    Name = "PrivateSubnet"
  }
}

resource "aws_subnet" "private2" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.4.0/24"
  availability_zone = "us-west-2b"
  tags = {
    Name = "PrivateSubnet2"
  }
}

# Internet Gateway for public access
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name = "MainInternetGateway"
  }
}

# Elastic IP for NAT Gateway
resource "aws_eip" "nat" {
  domain = "vpc"
}

# NAT Gateway configuration
resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public.id
  tags = {
    Name = "MainNATGateway"
  }
}

# Public Route Table and its association
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }
  tags = {
    Name = "PublicRouteTable"
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# Private Route Table and its association
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }
  tags = {
    Name = "PrivateRouteTable"
  }
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "private2" {
  subnet_id      = aws_subnet.private2.id
  route_table_id = aws_route_table.private.id
}

# Security Groups for Load Balancer and EC2 instance
resource "aws_security_group" "allow_http" {
  name        = "allow_http"
  description = "Allow HTTP inbound traffic"
  vpc_id      = aws_vpc.main.id

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

  tags = {
    Name = "HTTPSecurityGroup"
  }
}

resource "aws_security_group" "instance_sg" {
  name        = "nginx-instance-sg"
  description = "Security group for Nginx instance"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.allow_http.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "NginxInstanceSecurityGroup"
  }
}

# EC2 instance configuration
resource "aws_instance" "nginx" {
  ami                    = "ami-0319ef1a70c93d5c8"
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.private2.id
  security_groups        = [aws_security_group.instance_sg.id]
  associate_public_ip_address = false

  user_data = <<-EOF
                  #!/bin/bash
                  echo "Starting user-data execution..."
                  sudo yum update -y
                  sudo amazon-linux-extras install docker -y
                  sudo systemctl start docker
                  sudo systemctl enable docker
                  sudo usermod -a -G docker ec2-user
                  if ! sudo docker run --name nginx -d -p 80:80 roytzahor/nginx:latest; then
                      echo "Failed to start Nginx container."
                  else
                      echo "Nginx container started successfully."
                      # Wait a moment to ensure that Nginx has started
                      sleep 10
                      # Fetching logs from the Nginx container
                      sudo docker logs nginx > /var/log/nginx_startup_logs.txt
                      # Testing if Nginx is serving content on port 80
                      curl -o /var/log/nginx_response.txt http://localhost/
                  fi
              EOF

  tags = {
    Name = "NginxServer"
  }
}

# Load Balancer configuration
resource "aws_lb" "lb" {
  name               = "MainLoadBalancer"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.allow_http.id]
  subnets            = [aws_subnet.public.id, aws_subnet.private2.id]  # Ensure one subnet per AZ

  enable_deletion_protection = false

  tags = {
    Environment = "production"
    Name        = "MainLB"
  }
}

# Load Balancer Listener
resource "aws_lb_listener" "front_end" {
  load_balancer_arn = aws_lb.lb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.front_end.arn
  }
}

# Target Group for the Load Balancer
resource "aws_lb_target_group" "front_end" {
  name     = "NginxTargetGroup"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    enabled             = true
    healthy_threshold   = 3
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    matcher             = "200"
    path                = "/"
    port                = "traffic-port"
  }

  tags = {
    Name = "NginxTG"
  }
}

# Attach the EC2 Instance to the Target Group
resource "aws_lb_target_group_attachment" "test" {
  target_group_arn = aws_lb_target_group.front_end.arn
  target_id        = aws_instance.nginx.id
  port             = 80
}
