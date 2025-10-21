# In this file put the variables related to the deployment
variable "region" {
    type = string
    description = "Aws region"
    default = "us-east-2"
}

variable "app_name" {
    type = string
    default = "rdicidr"
  
}