variable "region" {
  description = "AWS region"
  type        = string
  default     = "eu-west-3"
}

variable "aws_profile" {
  description = "AWS CLI profile to use"
  type        = string
  default     = "default"
}

variable "project" {
  description = "Project name, used as a prefix for all resources"
  type        = string
  default     = "dekin"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "instance_type" {
  description = "EC2 instance type for the application host"
  type        = string
  default     = "t3.micro"
}

variable "ssh_public_key" {
  description = "SSH public key authorized on the EC2 instance"
  type        = string
}

variable "ssh_allowed_cidr" {
  description = "CIDR block allowed to SSH into the EC2 instance"
  type        = string
  default     = "0.0.0.0/0"
}

variable "db_name" {
  description = "Initial PostgreSQL database name"
  type        = string
  default     = "dekin"
}

variable "db_username" {
  description = "Master username for the RDS instance"
  type        = string
  default     = "dekin"
}

variable "db_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t4g.micro"
}

variable "db_allocated_storage" {
  description = "Allocated storage in GB for the RDS instance"
  type        = number
  default     = 20
}
