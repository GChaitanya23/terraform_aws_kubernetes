
variable "admin_ip" {
  description = "Admin Ip for accessing Bastion instance"
  type        = string
  default = "0.0.0.0/0"  # need to change the ip address
}

variable "vpc_cidr_block" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"

}

variable "availability_zones" {
  description = "Availability zones"
  type        = list(string)
  default     = ["ap-south-1a", "ap-south-1b", "ap-south-1c"]
}
variable "public_subnet_cidr_blocks" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
  default     = ["10.0.128.0/20", "10.0.144.0/20", "10.0.160.0/20"]
}

variable "private_subnet_cidr_blocks" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
  default     = ["10.0.0.0/19", "10.0.32.0/19", "10.0.64.0/19"]
}

variable "key_name" {
  description = "SSH key pair name for the bastion instances"
  type        = string
  default     = "demokey"  # Replace with the appropriate key pair name
}
