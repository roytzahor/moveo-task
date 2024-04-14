# NGINX Deployment on AWS using Terraform

This project sets up a high-availability architecture on AWS to host a Dockerized NGINX server returning 'yo this is nginx'. The setup is managed entirely through Terraform and is designed to be robust, secure, and cost-efficient within the AWS free tier limits.

## Overview

The infrastructure includes:
- **VPC** with a separate public and private subnet.
- **Internet Gateway** to enable communication over the internet.
- **NAT Gateway** to allow internet access for instances in the private subnet.
- **Application Load Balancer (ALB)** to distribute incoming traffic.
- **EC2 Instance** running within a private subnet, hosting the Dockerized NGINX.
- **Security Groups** to tightly control traffic flow.

The goal is to deploy NGINX that displays "yo this is nginx" when accessed via a web browser through the ALB.

## Architecture diagram
```bash
[Internet]
    |
[Internet Gateway]-----[VPC: 10.0.0.0/16]
    |                         |
    |                   [Public Subnet: 10.0.1.0/24]
    |                         |    \
    |                     [ALB]   [NAT Gateway]---[Internet]
    |                         |          |
    |                         |          |
    |                         |-----[Private Subnet: 10.0.2.0/24]
    |                                          |
    |                                          `---->[EC2 Instance (NGINX)]
    |
    \/
```
*Figure 1: High-level architecture diagram*

## Prerequisites

Before you begin, ensure you have the following:
- AWS account
- Terraform installed
- AWS CLI installed and configured

## Quick Start

Clone this repository to get started:

```bash
git clone https://github.com/roytzahor/moveo-task.git
cd moveo-task
```
## Setup Infrastructure
Initialize Terraform and apply the configuration to start building the infrastructure:

```bash
terraform init
terraform apply
```
## cleanup 
remember to clean your enviroment using 
```bash
terraform destroy
```

## Confirm the apply when prompted.

Access Application
After deployment, access the application via the DNS name provided by the ALB output. This can be found in the Terraform output or in the AWS console under ELB services.
