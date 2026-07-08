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

# Implementation Roadmap

## Phase 1 - Project Setup
- [x] 01 GleamGoods-DevOps project repository
- [x] 02 Terraform and AWS CLI setup
- [x] 03 Terraform CICD with automatic apply

## Phase 2 - Core Infrastructure EKS
- [x] 04 Remote Backend S3 Bucket
- [x] 05 VPC
- [x] 06 EKS Cluster Basic
- [x] 07 EKS Cluster core Addons
- [ ] 08 EKS Cluster Karpenter
- [ ] 19 Karpenter K8s manifests (EC2 Nodeclass, nodepool's)
- [ ] 10 Kubernetes HPA
- [ ] 11 Open Telemetry
- [ ] 12 ALB
- [ ] 13 Secret Manager in the cluster
- [ ] 14 EBS (persistent volumes)

## Phase 3 - Database
- [ ] 15 RDS MySQL
- [ ] 16 RDS Postgres
- [ ] 17 DynamoDB
- [ ] 18 Elastic cache Redis
- [ ] 19 SQS Queue

## Phase 4 — Application CI (Plain From Commit to ECR)
- [ ] 20 Catalog
- [ ] 21 Cart
- [ ] 22 Checkout
- [ ] 23 Orders
- [ ] 24 UI

## Phase 5 — Application CI Security SCAN
- [ ] 25 SAST
- [ ] 26 SCA

## Phase 6 - Application K8s Manifests and deploy

### Phase 6.1 - Application K8s Yaml (Deployent, ConfigMaps, Service, Ingress, etc)
- [ ] 27 UI
- [ ] 28 Catalog
- [ ] 29 Cart
- [ ] 30 Checkout
- [ ] 31 Orders

## Phase 7 — Application CD with ArgoCD
- [ ] 32 Helm chart templating for the 5 services and test
- [ ] 33 ArgoCD AutoSync Setup with the Helm Chart Manifest
- [ ] 34 ArgoCD Rollout - Canary

## Phase 8 — Open Telemetry K8s Manifests
- [ ] 35 Adot traces
- [ ] 36 Adot logs
- [ ] 37 Open Telemetry Amazon managed Prometheus
- [ ] 38 Open Telemetry Amazon managed Grafana
- [ ] 39 Grafana Dashboards

## Phase 9 — DNS configuraion
- [ ] 40 Amazon Route 53 domain setup
- [ ] 41 AWS Certificate Manager (ACM)
- [ ] 42 https termination

## Phase 10 — refactor project for multi-environment
- [ ] 44 TBD