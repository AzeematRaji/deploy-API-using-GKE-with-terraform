terraform {
  backend "gcs" {
    bucket  = "cloudwingers-first-bucket" # Replace with your GCS bucket name
    prefix  = "terraform/state"         # Optional: specify a prefix for state files
  }
}
