# GleamGoods - E-Commerce DevOps Platform
<!-- Replace with actual diagram later -->

**Modern, scalable, and fully automated DevOps infrastructure** for a fast-moving e-commerce platform.

---

## 📖 Context

I received a call from a friend and entrepreneur who was launching an e-commerce application for his shops on his town. 
He put together a team of 5 developers to deliver 5 microservices, including the UI. He gave them the liberty to choose the language and framework of their choice. He just needed it to be delivered fast, his competition was about to launch one similar service.

He invited me to deliver the infrastructure and deploy his microservices on AWS using managed Kubernetes and any AWS services that I see necessary to deploy and operate the Application.
He gave the AWS Account and the project Github repository, and asked me to my magic.

I jumped to a call with the developers where each one briefed me about his service. They shared me the source code and I consolidated it into a single Github repository, from where they continued their commits.
Luckily, they were all senior, and I asked them to run the service on their local machines using Docker, commit the Dockerfile and README.md structured as:
 - Tech Stack
 - Configuration (Environment Variables)
 - API Endpoints
 - How to Run locally
 - How to run with Docker
 
I needed to prioritize QA environment so the QA guys could jump ASAP.
I put together a blue print of what and how the deployment would happens, before start the implementation with Terraform and Kubernetes manifests:
 

---

## Deployment Tech Stack
The current project/repository is the AWS, Terraform, Kubernetes deployment.
The source code, and helm charts can be accessed at https://github.com/dercioanselmo/GleamGoods

### AWS Managed Services (Core Infrastructure)

- **VPC**  
  - Spans 3 Availability Zones  
  - Public + Private subnet segmentation  
  - Internet Gateway + Multi-AZ NAT Gateways  

- **IAM Roles/Policies** (least privilege)

- **Amazon EKS**
  - Multi-AZ worker nodes  
  - **AWS Load Balancer Controller**  
  - **Karpenter** for dynamic node provisioning  
    - On-Demand EC2 Instances  
    - Spot EC2 Instances 
  - **Horizontal Pod Autoscaler (HPA)**  
  - **ExternalDNS** + Amazon Route 53  
  - **Helm** for package management  
  - ArgoCD

- **Supporting AWS Services**:
  - Application Load Balancer (ALB)
  - AWS Secrets Manager
  - Amazon EBS (persistent volumes)
  - S3 Buckets
  - Amazon Route 53
  - AWS Certificate Manager (ACM)
  - Open Telemetry
    - Adot Collector
    - Amazon CloudWatch
    - Amazon Managed Service for Prometheus
    - Amazon Managed Grafana

---

## 🔧 EKS Add-ons

### Core Add-ons
- ExternalDNS
- EKS Pod Identity Agent
- EBS CSI Driver
- Cert Manager

### Observability Add-ons
- Kube State Metrics
- Metrics Server
- Prometheus Node Exporter

### GitOps
- **Argo CD** – Installed and configured early to support Helm Charts and GitOps workflows

---

## 🧩 Application Microservices

| Service     | Language   | Persistence          | AWS Service          | Description |
|-------------|------------|----------------------|----------------------|-----------|
| **UI**      | Java       | -                    | -                    | Frontend serving HTML UI + API aggregation |
| **Orders**  | Java       | PostgreSQL           | **RDS Postgres** + SQS | Order management & persistence |
| **Checkout**| Node.js    | Redis                | **ElastiCache Redis**| Checkout process state |
| **Catalog** | Go         | MySQL                | **RDS MySQL**        | Product catalog API |
| **Cart**    | Java       | DynamoDB             | **DynamoDB**         | Shopping cart management |

---

## 🔄 CI/CD Pipelines

### Application CI/CD

**CI (GitHub Actions)**
- SAST & SCA:
  - Static Code Analisys
  - Secret Scanner
  - Software Composition Analysis (SCA)
  - Static Application Security Testing (SAST)
  - Software Bill of Materials (BOM) 

- Builds and pushes images to **Amazon ECR**
  - DAST with OWASP ZAP
  - Image Scanners (On ECR)

**CD (GitOps)**
- **Argo CD** + **Argo Rollouts**
- Canary deployment strategy

### Infrastructure as Code (Terraform) CI/CD

- IaC vulnerability scanning (Trivy or equivalent)
- `terraform plan` on every PR
- Manual approval gate for `terraform apply`
- Manual approval gate for `terraform destroy`

---

## 📦 Application Helm Charts

