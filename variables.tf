variable "region" {
  description = "AWS Default Region"
  type        = string
  default     = "eu-west-1"
}

variable "ami_id" {
  description = "ID of the AMI to use by EC2 Instances"
  type        = string
  default     = ""

  validation {

    condition     = length(var.ami_id) >= 12
    error_message = "AMI ID should be at least 12 characters long"
  }


}

variable "instances_per_subnet" {
  description = "Count of EC2 Instances to create in each Subnet"
  type        = number
}


