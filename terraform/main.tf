# Create and configure project along with associated resources
module "project-factory" {
  source  = "terraform-google-modules/project-factory/google"
  version = "17.0.0" # Check for the latest version

  name                = var.project_name
  project_id          = var.project_id
  billing_account     = var.billing_account
  activate_apis       = var.activate_apis
  bucket_name         = var.bucket_name
  bucket_location     = var.bucket_location
  bucket_versioning   = true
  bucket_force_destroy = true
  default_service_account = "keep"
  disable_services_on_destroy = true

}


# Create VPC, subnets, Cloud Router, and Cloud NAT 
module "network" {
  source       = "terraform-google-modules/network/google"
  version      = "9.3.0"

  network_name = var.network_name
  project_id   = var.project_id

  # Define subnets: one private and one public
  subnets = [
    {
      subnet_name           = "private_subnet"
      subnet_ip             = "10.0.1.0/24"
      subnet_region         = var.region
      subnet_private_access = true
    },
    {
      subnet_name   = "public_subnet"
      subnet_ip     = "10.0.2.0/24"
      subnet_region = var.region
    }
  ]

  secondary_ranges = {
        private_subnet = [
            {
                range_name    = "private_subnet_secondary_01"
                ip_cidr_range = var.ip_range_pods #"10.1.0.0/24"
            },
            {
                range_name    = "private_subnet_secondary_02"
                ip_cidr_range = var.ip_range_services #"10.2.0.0/24"
            },
        ]

        
    }

  # Configure Cloud Router and NAT 
  routes = [
    {
      name                   = "nat-router"
      description            = "route through IGW to access internet"
      destination_range      = "0.0.0.0/0"
      #tags                  = "egress-inet"
      next_hop_internet      = "true"
    }
  ]

  # Ingress rules to allow traffic from LoadBalancer to GKE nodes
  ingress_rules = [
    {
      name = "allow-loadbalancer-to-nodes"
      ports = ["80"]  # application's port
      source_ranges = ["0.0.0.0/0"]  # Restrict this to the LoadBalancer IP range for security
      #target_tags = ["gke-node"]  # Make sure this tag matches your GKE node's tags
    }
  ]
}

# create cluster
module "kubernetes-engine" {
  source           = "terraform-google-modules/kubernetes-engine/google"
  version          = "34.0.0"

  project_id       = var.project_id
  name             = var.cluster_name
  region           = var.region
  network          = var.network_name
  subnetwork       = "private_subnet"
  ip_range_pods    = var.ip_range_pods
  ip_range_services = var.ip_range_services

  # Node pool settings
  node_pools = [
    {
      name           = "default-node-pool"
      machine_type   = "e2-medium"
      min_count      = 1
      max_count      = 3
      disk_size_gb   = 100
      auto_upgrade   = true
      auto_repair    = true
      service_account = "my-node-pool-sa@${var.project_id}.iam.gserviceaccount.com"
    }
  ]
}

# Kubernetes resource
resource "kubernetes_deployment" "my_api" {
  depends_on = [module.kubernetes-engine]

  metadata {
    name      = "my-api"
    namespace = "default"
  }

  spec {
    replicas = 2

    selector {
      match_labels = {
        app = "my-api"
      }
    }

    template {
      metadata {
        labels = {
          app = "my-api"
        }
      }

      spec {
        container {
          name  = "my-api"
          image = "us-central1-docker.pkg.dev/cloudwings-439409/new-repo/new-image:latest" # Replace with your actual image

          port {
            container_port = 8080 # Adjust based on your API
          }
        }
      }
    }
  }

}

resource "kubernetes_service" "my_api_service" {
  metadata {
    name      = "my-api-service"
    namespace = "default"
  }

  spec {
    selector = {
      app = kubernetes_deployment.my_api.metadata[0].labels["app"]
    }

    port {
      port        = 80
      target_port = 8080
    }

    type = "LoadBalancer"
  }
}
