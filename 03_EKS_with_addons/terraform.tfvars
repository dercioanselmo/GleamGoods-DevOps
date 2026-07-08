# AWS Region and Environment
aws_region        = "us-east-1"
project_name      = "gleamgoods"
business_division = "retail"

# EKS Cluster 
cluster_name = "eks"
cluster_service_ipv4_cidr = "172.20.0.0/16"
cluster_version = "1.35"

# EKS Cluster Access Control
cluster_endpoint_private_access = false
cluster_endpoint_public_access = true
cluster_endpoint_public_access_cidrs = ["0.0.0.0/0"]

# EKS Node Group Configuration
node_instance_types              = ["m7i-flex.large"]
node_capacity_type               = "ON_DEMAND"
node_disk_size                   = 20
node_ami_type                    = "AL2023_x86_64_STANDARD"
node_desired_size                = 3
node_min_size                    = 1
node_max_size                    = 6
node_max_unavailable_percentage  = 33
node_force_update_version        = true

# EKS Cluster Access & Logging
cluster_authentication_mode          = "API_AND_CONFIG_MAP"
cluster_bootstrap_admin_permissions  = true
cluster_log_types                    = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

