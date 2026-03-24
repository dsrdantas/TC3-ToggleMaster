terraform {
  backend "s3" {
    bucket         = "togglemaster-terraform-state-49"
    key            = "infra/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "togglemaster-terraform-lock-49"
    encrypt        = true
  }
}
