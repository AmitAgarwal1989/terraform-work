terraform{
    backend "s3" {
        bucket = "intelipaat-demo"
        encrypt = true
        key = "terraform.tfstate"
        region = "us-east-1"
      
    }
}