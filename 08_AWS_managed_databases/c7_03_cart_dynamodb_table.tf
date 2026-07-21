# ---------------------------------------------------------------
# DynamoDB Table: Items
# ---------------------------------------------------------------
# NOTE:
# The Cart microservice code is currently hardcoded to connect
# to the AWS region "us-west-2" (DynamoDB endpoint).
# To ensure compatibility without modifying application code,
# Creating this DynamoDB table specifically in the
# "us-west-2" region using an aliased AWS provider (aws.west2).
# File: DynamoDBConfiguration.java from Application repository
# ---------------------------------------------------------------

# DynamoDB Table: Items - us-west-2
resource "aws_dynamodb_table" "items_west2" {
  provider       = aws.west2
  name           = "Items"
  billing_mode   = "PAY_PER_REQUEST"    # On-demand pricing (no capacity planning)
  hash_key       = "id"

  attribute {
    name = "id"
    type = "S"
  }

  attribute {
    name = "customerId"
    type = "S"
  }

  # Global Secondary Index for customer-based lookups
  global_secondary_index {
    name               = "idx_global_customerId"
    hash_key           = "customerId"
    projection_type    = "ALL"
  }

  tags = {
    Name        = "Items"
    Environment = var.project_name
    Component   = "Cart"
  }
}