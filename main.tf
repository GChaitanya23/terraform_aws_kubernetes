provider "aws" {
  region = "ap-south-1"
}

terraform {
  backend "s3" {
    bucket         = "devops-task-file"
    key            = "s3://devops-task-file/terraform.tfstate"
    region         = "ap-south-1"
    encrypt        = true
    
  }
}


resource "aws_vpc" "eks_vpc" {
  cidr_block           = var.vpc_cidr_block
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "eks-vpc"
  }
}

resource "aws_internet_gateway" "eks_igw" {
  vpc_id = aws_vpc.eks_vpc.id

  tags = {
    Name = "eks-igw"
  }
}

resource "aws_route_table" "eks_public_route_table" {
  vpc_id = aws_vpc.eks_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.eks_igw.id
  }

  tags = {
    Name = "eks-public-rt"
  }
}


resource "aws_subnet" "eks_public_subnets" {
  count                   = length(var.public_subnet_cidr_blocks)
  vpc_id                  = aws_vpc.eks_vpc.id
  cidr_block              = var.public_subnet_cidr_blocks[count.index]
  availability_zone       = element(var.availability_zones, count.index)
  map_public_ip_on_launch = true

  tags = {
    Name = "eks-public-subnet-${count.index + 1}"
  }
}

resource "aws_route_table_association" "eks_public_subnet_association" {
  count          = length(var.public_subnet_cidr_blocks)
  subnet_id      = aws_subnet.eks_public_subnets[count.index].id
  route_table_id = aws_route_table.eks_public_route_table.id
}



resource "aws_subnet" "eks_private_subnets" {
  count                   = length(var.private_subnet_cidr_blocks)
  vpc_id                  = aws_vpc.eks_vpc.id
  cidr_block              = var.private_subnet_cidr_blocks[count.index]
  availability_zone       = element(var.availability_zones, count.index)

  tags = {
    Name = "eks-private-subnet-${count.index + 1}"
  }
}



resource "aws_security_group" "bastion_sg" {
  name        = "bastion-security-group"
  description = "Security group for bastion instances"
  vpc_id      = aws_vpc.eks_vpc.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.admin_ip]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "bastion-security-group"
  }
}

resource "aws_launch_configuration" "bastion_launch_configuration" {
  name                 = "bastion-launch-configuration"
  image_id             = "ami-008ad682ec6c1335b"  
  instance_type        = "t3.micro"  
  security_groups      = [aws_security_group.bastion_sg.id]
  key_name             = var.key_name
  associate_public_ip_address = true

  lifecycle {
    create_before_destroy = true
  }
}


resource "aws_autoscaling_group" "bastion_autoscaling_group" {
  name                      = "bastion-autoscaling-group"
  launch_configuration     = aws_launch_configuration.bastion_launch_configuration.name
  min_size                  = 1
  max_size                  = 3
  desired_capacity          = 2
  vpc_zone_identifier       = [aws_subnet.eks_public_subnets[0].id, aws_subnet.eks_public_subnets[1].id, aws_subnet.eks_public_subnets[2].id]
  health_check_type         = "EC2"
  health_check_grace_period = 300

  tag {
    key                 = "Name"
    value               = "bastion-instance"
    propagate_at_launch = true
  }
}


resource "aws_eip" "eks_nat_eip" {
  count = length(var.public_subnet_cidr_blocks)

  vpc = true

  tags = {
    Name = "eks-nat-eip-${count.index + 1}"
  }
}

resource "aws_nat_gateway" "eks_nat_gateway" {
  count = length(var.public_subnet_cidr_blocks)

  subnet_id     = aws_subnet.eks_public_subnets[count.index].id
  allocation_id = aws_eip.eks_nat_eip[count.index].id

  tags = {
    Name = "eks-nat-gateway-${count.index + 1}"
  }
}


resource "aws_route_table" "eks_private_route_table" {
  vpc_id = aws_vpc.eks_vpc.id

  tags = {
    Name = "eks-private-rt"
  }
}


