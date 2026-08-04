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
// See https://www.iana.org/assignments/protocol-numbers/protocol-numbers.xhtml
// for protocol numbers
//
// TCP = 6
// UDP = 17
resource "oci_core_security_list" "security_list" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_virtual_network.vcn.id
  display_name   = "SecurityList"

  egress_security_rules {
    protocol    = "6"
    destination = "0.0.0.0/0"
  }

  ingress_security_rules {
    protocol    = "6"
    source      = "0.0.0.0/0"
    description = "SSH"

    tcp_options {
      min = "22"
      max = "22"
    }
  }

  ingress_security_rules {
    protocol    = "6"
    source      = "0.0.0.0/0"
    description = "HTTP"

    tcp_options {
      min = "80"
      max = "80"
    }
  }

  ingress_security_rules {
    protocol    = "6"
    source      = "0.0.0.0/0"
    description = "HTTPS"

    tcp_options {
      min = "443"
      max = "443"
    }
  }

  ingress_security_rules {
    protocol    = "6"
    source      = "0.0.0.0/0"
    description = "Caddy HTTP"

    tcp_options {
      min = "8080"
      max = "8080"
    }
  }

  ingress_security_rules {
    protocol    = "6"
    source      = "0.0.0.0/0"
    description = "Caddy HTTPS"

    tcp_options {
      min = "4443"
      max = "4443"
    }
  }

  ingress_security_rules {
    protocol    = "17"
    source      = "0.0.0.0/0"
    description = "Torrent DHT"

    udp_options {
      min = "6881"
      max = "6881"
    }
  }

  ingress_security_rules {
    protocol    = "6"
    source      = "0.0.0.0/0"
    description = "Torrent TCP"

    tcp_options {
      min = "6890"
      max = "6999"
    }
  }

  ingress_security_rules {
    protocol    = "17"
    source      = "0.0.0.0/0"
    description = "Mosh"

    udp_options {
      min = "60000"
      max = "61000"
    }
  }
}

// Compute
resource "oci_core_instance" "free_instance0" {
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[0].name
  compartment_id      = var.compartment_ocid
  display_name        = "freeInstance0"
  shape               = var.instance_shape

  shape_config {
    ocpus         = var.instance_ocpus
    memory_in_gbs = var.instance_shape_config_memory_in_gbs
  }

  create_vnic_details {
    subnet_id        = oci_core_subnet.subnet.id
    display_name     = "primaryvnic"
    assign_public_ip = true
    hostname_label   = "freeinstance0"
  }

  source_details {
    source_type = "image"
    source_id   = lookup(data.oci_core_images.images.images[0], "id")
  }

  metadata = {
    ssh_authorized_keys = (var.ssh_public_key != "") ? var.ssh_public_key : tls_private_key.compute_ssh_key.public_key_openssh
  }
}

resource "oci_core_instance" "free_instance1" {
  // A1.Flex is only available in one AD per region — use the same AD as instance0.
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[0].name
  compartment_id      = var.compartment_ocid
  display_name        = "freeInstance1"
  shape               = var.instance_shape

  shape_config {
    ocpus         = var.instance_ocpus
    memory_in_gbs = var.instance_shape_config_memory_in_gbs
  }

  create_vnic_details {
    subnet_id        = oci_core_subnet.subnet.id
    display_name     = "primaryvnic"
    assign_public_ip = true
    hostname_label   = "freeinstance1"
  }

  source_details {
    source_type = "image"
    source_id   = lookup(data.oci_core_images.images.images[0], "id")
  }

  metadata = {
    ssh_authorized_keys = (var.ssh_public_key != "") ? var.ssh_public_key : tls_private_key.compute_ssh_key.public_key_openssh
  }
}

output "compute_instance0_ip" {
  value = oci_core_instance.free_instance0.public_ip
}

output "compute_instance1_ip" {
  value = oci_core_instance.free_instance1.public_ip
}

// Generate a key pair for authentication if none is provided
resource "tls_private_key" "compute_ssh_key" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

output "generated_private_key_pem" {
  value     = (var.ssh_public_key != "") ? var.ssh_public_key : tls_private_key.compute_ssh_key.private_key_pem
  sensitive = true
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
  instance_id         = oci_core_instance.free_instance0.id
}

data "oci_core_vnic" "app_vnic" {
  vnic_id = data.oci_core_vnic_attachments.app_vnics.vnic_attachments[0]["vnic_id"]
}

output "app" {
  value = "http://${data.oci_core_vnic.app_vnic.public_ip_address}"
}

