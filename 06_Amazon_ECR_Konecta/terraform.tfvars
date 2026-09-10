aws_region   = "us-east-1"
project_name = "Konecta"

github_repos = [
  "dercioanselmo/konecta-frontend",
  "dercioanselmo/konecta-security-service",
  "dercioanselmo/konecta-stores-and-stock-service",
  "dercioanselmo/konecta-cart-service",
  "dercioanselmo/konecta-checkout-service",
  "dercioanselmo/konecta-order-service",
  "dercioanselmo/konecta-courier-service",
]

role_name = "github-actions-oidc-role-Konecta"

tags = {
  Terraform   = "true"
  Environment = "prod"
  Project     = "Konecta"
  ManagedBy   = "platform-team"
}