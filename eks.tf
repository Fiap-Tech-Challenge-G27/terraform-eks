resource "aws_default_vpc" "vpcTechChallenge" {
  tags = {
    Name = "Default VPC to Tech Challenge"
  }
}

resource "aws_default_subnet" "subnetTechChallenge" {
  availability_zone = "us-east-1a"

  tags = {
    Name = "Default subnet for us-east-1a to Tech Challenge"
  }
}

resource "aws_default_subnet" "subnetTechChallenge2" {
  availability_zone = "us-east-1b"

  tags = {
    Name = "Default subnet for us-east-1b to Tech Challenge"
  }
}

data "aws_iam_policy_document" "policyDocEKS" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

data "aws_iam_policy_document" "policyDocNodeEKS" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "roleEKS" {
  name               = "roleEKS"
  assume_role_policy = data.aws_iam_policy_document.policyDocEKS.json

  inline_policy {
    name = "EKSEC2Policy"

    policy = jsonencode({
      Version = "2012-10-17",
      Statement = [{
        Effect   = "Allow",
        Action   = [
          "ec2:DescribeInstances",
          # Adicione outras ações necessárias para o serviço EC2
        ],
        Resource = "*",
      }],
    })
  }
}

resource "aws_iam_role" "roleNodeEKS" {
  name = "roleNodeEKS"
  assume_role_policy = data.aws_iam_policy_document.policyDocNodeEKS.json
}

resource "aws_iam_role_policy_attachment" "policyEKSAmazonEKSClusterPolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.roleEKS.name
}

resource "aws_iam_role_policy_attachment" "policyEKSAmazonEKSVPCResourceController" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
  role       = aws_iam_role.roleEKS.name
}

resource "aws_iam_role_policy_attachment" "policyRoleNodeEKS" {
  role       = aws_iam_role.roleNodeEKS.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "cniPolicyRoleNodeEKS" {
  role       = aws_iam_role.roleNodeEKS.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "ec2PolicyRoleNodeEKS" {
  role       = aws_iam_role.roleNodeEKS.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_eks_cluster" "clusterTechChallenge" {
  name     = "techchallenge"
  role_arn = aws_iam_role.roleEKS.arn

  vpc_config {
    subnet_ids = [aws_default_subnet.subnetTechChallenge.id, aws_default_subnet.subnetTechChallenge2.id]
  }

  depends_on = [
    aws_iam_role_policy_attachment.policyEKSAmazonEKSClusterPolicy,
    aws_iam_role_policy_attachment.policyEKSAmazonEKSVPCResourceController,
  ]
}

resource "aws_eks_node_group" "appNodeGroupTechChallenge" {
  cluster_name    = aws_eks_cluster.clusterTechChallenge.name
  node_group_name = "appNodeTechChallenge"
  node_role_arn   = aws_iam_role.roleNodeEKS.arn
  subnet_ids      = [aws_default_subnet.subnetTechChallenge.id, aws_default_subnet.subnetTechChallenge2.id]

  instance_types = ["t3.micro"]  # Especifica o tipo de instância
  # ami_type       = "AL2_x86_64"   # Especifica o tipo de AMI
  disk_size      = 20              # Tamanho do disco em GB
  tags = {
    "Name" = "eks-node-app"
  }

  scaling_config {
    desired_size = 2
    max_size     = 3
    min_size     = 1
  }

  depends_on = [
    aws_iam_role_policy_attachment.policyRoleNodeEKS,
    aws_iam_role_policy_attachment.cniPolicyRoleNodeEKS,
    aws_iam_role_policy_attachment.ec2PolicyRoleNodeEKS,
  ]
}