variable "environment" {
  type        = string
  description = "Environment name used in resource names."
  default     = "lab"

  validation {
    condition     = contains(["lab", "dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: lab, dev, staging, prod."
  }
}

variable "location" {
  type        = string
  description = "Azure region."
  default     = "francecentral"

  validation {
    condition     = can(regex("^[a-z]+[0-9]*$", var.location))
    error_message = "location must be a lowercase Azure region name such as francecentral."
  }
}

variable "sql_admin_login" {
  type        = string
  description = "SQL Server administrator login."
  default     = "secopsadmin"

  validation {
    condition     = length(var.sql_admin_login) >= 5 && !contains(["admin", "administrator", "root", "sa"], lower(var.sql_admin_login))
    error_message = "Login must be at least 5 characters and not a reserved name (admin, administrator, root, sa)."
  }
}

variable "sql_admin_password" {
  type        = string
  description = "SQL Server administrator password."
  sensitive   = true

  validation {
    condition = (
      length(var.sql_admin_password) >= 14 &&
      can(regex("[A-Z]", var.sql_admin_password)) &&
      can(regex("[a-z]", var.sql_admin_password)) &&
      can(regex("[0-9]", var.sql_admin_password)) &&
      can(regex("[^A-Za-z0-9]", var.sql_admin_password))
    )
    error_message = "Password: at least 14 characters with upper case, lower case, digit and special character."
  }
}

variable "client_ip_address" {
  type        = string
  description = "Your public IPv4 address (no CIDR) allowed through the SQL firewall."

  validation {
    condition     = can(regex("^((25[0-5]|2[0-4][0-9]|1?[0-9]?[0-9])\\.){3}(25[0-5]|2[0-4][0-9]|1?[0-9]?[0-9])$", var.client_ip_address))
    error_message = "client_ip_address must be a valid IPv4 address such as 203.0.113.45."
  }
}