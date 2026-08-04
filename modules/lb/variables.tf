variable "compartment_id" {
  type        = string
  description = "OCID of the compartment to create the load balancer in."
}

variable "subnet_ids" {
  type        = list(string)
  description = "Subnets for the load balancer."
}

variable "display_name" {
  type        = string
  description = "Display name of the load balancer."
}

variable "hostname" {
  type        = string
  description = "Hostname routed by the HTTP listener."
}

variable "backends" {
  type = list(object({
    ip   = string
    port = optional(number, 80)
  }))
  description = "Backend compute instances as ip + port pairs."
}
