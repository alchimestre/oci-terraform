variable "tenancy_ocid" {
  type        = string
  description = "OCID of your tenancy. To get the value, see https://docs.oracle.com/en-us/iaas/Content/API/Concepts/apisigningkey.htm#five"
}

variable "user_ocid" {
  type        = string
  description = "OCID of the user calling the API. To get the value, see https://docs.oracle.com/en-us/iaas/Content/API/Concepts/apisigningkey.htm#five"
}

variable "private_key_path" {
  type        = string
  description = "The path (including filename) of the private key stored on your computer. Required if private_key is not defined. For details on how to create and configure keys see https://docs.oracle.com/en-us/iaas/Content/API/Concepts/apisigningkey.htm#two and https://docs.oracle.com/en-us/iaas/Content/API/Concepts/apisigningkey.htm#three"
}

variable "fingerprint" {
  type        = string
  description = "Fingerprint for the key pair being used. To get the value, see https://docs.oracle.com/en-us/iaas/Content/API/Concepts/apisigningkey.htm#four"
}

variable "region" {
  type        = string
  description = "An OCI region. See https://docs.oracle.com/en-us/iaas/Content/General/Concepts/regions.htm#top"
}

variable "compartment_ocid" {
  type = string
}

variable "ssh_public_key" {
  type        = string
  description = "An SSH public key for use with a virtual machine."
}

variable "instance_shape" {
  type        = string
  description = "An OCI instance type."
  default     = "VM.Standard.A1.Flex"
}

variable "instance_ocpus" {
  type        = number
  description = "Number of vCPUs to use for a given instance."
  default     = 1
}

variable "instance_shape_config_memory_in_gbs" {
  type        = number
  description = "RAM quantity to assign to a given instance."
  default     = 6
}

variable "autonomous_database_admin_password" {
  type        = string
  description = "Admin password for the Autonomous Database. Must be 12-30 characters and include uppercase, lowercase, and a number."
  sensitive   = true
}

variable "ingress_rules" {
  type = map(object({
    description = string
    protocol    = string # "tcp" or "udp"
    source      = optional(string, "0.0.0.0/0")
    min_port    = number
    max_port    = optional(number, null) # null = single port
  }))
  description = "Firewall ingress rules for the security list, keyed by rule name."
  default = {
    ssh         = { description = "SSH", protocol = "tcp", min_port = 22 }
    http        = { description = "HTTP", protocol = "tcp", min_port = 80 }
    https       = { description = "HTTPS", protocol = "tcp", min_port = 443 }
    caddy_http  = { description = "Caddy HTTP", protocol = "tcp", min_port = 8080 }
    caddy_https = { description = "Caddy HTTPS", protocol = "tcp", min_port = 4443 }
    torrent_dht = { description = "Torrent DHT", protocol = "udp", min_port = 6881 }
    torrent_tcp = { description = "Torrent TCP", protocol = "tcp", min_port = 6890, max_port = 6999 }
    mosh        = { description = "Mosh", protocol = "udp", min_port = 60000, max_port = 61000 }
  }
  validation {
    condition     = alltrue([for rule in values(var.ingress_rules) : contains(["tcp", "udp"], rule.protocol)])
    error_message = "Ingress rule protocol must be \"tcp\" or \"udp\"."
  }
}
