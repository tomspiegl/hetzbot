terraform {
  backend "s3" {
    # These values are supplied via `tofu init -backend-config=...` from
    # the justfile, which reads them out of .env. Keeping them out of the
    # committed file means one backend.tf serves any fleet.
    key = "{{FLEET_NAME}}/terraform.tfstate"

    # Hetzner Object Storage compatibility flags.
    use_path_style              = true
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_s3_checksum            = true
  }
}