resource "aws_route_table_association" "eks_private_subnet_association" {
  count          = length(var.private_subnet_cidr_blocks)
  subnet_id      = aws_subnet.eks_private_subnets[count.index].id
  route_table_id = aws_route_table.eks_private_route_table.id
}

resource "aws_security_group" "eks_control_plane_sg" {
  name        = "eks-control-plane-sg"
  description = "Security group for EKS control plane"
  vpc_id      = aws_vpc.eks_vpc.id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "eks-control-plane-sg"
  }
}

data "aws_iam_policy_document" "assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "role" {
  name               = "test-role"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}

data "aws_iam_policy_document" "policy" {
  statement {
    effect    = "Allow"
    actions   = ["ec2:Describe*"]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "policy" {
  name        = "test-policy"
  description = "A test policy"
  policy      = data.aws_iam_policy_document.policy.json
}

resource "aws_iam_role_policy_attachment" "test-attach" {
  role       = aws_iam_role.role.name
  policy_arn = aws_iam_policy.policy.arn
}




resource "aws_iam_role_policy_attachment" "eks_cluster_policy_attachment" {
  role       = aws_iam_role.role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}


resource "aws_iam_role_policy_attachment" "eks_cluster_autoscaler_policy_attachment" {
  role       = aws_iam_role.role.name 
  policy_arn = "arn:aws:iam::aws:policy/AutoScalingFullAccess"
}


resource "aws_eks_cluster" "eks_cluster" {
  name    = aws_iam_role.role.name
  role_arn = aws_iam_role.eks_service_role.arn
  version = "1.27"

  vpc_config {
    subnet_ids         = [aws_subnet.eks_private_subnets[0].id]
    security_group_ids = [aws_security_group.eks_control_plane_sg.id]

    
    endpoint_public_access = true
    endpoint_private_access = false
  }

  depends_on = [aws_iam_role_policy_attachment.eks_cluster_policy_attachment]
}


resource "aws_iam_role" "eks_service_role" {
  name = "eks-service-role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "",
      "Effect": "Allow",
      "Principal": {
        "Service": "eks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

resource "aws_iam_role" "eks_node_role" {
  name = "eks-node-role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}


resource "aws_iam_role_policy_attachment" "eks_node_role_policy_attachment" {
  role       = aws_iam_role.eks_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}



resource "null_resource" "install_nginx_ingress" {
  provisioner "local-exec" {
    command = "kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/master/deploy/static/provider/aws/deploy.yaml"
  }

  depends_on = [aws_eks_cluster.eks_cluster]
}

resource "null_resource" "install_jfrog_container_registry" {
  provisioner "local-exec" {
    command = "kubectl apply -f - <<EOF\n---\napiVersion: v1\nkind: Namespace\nmetadata:\n  name: jfrog\n---\napiVersion: apps/v1\nkind: Deployment\nmetadata:\n  name: jfrog-container-registry\n  namespace: jfrog\nspec:\n  replicas: 1\n  selector:\n    matchLabels:\n      app: jfrog-container-registry\n  template:\n    metadata:\n      labels:\n        app: jfrog-container-registry\n    spec:\n      containers:\n        - name: jfrog-container-registry\n          image: docker.bintray.io/jfrog/artifactory-jcr:latest\n          ports:\n            - containerPort: 8081\nEOF"
  }

  depends_on = [aws_eks_cluster.eks_cluster]
}


resource "aws_eks_node_group" "eks_node_group" {
  cluster_name    = aws_eks_cluster.eks_cluster.name
  node_group_name = "eks-node-group"
  node_role_arn   = aws_iam_role.eks_node_role.arn
  subnet_ids      = [aws_subnet.eks_private_subnets[1].id, aws_subnet.eks_private_subnets[2].id]
  scaling_config {
    desired_size = 2
    min_size     = 1
    max_size     = 3
  }
}
