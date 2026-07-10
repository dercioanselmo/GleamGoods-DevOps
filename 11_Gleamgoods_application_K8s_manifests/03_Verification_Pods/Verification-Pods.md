# Verification of Data Flow & Connectivity Between RetailStore Microservices and AWS Data Plane

This section helps you **verify end-to-end connectivity** between the GleamGoods microservices running on **Amazon EKS** and their respective **AWS managed services (data plane)** — such as 
1. AWS RDS, 
2. AWS DynamoDB, 
3. AWS ElastiCache, and 
4. AWS Simple Queue Service (SQS).

Each verification uses a lightweight **client pod** (or AWS CLI pod) that:
- Runs inside the **EKS cluster**, sharing the same **VPC and network path** as the microservices.
- Uses **EKS Pod Identity** to securely access AWS services (no static IAM keys).
- Confirms that each microservice is successfully writing or reading data from its assigned AWS service.

By running these commands, you’ll validate:
✅ Network routing from Pods → AWS managed endpoints  
✅ IAM permissions via Pod Identity  
✅ Actual persisted data in the AWS data layer  

> 💡 These steps are crucial for **end-to-end testing** after migrating each microservice from in-cluster dependencies (like MySQL/Redis pods) to **AWS-managed services** for real-world production readiness.

## Step-01: Catalog -> AWS RDS MySQL Database
```bash
# Step-01: Create Pod
kubectl apply -f 01_catalog_mysql_client_pod.yaml
kubectl get pods

# Step-02: Connect to Pod
kubectl exec -it catalog-mysql-client -- bash

# Step-03: Verify Environment Variables
env
env | grep MYSQL
echo $MYSQL_HOST   # It has port appended (catalog-mysql:3306)

# Step-04: Connect to MySQL DB
mysql -h $(echo $MYSQL_HOST | cut -d: -f1) -u $MYSQL_USER -p$MYSQL_PASSWORD 
# (or)
# Connect directly using explicit endpoint or extenralname service
mysql -h catalog-mysql -u $MYSQL_USER -p$MYSQL_PASSWORD 

# Step-05: Verify Data
SHOW DATABASES;
USE catalogdb;
SHOW TABLES;
SELECT * FROM products;
SELECT * FROM products LIMIT 5;
EXIT

# Step-06: exit pod
exit
```

## Step-02: Carts -> AWS Dynamodb
- **AWS Console:** You can also browse via AWS Console -> Dynamodb -> Explore Items
```bash
# Step-01: Create Pod
kubectl apply -f 02_cart_dynamodb_awscli_pod.yaml
kubectl get pods

# Step-02: Connect to Pod
kubectl exec -it carts-dynamodb-client -- bash

# Step-03: Verify AWS Configuration
aws sts get-caller-identity
aws configure list
echo $AWS_REGION

# Step-04: List DynamoDB Tables
aws dynamodb list-tables --region $AWS_REGION

# Step-05: Describe the 'Items' Table
aws dynamodb describe-table \
  --table-name Items \
  --region $AWS_REGION \
  --output table

# Step-06: Scan the Table for All Items
aws dynamodb scan \
  --table-name Items \
  --region $AWS_REGION \
  --output table

# Step-07: Exit pod
exit
```

## Step-03: Checkout -> AWS ElastiCache Redis
```bash
# Step-01: Create Pod
kubectl apply -f 03_checkout_elasticache_redis_client_pod.yaml
kubectl get pods

# Step-02: Connect to Pod
kubectl exec -it checkout-redis-client -- bash

# Step-03: Verify Environment Variables
env | grep REDIS
echo $REDIS_URL

# Step-04: Extract REDIS_HOST and REDIS_PORT
## Since redis-cli doesn’t accept URLs directly, extract host and port:
## Extract hostname and port from the REDIS_URL
REDIS_HOST=$(echo $REDIS_URL | sed -E 's#redis://([^:]+):([0-9]+)#\1#')
REDIS_PORT=$(echo $REDIS_URL | sed -E 's#redis://([^:]+):([0-9]+)#\2#')
echo $REDIS_HOST
echo $REDIS_PORT

# Step-05: Connect to AWS ElastiCache / Redis
redis-cli -h $REDIS_HOST -p $REDIS_PORT

# Step-06: Verify Data
## PING  → Test connectivity; returns PONG if Redis is reachable
PING

## DBSIZE → Shows total number of keys in the current database
DBSIZE

## KEYS * → Lists all keys (use only for quick checks, not on large datasets)
KEYS *

## GET <KEY> → Retrieves the value for a specific key (e.g., cached checkout data)
GET 4a754b49-3021-4e49-ab24-281b4a675214

## SCAN 0 → Non-blocking iterator to explore keys in batches (safer than KEYS *)
SCAN 0

## QUIT → Exit redis-cli prompt
QUIT

# Step-07: exit pod
exit
```

