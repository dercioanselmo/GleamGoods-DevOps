

GleamGoods

I received a call from a friend interprenwer, opening his e-commerce application for his shops on his town. He put together a team of 5 developers to deliver 5 microservices, including the UI. He gave them the liberty to choose the language and framework of their choice. He just needed it to be delivered fast, his competition was about to launch one similar service.
He invited me to deliver the infrastructure and deploy his microservices on AWS using managed Kubernetes and any AWS services that I see necessary to deploy and operate the Application.
He gave the AWS Account and the project Github repository, and asked me to my magic.

I jumped to a call with the developers where each one briefed me about his service. They shared me the source code and I consolidated it into a single Github repository, from where they would continue their commits. 
Luckily, they were all seniors, and I asked them to run the service on their local machines using Docker, commit the Dockerfile and README.md structured as: 
 - Tech Stack
 - Configuration (Environment Variables)
 - API Endpoints
 - How to Run locally
 - How to run with Docker

I needed to prioritize QA environment so the QA guys could jump ASAP.
I put together a blue print of what and how the deployment would happens, before start the implementation with Terraform and Kubernetes manifests:

Deployment Tech Stack:
AWS Managed Services
For the cluster
 - VPC 
   - cross 3 Availability Zones, 
   - Public and Private subnet segmentation
   - Internet Gateway + Multi-AZ NAT Gateways
 - Security group, 
 - EKS cluster with multi-AZ worker nodes
   - AWS Load Balancer Controller
   - Karpenter dynamic node provisioning
   - Horizontal Pod Autoscaler (HPA)
   - ExternalDNS with Amazon Route 53
   - Helm-based application deployments
 - IAM Roles  and Policies, 
 - Load Balancer, 
 - Secret Manager, 
 - EBS, 
 - S3 Bucket, 
 - Amazon Route 53, 
 - Certificate Manager
 - Amazon CloudWatch
 - Amazon Managed Prometheus
 - Amazon Managed Grafana

EKS Addons
Core:
 - ExternalDNS
 - EKS Pod Identity Agent
 - EBS CSI Driver
 - Cert Manager
Observability:
 - Kube State Metrics
 - Metric Server
 - Prometheus Node Explorer
 - Grafana

For the Application Microservices:
UI - A Java service providing the frontend for the GleamGoods, serving the HTML UI and aggregating calls to the backend API components.
Orders - Java service providing an API for storing orders with persistence using PostgreSQL.
 - RDS postgres
 - SQS
Checkout - A Node.js API for storing customer data during the checkout process using Redis.
 - ElasticCache Redis
Catalog - Implemented with Go and data persisted with MySQL, provides an API for retrieving product catalog information
 - RDS MySQL
Cart - A service implemented using Java and data persisted using DynamoDB, is the API for storing customer shopping carts.
 - DynamoDB

CICD



