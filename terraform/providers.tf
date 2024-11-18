terraform {
  required_providers {
    google = {
      source = "hashicorp/google"
      version = "6.9.0"
    }
  }
}

# Define the Google provider
provider "google" {
  project = var.project_id
  region  = var.region
}

# Define the kubernetes provider

data "google_client_config" "default" {}

provider "kubernetes" {
  host                   = module.kubernetes-engine.endpoint
  token                  = data.google_client_config.default.access_token
  cluster_ca_certificate = base64decode(module.kubernetes-engine.master_auth[0].cluster_ca_certificate)
}