## Step-04: Orders -> AWS RDS PostgreSQL Database
```bash
# Step-01: Create Pod
kubectl apply -f 04_orders_postgresql_client_pod.yaml 
kubectl get pods

# Step-02: Connect to Pod
kubectl exec -it orders-postgresql-client -- bash

# Step-03: Verify Environment Variables
env
env | grep PG
echo $PGHOST   # It has port appended (orders-postgres-db.cxojydmxwly6.us-east-1.rds.amazonaws.com:5432)

# Step-04: Connect to PostgreSQL DB
psql -h $(echo $PGHOST | cut -d: -f1) -p 5432 -U $PGUSER -d $PGDATABASE
# [or]
# Connect directly using explicit endpoint
psql -h orders-postgres-db.cxojydmxwly6.us-east-1.rds.amazonaws.com -p 5432 -U $PGUSER -d $PGDATABASE


## PostgreSQL Verification Commands for ordersdb (from inside the client pod)

# Step-05: List all databases
\l

# Step-06: Connect to ordersdb (if not already)
\c ordersdb

# Step-07: List all tables in public schema
\dt

# Step-08: Describe table structure (example: orders table)
\d orders

# Step-09: View first 10 records from orders table
SELECT * FROM orders LIMIT 10;

# Step-10: Check total row count in orders table
SELECT COUNT(*) FROM orders;

# Step-11: Exit from psql session
\q

# Step-12: exit pod
exit
```

## Step-05: Orders -> AWS Simple Queue Service (SQS)
- **AWS Console:** You can also browse via AWS Console -> SQS -> 
Send and receive messages -> Receive messages -> Click on **Poll for messages**
```bash
# Step-01: Create Pod
kubectl apply -f 05_orders_sqs_awscli_pod.yaml
kubectl get pods

# Step-02: Connect to Pod
kubectl exec -it orders-sqs-client -- bash

# Step-03: Verify AWS Identity and Region
aws sts get-caller-identity
echo $AWS_REGION

# Step-04: Verify Environment Variables
env | grep SQS
echo $SQS_QUEUE_NAME   # From ConfigMap: retail-gleamgoods-orders-queue

# Step-05: Construct Full Queue URL Dynamically
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo $ACCOUNT_ID
QUEUE_URL="https://sqs.${AWS_REGION}.amazonaws.com/${ACCOUNT_ID}/${SQS_QUEUE_NAME}"
echo $QUEUE_URL

# Step-06: Get Queue Attributes
# View key metadata like visibility timeout, message retention, and ARN.
aws sqs get-queue-attributes \
  --queue-url $QUEUE_URL \
  --attribute-names All \
  --region $AWS_REGION

# Step-07: Receive Messages from the Queue
# Fetch up to 5 messages (non-destructive read) and view their contents.
aws sqs receive-message \
  --queue-url $QUEUE_URL \
  --max-number-of-messages 5 \
  --visibility-timeout 10 \
  --wait-time-seconds 5 \
  --region $AWS_REGION

# Step-08: (Optional) View Message Body Cleanly with jq
# Pretty-print message JSON bodies for easier reading.
# The first jq unescapes the body,  
# the second jq pretty-prints the JSON for easy readability.
aws sqs receive-message \
  --queue-url $QUEUE_URL \
  --max-number-of-messages 5 \
  --region $AWS_REGION \
  --output json | jq -r '.Messages[].Body' | jq

# Step-09: Exit the Pod
exit
```
---


## Step-06: Clean-Up
```bash
# Delete all Verification Pods 
kubectl delete -f 04_Verification_Pods
```

## Summary

| Microservice | AWS Managed Service | Verification Pod | Key Commands |
|---------------|---------------------|------------------|---------------|
| **Catalog** | Amazon RDS (MySQL) | `01_catalog_mysql_client_pod.yaml` | `SHOW TABLES`, `SELECT * FROM products` |
| **Carts** | Amazon DynamoDB | `02_cart_dynamodb_awscli_pod.yaml` | `describe-table`, `scan` |
| **Checkout** | Amazon ElastiCache (Redis) | `03_checkout_elasticache_redis_client_pod.yaml` | `PING`, `GET`, `SCAN` |
| **Orders (DB)** | Amazon RDS (PostgreSQL) | `04_orders_postgresql_client_pod.yaml` | `\dt`, `SELECT * FROM orders` |
| **Orders (Queue)** | Amazon SQS | `05_orders_sqs_awscli_pod.yaml` | `get-queue-attributes`, `receive-message` |

This completes the verification of **data flow between EKS microservices and AWS managed services** ensuring our GleamGoods application is fully production-ready with **secure, observable, and scalable data endpoints**.
