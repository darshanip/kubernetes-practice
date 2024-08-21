provider "aws" {
  region = "us-east-1"  # Choose your region
}

resource "aws_vpc" "kubespray_vpc" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_subnet" "kubespray_subnet" {
  vpc_id     = aws_vpc.kubespray_vpc.id
  cidr_block = "10.0.1.0/24"
}

resource "tls_private_key" "ssh_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "kubespray_key" {
  key_name   = "kubespray_key"
  public_key = tls_private_key.ssh_key.public_key_openssh
}

resource "aws_internet_gateway" "kubespray_igw" {
  vpc_id = aws_vpc.kubespray_vpc.id
}

resource "aws_route_table" "kubespray_route_table" {
  vpc_id = aws_vpc.kubespray_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.kubespray_igw.id
  }
}

resource "aws_route_table_association" "kubespray_route_table_association" {
  subnet_id      = aws_subnet.kubespray_subnet.id
  route_table_id = aws_route_table.kubespray_route_table.id
}

resource "aws_security_group" "kubespray_sg" {
  vpc_id = aws_vpc.kubespray_vpc.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # Allow SSH from anywhere (replace with your IP for security)
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "kubespray_sg"
  }
}

resource "aws_instance" "controlplane" {
  ami           = "ami-066784287e358dad1"  # Example Ubuntu 20.04 AMI ID (use a free-tier eligible AMI)
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.kubespray_subnet.id
  key_name      = aws_key_pair.kubespray_key.key_name
  security_groups = [aws_security_group.kubespray_sg.id]

  associate_public_ip_address = true

  tags = {
    Name = "controlplane"
  }

  user_data = <<-EOF
    #!/bin/bash
    sudo yum update -y
    sudo yum install -y epel-release
    sudo yum install -y ansible
    sudo yum install -y python3-pip
    sudo pip3 install netaddr
  EOF
   
  depends_on = [aws_security_group.kubespray_sg] 
}

resource "aws_instance" "worker" {
  count         = 3
  ami           = "ami-066784287e358dad1"  # Example Ubuntu 20.04 AMI ID (use a free-tier eligible AMI)
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.kubespray_subnet.id
  key_name      = aws_key_pair.kubespray_key.key_name
  security_groups = [aws_security_group.kubespray_sg.id]

  associate_public_ip_address = true  

  tags = {
    Name = "worker${count.index + 1}"
  }

  user_data = <<-EOF
    #!/bin/bash
    sudo yum update -y
    sudo yum install -y epel-release
    sudo yum install -y ansible
    sudo yum install -y python3-pip
    sudo pip3 install netaddr
  EOF
   
  depends_on = [aws_security_group.kubespray_sg] 
  
}

output "controlplane_ip" {
  value = aws_instance.controlplane.public_ip
}

output "worker_ips" {
  value = [for instance in aws_instance.worker : instance.public_ip]
}

output "ssh_private_key" {
  value     = tls_private_key.ssh_key.private_key_pem
  sensitive = true
}
