terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.27.0"
    }
  }

  backend "s3" {
    bucket       = "samproj-development-tfstate-bucket-521713274292"
    key          = "vpc/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region = "us-east-1"
}
