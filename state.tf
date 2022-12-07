terraform{
    backend "s3" {
        bucket = "network-e1-terraformstate"
        encrypt = true
        key = "terraform.tfstate"
        region = "us-east-1"
      
    }
}
