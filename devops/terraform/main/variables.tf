variable "env_name" {
  type        = string
  description = "Environment name, e.g. test, dev, prod-env-1."
}

variable "location" {
  type        = string
  description = "Azure region for this environment."
}

variable "resource_group_name" {
  type        = string
  description = "Resource group name for this environment."
}