Each microservice includes Helm chart with:

- **Deployment** (replicas, resource requests & limits, liveness/readiness probes)
- **ConfigMaps** & **Secrets**
- **Service** (ClusterIP / LoadBalancer)
- **HorizontalPodAutoscaler**
- **Ingress** (via ALB)
- Environment-specific values files

**Local Testing**: `helm install` + `kubectl port-forward`

---

## 📈 Load Testing & Validation

- Load generator tools integrated for performance and stress testing
- Monitoring dashboards in Amazon Managed Grafana
- Full observability stack (metrics, logs, traces)



---

# Implementation Progress

## Phase 1 - Project Setup
- [x] 01 GleamGoods-DevOps project repository
- [x] 02 Terraform and AWS CLI setup
- [x] 03 Terraform CICD with automatic apply

## Phase 2 - Core Infrastructure EKS Terraform
- [x] 04 Remote Backend S3 Bucket
- [x] 05 VPC
- [x] 06 EKS Cluster Basic
- [x] 07 EKS Cluster core Addons
- [x] 08 EKS Cluster Karpenter
- [x] 09 Open Telemetry
- [x] 10 ECR
- [x] 11 ArgoCD Install
- [x] 12 Karpenter K8s manifests (EC2 Nodeclass, nodepool's)
- [x] 13 Kubernetes Metrics Server for HPA (Added as EKS Cluster add-ons terraform project)
- [x] 14 Secret Manager in the cluster [With Rotation]

## Phase 3 - Database
- [x] 15 RDS MySQL
- [x] 16 RDS Postgres
- [x] 17 DynamoDB
- [x] 18 Elastic cache Redis
- [x] 19 SQS Queue

## Phase 4 — Application CI (Plain From Commit to ECR)
- [x] 20 Catalog
- [x] 21 Cart
- [x] 22 Checkout
- [x] 23 Orders
- [x] 24 UI

## Phase 6 - Application K8s Manifests and deploy
- [x] 25 Secrets Prover Class (Will allow the apps to use AWS Secrets)
### Phase 6.1 - Application K8s Yaml (Deployent, ConfigMaps, Service, Ingress, etc)
- [x] 26 UI
- [x] 27 Catalog
- [x] 28 Cart
- [x] 29 Checkout
- [x] 30 Orders

## Phase 7 — Application CD with ArgoCD
- [x] 31 Helm chart templating for the 5 services and test
- [x] 32 ArgoCD AutoSync Setup with the Helm Chart Manifest
- [x] 33 ArgoCD Rollout - Convert Deployment in to Rollout and Canary Strategy

## Phase 9 — DNS configuraion
- [x] 34 Amazon Route 53 domain setup
- [x] 35 AWS Certificate Manager (ACM)
- [x] 36 https termination

## Phase 5 — Application CI Security SCAN
- [x] 37 SAST
- [x] 38 SCA

## Phase 8 — Open Telemetry K8s Manifests
- [x] 39 Adot traces
- [x] 40 Adot logs
- [x] 41 Open Telemetry Amazon managed Prometheus
- [x] 42 Open Telemetry Amazon managed Grafana
- [x] 43 Grafana Dashboards

## Phase 10 — refactor project for multi-environment
- [ ] 44 TBD

## Phase 11 — Secrets Rotation Setup
- [x] 45 Enable rotation
- [x] 46 Lambda Functions
- [x] 47 Reloader



### Notes
## ArgoCD Installation and config:
 1. Run the script 07/ArgoCD_Install/install-argocd.sh
 2. Add GithHub token to ArgoCD
 
argocd repo add https://github.com/dercioanselmo/GleamGoods-DevOps.git \
  --username dercioanselmo \
  --password ghp_******_p \ (Get this from GitHub settings --> Developer Tools --> Access tocken)
  --name GleamGoods-DevOps

### Terraform CI/CD — AWS authentication

Every `terraform-*.yaml` workflow authenticates to AWS via **GitHub OIDC** (no long-lived `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY`), assuming `github-actions-terraform-role-gleamgoods-devops`. That role is defined in `01_remote_backend_s3bucket` — the one module applied manually — so it already exists before any other module's CI needs it. Full details in [SECRETS.md](SECRETS.md).

### Detailed per section README:
1.  [01_remote_backend_s3bucket](01_remote_backend_s3bucket/README.md)
2.  [02_VPC](02_VPC/README.md)
3.  [03_EKS_with_addons](03_EKS_with_addons/README.md)