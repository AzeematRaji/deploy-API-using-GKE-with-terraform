terraform {
  required_providers {
    google = {
      source = "hashicorp/google"
      version = "4.51.0"
    }
  }
}

variable "project_id" {
  description = "project id"
}

variable "region" {
  description = "region"
}

variable "credentials_file" {
    description = "Path to the service account key JSON file"
    type        = string
    default     = ""
}
provider "google" {
  project = var.project_id
  region  = var.region
  credentials = file(var.credentials_file)
}

# Enable necessary APIs
resource "google_project_service" "project" {
  for_each = toset([
    "container.googleapis.com",  # GKE API
    "compute.googleapis.com",    # Compute API for VPC and NAT
  ])
  project = var.project_id
  service = each.key
}



# Create a VPC
resource "google_compute_network" "vpc" {
  name                    = "${var.project_id}-vpc"
  auto_create_subnetworks = "false"
}

# Create Subnet
resource "google_compute_subnetwork" "subnet" {
  name          = "${var.project_id}-subnet"
  region        = var.region
  network       = google_compute_network.vpc.name
  ip_cidr_range = "10.10.0.0/24"
}


# Create GKE cluster
data "google_container_engine_versions" "gke_version" {
  location = var.region
  version_prefix = "1.27."
}

resource "google_container_cluster" "primary" {
  name     = "${var.project_id}-gke"
  location = var.region
  remove_default_node_pool = true
  initial_node_count       = 1

  network    = google_compute_network.vpc.name
  subnetwork = google_compute_subnetwork.subnet.name
}

# Separately Managed Node Pool
resource "google_container_node_pool" "primary_nodes" {
  name       = google_container_cluster.primary.name
  location   = var.region
  cluster    = google_container_cluster.primary.name
  
  version = data.google_container_engine_versions.gke_version.release_channel_latest_version["STABLE"]
  node_count = 1

  node_config {
    oauth_scopes = [
      "https://www.googleapis.com/auth/logging.write",
      "https://www.googleapis.com/auth/monitoring",
    ]

    labels = {
      env = var.project_id
    }

    machine_type = "e2-medium"
    tags         = ["gke-node", "${var.project_id}-gke"]
    metadata = {
      disable-legacy-endpoints = "true"
    }
    
    # Set disk size (in GB)
    disk_size_gb = 30  # Reduce this to stay within your quota
  }
}


# NAT gateway

resource "google_compute_instance" "nat_gateway" {
    name         = "nat-gateway"
    machine_type = "e2-medium" 
    zone         =  "us-central1-b"

    network_interface {
        subnetwork = google_compute_subnetwork.subnet.id
        access_config {
            nat_ip = google_compute_address.nat_ip.address
        }
    }

    boot_disk {
      initialize_params {
        image = "ubuntu-os-cloud/ubuntu-2004-lts"
    }
  }

    
}
# Additional firewall rules for ingress/egress traffic as needed

resource "google_compute_address" "nat_ip" {
    name = "nat-ip"
    region = google_compute_subnetwork.subnet.region
}

resource "google_compute_router" "nat_router" {
  name     = "nat-router"
  network = google_compute_network.vpc.name
  region  = var.region
}

resource "google_compute_router_nat" "nat_config" {
  name                 = "nat-config"
  router               = google_compute_router.nat_router.name
  region               = var.region
  nat_ip_allocate_option = "AUTO_ONLY"

  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
  
  
}


# IAM Role for GKE Cluster 
resource "google_project_iam_binding" "gke_cluster_role" {
  project = var.project_id
  role    = "roles/container.clusterAdmin"
  members = ["user:azeematjumoke@gmail.com"]
}

# IAM Role for Service Account 
resource "google_project_iam_binding" "gke_sa_role" {
  project = var.project_id
  role    = "roles/container.developer"
  members = ["serviceAccount:api-deployment-28@gleaming-medium-434407-d8.iam.gserviceaccount.com"]
}

# Firewall Rules
resource "google_compute_firewall" "gke_firewall" {
  name    = "gke-firewall"
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
    ports    = ["80", "443", "5000"]
  }

  source_ranges = ["0.0.0.0/0"]
}


# Kubernetes Provider Configuration 
provider "kubernetes" {
  host                   = google_container_cluster.primary.endpoint
  client_certificate     = google_container_cluster.primary.master_auth.0.client_certificate
  client_key             = google_container_cluster.primary.master_auth.0.client_key
  cluster_ca_certificate = base64decode(google_container_cluster.primary.master_auth.0.cluster_ca_certificate)
}

# Kubernetes Resources
resource "kubernetes_namespace" "demo_ns" {
  metadata {
    name = "api-namespace"
  }
}

resource "kubernetes_deployment" "api_deployment" {
  metadata {
    name      = "api-deployment"
    namespace = kubernetes_namespace.demo_ns.metadata[0].name
  }

  spec {
    replicas = 2
    selector {
      match_labels = {
        app = "python-api"
      }
    }
    template {
      metadata {
        labels = {
          app = "python-api"
        }
      }
      spec {
        container {
          image = "us-east1-docker.pkg.dev/gleaming-medium-434407-d8/api-deployment-repo/my-python-api:v2"
          name  = "api-container"
          port {
            container_port = 5000
          }
          
        }
      }
    }
  }
}

resource "kubernetes_service" "api_service" {
  metadata {
    name      = "api-service"
    namespace = kubernetes_namespace.demo_ns.metadata[0].name
  }
  spec {
    selector = {
      app = "python-api"
    }
    type = "LoadBalancer"
    port {
      port        = 80
      target_port = 5000
    }
  }
}

resource "kubernetes_ingress" "api_ingress" {
  metadata {
    name      = "api-ingress"
    namespace = kubernetes_namespace.demo_ns.metadata[0].name
  }

  spec {
    rule {
      http {
        path {
          path    = "/"
          backend {
            service_name = kubernetes_service.api_service.metadata[0].name
            service_port = 80
          }
        }
      }
    }
  }
}
