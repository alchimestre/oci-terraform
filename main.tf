provider "oci" {
  fingerprint      = var.fingerprint
  region           = var.region
  tenancy_ocid     = var.tenancy_ocid
  user_ocid        = var.user_ocid
  private_key_path = var.private_key_path
}

// Fetch all availability domains so instances can be spread across them,
// improving chances of finding capacity for Always Free A1 shapes.
data "oci_identity_availability_domains" "ads" {
  compartment_id = var.tenancy_ocid
}

// Networking
resource "oci_core_virtual_network" "vcn" {
  cidr_block     = "10.1.0.0/16"
  compartment_id = var.compartment_ocid
  display_name   = "VCN"
  dns_label      = "vcn"
}

resource "oci_core_subnet" "subnet" {
  cidr_block        = "10.1.20.0/24"
  display_name      = "Subnet"
  dns_label         = "subnet"
  security_list_ids = [oci_core_security_list.security_list.id]
  compartment_id    = var.compartment_ocid
  vcn_id            = oci_core_virtual_network.vcn.id
  route_table_id    = oci_core_route_table.route_table.id
  dhcp_options_id   = oci_core_virtual_network.vcn.default_dhcp_options_id
}

resource "oci_core_internet_gateway" "internet_gateway" {
  compartment_id = var.compartment_ocid
  display_name   = "IG"
  vcn_id         = oci_core_virtual_network.vcn.id
}

resource "oci_core_route_table" "route_table" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_virtual_network.vcn.id
  display_name   = "RouteTable"

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.internet_gateway.id
  }
}

// Firewall rules
// Protocol numbers: https://www.iana.org/assignments/protocol-numbers/protocol-numbers.xhtml
locals {
  protocol_numbers = {
    tcp = "6"
    udp = "17"
  }
}

resource "oci_core_security_list" "security_list" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_virtual_network.vcn.id
  display_name   = "SecurityList"

  egress_security_rules {
    protocol    = "6"
    destination = "0.0.0.0/0"
  }

  dynamic "ingress_security_rules" {
    for_each = var.ingress_rules
    content {
      description = ingress_security_rules.value.description
      protocol    = local.protocol_numbers[ingress_security_rules.value.protocol]
      source      = ingress_security_rules.value.source

      dynamic "tcp_options" {
        for_each = ingress_security_rules.value.protocol == "tcp" ? [1] : []
        content {
          min = tostring(ingress_security_rules.value.min_port)
          max = tostring(ingress_security_rules.value.max_port == null ? ingress_security_rules.value.min_port : ingress_security_rules.value.max_port)
        }
      }

      dynamic "udp_options" {
        for_each = ingress_security_rules.value.protocol == "udp" ? [1] : []
        content {
          min = tostring(ingress_security_rules.value.min_port)
          max = tostring(ingress_security_rules.value.max_port == null ? ingress_security_rules.value.min_port : ingress_security_rules.value.max_port)
        }
      }
    }
  }
}

// Compute
resource "oci_core_instance" "free_instance" {
  count = 2
  // A1.Flex is only available in one AD per region — use the same AD for both.
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[0].name
  compartment_id      = var.compartment_ocid
  display_name        = "freeInstance${count.index}"
  shape               = var.instance_shape

  shape_config {
    ocpus         = var.instance_ocpus
    memory_in_gbs = var.instance_shape_config_memory_in_gbs
  }

  create_vnic_details {
    subnet_id        = oci_core_subnet.subnet.id
    display_name     = "primaryvnic"
    assign_public_ip = true
    hostname_label   = "freeinstance${count.index}"
  }

  source_details {
    source_type = "image"
    source_id   = lookup(data.oci_core_images.images.images[0], "id")
  }

  metadata = {
    ssh_authorized_keys = (var.ssh_public_key != "") ? var.ssh_public_key : tls_private_key.compute_ssh_key.public_key_openssh
  }
}

output "compute_instance_ip" {
  description = "Public IPs of the compute instances, one per instance."
  value       = oci_core_instance.free_instance[*].public_ip
}

// Generate a key pair for authentication if none is provided
resource "tls_private_key" "compute_ssh_key" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

output "generated_private_key_pem" {
  description = "Private key PEM, only when ssh_public_key was left empty."
  value       = var.ssh_public_key == "" ? tls_private_key.compute_ssh_key.private_key_pem : null
  sensitive   = true
}

// Pick up the last Oracle Linux image for provisioning
# See https://docs.oracle.com/iaas/images/
data "oci_core_images" "images" {
  compartment_id           = var.compartment_ocid
  operating_system         = "Oracle Linux"
  operating_system_version = "8"
  shape                    = var.instance_shape
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"
}

// VNIC data sources
data "oci_core_vnic_attachments" "app_vnics" {
  compartment_id      = var.compartment_ocid
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[0].name
  instance_id         = oci_core_instance.free_instance[0].id
}

data "oci_core_vnic" "app_vnic" {
  vnic_id = data.oci_core_vnic_attachments.app_vnics.vnic_attachments[0]["vnic_id"]
}

output "app" {
  value = "http://${data.oci_core_vnic.app_vnic.public_ip_address}"
}

// Load Balancer
module "app_lb" {
  source         = "./modules/lb"
  compartment_id = var.compartment_ocid
  subnet_ids     = [oci_core_subnet.subnet.id]
  display_name   = "alwaysFreeLoadBalancer"
  hostname       = "app.free.com"
  backends = [
    for ip in oci_core_instance.free_instance[*].public_ip : { ip = ip, port = 80 }
  ]
}

output "lb_public_ip" {
  description = "Public IP address of the load balancer."
  value       = module.app_lb.public_ip
}

// Autonomous Database
data "oci_database_autonomous_databases" "autonomous_databases" {
  compartment_id = var.compartment_ocid
  db_workload    = "OLTP"
  is_free_tier   = "true"
}

resource "oci_database_autonomous_database" "autonomous_database" {
  admin_password           = var.autonomous_database_admin_password
  compartment_id           = var.compartment_ocid
  cpu_core_count           = "1"
  data_storage_size_in_tbs = "1"
  db_name                  = "testadb"

  db_workload  = "OLTP"
  display_name = "autonomous_database"

  freeform_tags = {
    "Department" = "Finance"
  }

  is_auto_scaling_enabled = "false"
  license_model           = "LICENSE_INCLUDED"
  is_free_tier            = "true"

  // Always Free ADB is provisioned as "Autonomous AI Database" by OCI, which
  // does not support updating license_model or is_auto_scaling_enabled.
  // Ignoring these prevents a 403 on every subsequent terraform apply.
  lifecycle {
    ignore_changes = [
      license_model,
      is_auto_scaling_enabled,
    ]
  }
}
