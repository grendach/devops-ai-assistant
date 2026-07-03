terraform {
  backend "s3" {
    bucket  = "tf-state-devops-ai-assistant-432180781943-eu-west-1-an"
    key     = "devops-ai-assistant/terraform.tfstate"
    region  = "eu-west-1"
    encrypt = true
  }
}
