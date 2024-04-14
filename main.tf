provider "aws" {
  region = "us-west-2"
}

resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name = "MainVPC"
  }
}

# Define public subnets
resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "us-west-2a"
  tags = {
    Name = "PublicSubnetA"
  }
}

resource "aws_subnet" "public_b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.3.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "us-west-2b"
  tags = {
    Name = "PublicSubnetB"
  }
}

# Define private subnet
resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-west-2a"
  tags = {
    Name = "PrivateSubnet"
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
  subnet_id     = aws_subnet.public_a.id
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

resource "aws_route_table_association" "public_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_b" {
  subnet_id      = aws_subnet.public_b.id
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
  subnet_id              = aws_subnet.private.id
  security_groups        = [aws_security_group.instance_sg.id]
  associate_public_ip_address = false
  user_data = <<-EOF
    #!/bin/bash
    echo "Starting user-data execution..."
    
    # Install Docker if not installed
    sudo yum install -y docker
    
    # Start and enable Docker service to ensure it runs on reboot
    sudo systemctl start docker
    sudo systemctl enable docker
    
    # Add the 'ec2-user' to the 'docker' group to allow running docker without sudo
    sudo usermod -aG docker ec2-user
    
    # Pull the specific Nginx image built for AMD64 architecture
    sudo docker pull roytzahor/nginx:latest-amd64
    
    # Run the Nginx container with auto-restart unless manually stopped
    sudo docker run --name nginx -d -p 80:80 --restart=unless-stopped roytzahor/nginx:latest-amd64
    
    # Check if the Docker container is running properly
    if ! sudo docker ps | grep -q nginx; then
        echo "Failed to start Nginx container."
        exit 1
    else
        echo "Nginx container started successfully."
        # Quick test to see if Nginx serves content on port 80
        if ! curl -s http://localhost/; then
            echo "Nginx server error, check logs."
            sudo docker logs nginx > /var/log/nginx_startup_logs.txt
        else
            echo "Nginx is active and serving content."
        fi
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
  subnets            = [aws_subnet.public_a.id, aws_subnet.public_b.id]

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