// Load Balancer
resource "oci_load_balancer_load_balancer" "free_load_balancer" {
  compartment_id = var.compartment_ocid
  display_name   = "alwaysFreeLoadBalancer"
  shape          = "flexible"

  shape_details {
    maximum_bandwidth_in_mbps = 10
    minimum_bandwidth_in_mbps = 10
  }

  subnet_ids = [
    oci_core_subnet.subnet.id,
  ]
}

resource "oci_load_balancer_backend_set" "free_load_balancer_backend_set" {
  name             = "lbBackendSet1"
  load_balancer_id = oci_load_balancer_load_balancer.free_load_balancer.id
  policy           = "ROUND_ROBIN"

  health_checker {
    port                = "80"
    protocol            = "HTTP"
    response_body_regex = ".*"
    url_path            = "/"
  }

  session_persistence_configuration {
    cookie_name      = "lb-session1"
    disable_fallback = true
  }
}

resource "oci_load_balancer_backend" "free_load_balancer_backend0" {
  backendset_name  = oci_load_balancer_backend_set.free_load_balancer_backend_set.name
  ip_address       = oci_core_instance.free_instance0.public_ip
  load_balancer_id = oci_load_balancer_load_balancer.free_load_balancer.id
  port             = "80"
}

resource "oci_load_balancer_backend" "free_load_balancer_backend1" {
  backendset_name  = oci_load_balancer_backend_set.free_load_balancer_backend_set.name
  ip_address       = oci_core_instance.free_instance1.public_ip
  load_balancer_id = oci_load_balancer_load_balancer.free_load_balancer.id
  port             = "80"
}

resource "oci_load_balancer_hostname" "load_balancer_hostname" {
  hostname         = "app.free.com"
  load_balancer_id = oci_load_balancer_load_balancer.free_load_balancer.id
  name             = "hostname1"
}

resource "oci_load_balancer_rule_set" "load_balancer_rule_set" {
  items {
    action = "ADD_HTTP_REQUEST_HEADER"
    header = "example_header_name"
    value  = "example_header_value"
  }

  items {
    action          = "CONTROL_ACCESS_USING_HTTP_METHODS"
    allowed_methods = ["GET", "POST"]
    status_code     = "405"
  }

  load_balancer_id = oci_load_balancer_load_balancer.free_load_balancer.id
  name             = "load_balancer_rule_set"
}

resource "oci_load_balancer_listener" "load_balancer_listener_http" {
  load_balancer_id         = oci_load_balancer_load_balancer.free_load_balancer.id
  name                     = "http"
  default_backend_set_name = oci_load_balancer_backend_set.free_load_balancer_backend_set.name
  hostname_names           = [oci_load_balancer_hostname.load_balancer_hostname.name]
  port                     = 80
  protocol                 = "HTTP"
  rule_set_names           = [oci_load_balancer_rule_set.load_balancer_rule_set.name]

  connection_configuration {
    idle_timeout_in_seconds = "240"
  }
}

// TLS certificate for HTTPS load balancer listener
resource "tls_private_key" "lb_key" {
  algorithm   = "ECDSA"
  ecdsa_curve = "P384"
}

resource "tls_self_signed_cert" "lb_cert" {
  private_key_pem = tls_private_key.lb_key.private_key_pem

  subject {
    organization = "Oracle"
    country      = "US"
    locality     = "Austin"
    province     = "TX"
  }

  validity_period_hours = 8760 # 1 year

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
    "client_auth",
    "cert_signing",
  ]

  is_ca_certificate = true
}

resource "oci_load_balancer_certificate" "load_balancer_certificate" {
  load_balancer_id   = oci_load_balancer_load_balancer.free_load_balancer.id
  ca_certificate     = tls_self_signed_cert.lb_cert.cert_pem
  certificate_name   = "certificate1"
  private_key        = tls_private_key.lb_key.private_key_pem
  public_certificate = tls_self_signed_cert.lb_cert.cert_pem

  lifecycle {
    create_before_destroy = true
  }
}

resource "oci_load_balancer_listener" "load_balancer_listener_https" {
  load_balancer_id         = oci_load_balancer_load_balancer.free_load_balancer.id
  name                     = "https"
  default_backend_set_name = oci_load_balancer_backend_set.free_load_balancer_backend_set.name
  port                     = 443
  protocol                 = "HTTP"

  ssl_configuration {
    certificate_name        = oci_load_balancer_certificate.load_balancer_certificate.certificate_name
    verify_peer_certificate = false
  }
}

output "lb_public_ip" {
  value = [oci_load_balancer_load_balancer.free_load_balancer.ip_address_details]
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
