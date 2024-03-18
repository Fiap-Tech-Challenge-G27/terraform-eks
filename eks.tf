data "terraform_remote_state" "rds" {
  backend = "s3"
  config = {
    bucket = "techchallengestate-g27"
    key    = "terraform-rds/terraform.tfstate"
    region = var.aws-region
  }
}

resource "aws_default_vpc" "vpcTechChallenge" {
  tags = {
    Name = "Default VPC to Tech Challenge"
  }
}

resource "aws_default_subnet" "subnetTechChallenge" {
  availability_zone = "us-east-1a"

  tags = {
    Name = "Default subnet for us-east-1a to Tech Challenge",
    "kubernetes.io/role/elb" = "1"
  }
}

resource "aws_default_subnet" "subnetTechChallenge2" {
  availability_zone = "us-east-1b"

  tags = {
    Name = "Default subnet for us-east-1b to Tech Challenge",
    "kubernetes.io/role/elb" = "1"
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

resource "aws_iam_role" "roleNodeSecrets" {
  name = "roleNodeSecrets"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.oidc_eks.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${aws_eks_cluster.clusterTechChallenge.identity.0.oidc.0.issuer}:sub" = "system:serviceaccount:default:irsasecrets"
          }
        }
      },
    ]
  })
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

resource "aws_iam_role_policy_attachment" "ecrPolicyRoleNodeEKS" {
  role       = aws_iam_role.roleNodeEKS.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_role_policy_attachment" "elbPolicyRoleNodeEKS" {
  role       = aws_iam_role.roleNodeEKS.name
  policy_arn = "arn:aws:iam::aws:policy/ElasticLoadBalancingFullAccess"
}

resource "aws_iam_role_policy_attachment" "nginx_policy_attachment" {
  role       = aws_iam_role.roleNodeSecrets.name
  policy_arn = data.terraform_remote_state.rds.outputs.secrets_policy
}

resource "aws_iam_role_policy_attachment" "ec2PolicyRoleNodeEKS" {
  role       = aws_iam_role.roleNodeEKS.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2FullAccess"
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

  instance_types = ["t3.medium"]  # Especifica o tipo de instância
  # ami_type       = "AL2_x86_64"   # Especifica o tipo de AMI
  disk_size      = 20              # Tamanho do disco em GB
  tags = {
    "Name" = "eks-node-app"
  }

  capacity_type = "SPOT"

  scaling_config {
    desired_size = 3
    max_size     = 5
    min_size     = 1
  }

  depends_on = [
    aws_iam_role_policy_attachment.policyRoleNodeEKS,
    aws_iam_role_policy_attachment.cniPolicyRoleNodeEKS,
    aws_iam_role_policy_attachment.ec2PolicyRoleNodeEKS,
  ]
}

data "tls_certificate" "thumbprint_eks" {
  url = aws_eks_cluster.clusterTechChallenge.identity.0.oidc.0.issuer
}

resource "aws_iam_openid_connect_provider" "oidc_eks" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.thumbprint_eks.certificates.0.sha1_fingerprint]
  url             = aws_eks_cluster.clusterTechChallenge.identity.0.oidc.0.issuer
}