# 04 — EKS Karpenter

Installs the Karpenter controller, which provides dynamic node provisioning for the EKS cluster created by `03_EKS_with_addons`. While that module creates a static managed node group (`m7i-flex.large`, desired capacity: 3) to provide the cluster's baseline compute capacity, Karpenter watches for unschedulable pods and automatically provisions EC2 instances that satisfy the pending workloads' scheduling requirements. When the additional capacity is no longer needed, it removes those nodes automatically.

This module only installs the **controller** (IAM, Pod Identity, the Helm release, SQS interruption handling). It does **not** define what Karpenter is allowed to provision — that's a separate concern, covered in the note at the bottom of this README.

This module consumes:
- `02_VPC` (`data.terraform_remote_state.vpc`) — provides VPC context and maintains the dependency on the network layer. The module does not currently consume subnet IDs directly for Terraform-managed resources; Karpenter discovers subnets at runtime through AWS resource tags defined for node provisioning (see below).
- `03_EKS_with_addons` (`data.terraform_remote_state.eks`) — provides the EKS cluster name, endpoint, and certificate authority data required by the helm and kubernetes providers to authenticate. These values are also used by the Karpenter Helm deployment to connect the controller to the correct cluster.

## Karpenter controller

| Resource | What it does |
|---|---|
| `aws_iam_role.karpenter_controller` | The controller's IAM role. Trust policy allows `pods.eks.amazonaws.com` to assume it — Pod Identity, consistent with every other AWS-facing workload in this project |
| `aws_iam_policy.karpenter_controller` (`c6_02`) | Karpenter IAM policy. Allows EC2 provisioning, node role handling, SQS interruptions, and required read-only APIs. Restricted to Karpenter-managed resources via tags.|
| `aws_eks_pod_identity_association.karpenter` | Associates the role above with the `karpenter` service account in `kube-system` |
| `aws_iam_role.karpenter_node` (`c6_04`) | IAM role assumed by EC2 nodes provisioned by Karpenter. Includes `AmazonEKSWorkerNodePolicy`, `AmazonEC2ContainerRegistryPullOnly`, `AmazonEKS_CNI_Policy`, and `AmazonSSMManagedInstanceCore`. |
| `aws_eks_access_entry.karpenter_node_access` | Registers `karpenter_node`'s role ARN as an EKS access entry (`EC2_LINUX` type) — without this, nodes Karpenter launches can authenticate to AWS fine but can't actually join the Kubernetes cluster (this is the Access Entries API half of `03`'s `cluster_authentication_mode = "API_AND_CONFIG_MAP"`) |
| `aws_sqs_queue.karpenter_interruption` + policy (`c6_07`) | Queue Karpenter polls to learn about Spot interruptions, AWS Health events, and instance state changes, so it can gracefully cordon/drain/replace a node *before* AWS forcibly reclaims it |
| `aws_cloudwatch_event_rule`/`_target` × 4 (`c6_08`) | EventBridge rules routing AWS Health events, Spot interruption warnings, rebalance recommendations, and EC2 instance state-change notifications into the SQS queue above — this is what actually populates the queue |
| `aws_iam_service_linked_role.ec2_spot` / `ec2_spot_fleet` (`c6_09`) | Account-wide service-linked roles required before EC2 will let anything (including Karpenter) launch Spot instances via `CreateFleet`. Idempotent — safe even if these already exist from something else in the account |
| `helm_release.karpenter` (`c6_06`) | Installs the `karpenter` chart from `oci://public.ecr.aws/karpenter`, version `1.8.2`, into `kube-system`. Explicitly `depends_on`s every IAM/Pod-Identity/SQS resource above — Karpenter's pod would otherwise start before it has permissions to do anything |

## Node discovery: how Karpenter finds subnets and security groups without Terraform telling it directly

Karpenter's controller doesn't take a list of subnet IDs as a Helm value. Instead, it discovers what it's allowed to use by **tag**, at the Kubernetes-manifest layer (`EC2NodeClass`, see below) — `02_VPC` tags both private subnets with `karpenter.sh/discovery = retail-gleamgoods-eks`, and the `EC2NodeClass` references that same tag via `subnetSelectorTerms`/`securityGroupSelectorTerms`. 

## Important: NodePool / EC2NodeClass live in a separate folder

`04_EKS_Karpenter` installs the **controller only**. The Kubernetes custom resources that actually tell Karpenter *what* to provision — instance families, sizes, Spot vs on-demand, AMI, disruption/consolidation policy — are Karpenter's own CRDs (`EC2NodeClass`, `NodePool`), and they live in **`09_KARPENTER_k8s-manifests/`**.

## Providers

Same pattern as `03_EKS_with_addons`: `c5_helm_and_kubernetes_providers.tf` configures the `helm` and `kubernetes` providers against this module's own `data.terraform_remote_state.eks` outputs, authenticating with a short-lived token from `data.aws_eks_cluster_auth` fetched fresh on every plan/apply.

## Variables

Full list in `c2_variables.tf`; only these are overridden in `terraform.tfvars` (rest stay at code defaults):

| Name | Value |
|---|---|
| `aws_region` | `us-east-1` |
| `project_name` | `gleamgoods` |
| `business_division` | `retail` |
| `tags` | `{ Terraform, Environment, Project, ManagedBy }` |

## Outputs

```
karpenter_controller_role_name              = retail-gleamgoods-karpenter-controller-role
karpenter_controller_role_arn               = arn:aws:iam::****:role/retail-gleamgoods-karpenter-controller-role
karpenter_controller_pod_identity_association = <association-id>
karpenter_node_role_name                    = retail-gleamgoods-karpenter-node-role
karpenter_node_role_arn                     = arn:aws:iam::****:role/retail-gleamgoods-karpenter-node-role
karpenter_node_role_unique_id               = <unique-id>
ec2_spot_service_linked_role_name           = AWSServiceRoleForEC2Spot
ec2_spot_service_linked_role_arn            = arn:aws:iam::****:role/aws-service-role/spot.amazonaws.com/AWSServiceRoleForEC2Spot
karpenter_helm_metadata                     = <helm release metadata>
vpc_id / private_subnet_ids / public_subnet_ids  = passthrough of 02_VPC's outputs
eks_cluster_name / eks_cluster_id                = passthrough of 03_EKS_with_addons's outputs
```

## CI/CD

`.github/workflows/terraform-04-eks-karpenter.yaml`, triggered by pushes to `main` touching `04_EKS_Karpenter/**`. Same three-stage pipeline as every other module: Trivy secret scan → Terraform Plan (uploads `tfplan-04-eks-karpenter`) → Terraform Apply, gated behind the `04-EKS-Karpenter-Apply` GitHub Environment's manual approval. AWS auth via OIDC (`github-actions-terraform-role-gleamgoods-devops`, defined in `01_remote_backend_s3bucket`) — no static keys. Corresponding `terraform-04-eks-karpenter-destroy.yaml` for teardown.

Note this CI/CD only covers this module's Terraform — it does **not** apply the `09_KARPENTER_k8s-manifests/` files described above; those remain a manual `kubectl apply` step outside any pipeline.

## State

Remote, same backend bucket, key `GleamGoods/karpenter/terraform.tfstate`.

## Destroy order

Must be destroyed **before** `03_EKS_with_addons` (this module depends on the EKS cluster existing) and **before** `02_VPC`. Before destroying, it's worth manually deleting any Karpenter-provisioned EC2 nodes/NodePools first (`kubectl delete nodepool --all`) so Karpenter's controller isn't torn down while it still owns live EC2 instances. Terraform doesn't know about those instances at all.