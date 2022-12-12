module "network" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 3.0"

  name = "${var.cluster_name}-vpc"
  cidr = "172.16.8.0/21"

  azs             = ["${var.region}a", "${var.region}b", "${var.region}c"]
  private_subnets = ["172.16.8.0/24", "172.16.9.0/24", "172.16.10.0/24"]
  public_subnets  = ["172.16.11.0/24", "172.16.12.0/24", "172.16.13.0/24"]

  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true

  public_subnet_tags = {
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    "kubernetes.io/role/elb"              = 1
  }

  private_subnet_tags = {
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    "kubernetes.io/role/internal-elb"     = 1
    # Tags subnets for Karpenter auto-discovery
    "karpenter.sh/discovery/${var.cluster_name}" = var.cluster_name
  }

  tags = {
    sharedservice = "enable"
  }
}