# --------------------------------------------------------------------
# Per-database rotation inputs
# --------------------------------------------------------------------
# Drives every for_each in c9_02-c9_05: one app-user secret, one
# host-qualified master-secret copy, one rotation Lambda SG, one SAR
# rotation app, and one rotation schedule per Konecta database - the
# same five resource *types* 08_AWS_managed_databases hand-writes once
# per service (c10_01/c10_02/c10_03/c10_04), applied here via for_each
# instead of being copy-pasted 5x, since 5 near-identical services makes
# copy-paste the worse tradeoff that it isn't for 08's 2 services.
#
# Split into two locals deliberately:
# - konecta_service_keys is static (just the 5 names) and drives every
#   for_each that doesn't need a live RDS attribute - security groups,
#   IAM roles/policies, secret containers, the SAR stacks. This exists
#   so those resources' for_each key set never depends on
#   aws_db_instance output - c7_01's security group takes an inline
#   ingress rule per Lambda SG (c9_02), and if that SG's for_each (and
#   therefore c7_01's dependency graph) pulled in aws_db_instance.*
#   attributes transitively, Terraform would report a dependency cycle
#   (aws_db_instance -> its security group -> the Lambda SGs -> the RDS
#   instances again). Hit exactly this while building it.
# - konecta_databases carries the actual per-instance attributes
#   (address, dbname) and is used ONLY by the one resource that
#   genuinely needs them post-creation: each master-secret copy's value
#   (c9_03's aws_secretsmanager_secret_version) - nothing upstream of
#   the RDS instances depends on that resource, so no cycle there.

locals {
  konecta_service_keys = toset(["cart", "checkout", "security", "courier", "store_stock"])

  konecta_databases = {
    cart = {
      address = aws_db_instance.konecta_cart_postgres.address
      dbname  = aws_db_instance.konecta_cart_postgres.db_name
    }
    checkout = {
      address = aws_db_instance.konecta_checkout_postgres.address
      dbname  = aws_db_instance.konecta_checkout_postgres.db_name
    }
    security = {
      address = aws_db_instance.konecta_security_postgres.address
      dbname  = aws_db_instance.konecta_security_postgres.db_name
    }
    courier = {
      address = aws_db_instance.konecta_courier_postgres.address
      dbname  = aws_db_instance.konecta_courier_postgres.db_name
    }
    store_stock = {
      address = aws_db_instance.konecta_store_stock_postgres.address
      dbname  = aws_db_instance.konecta_store_stock_postgres.db_name
    }
  }
}
