output "public_ip" {
  description = "Public IP address of the load balancer."
  value       = oci_load_balancer_load_balancer.this.ip_address_details[0].ip_address
}

output "load_balancer_id" {
  description = "OCID of the load balancer."
  value       = oci_load_balancer_load_balancer.this.id
}

output "certificate_name" {
  description = "Name of the certificate configured on the HTTPS listener."
  value       = oci_load_balancer_certificate.this.certificate_name
}
