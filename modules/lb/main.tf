// Always Free flexible load balancer: HTTP/HTTPS listeners, health-checked
// backend set, hostname routing, request rules, and a self-signed certificate.

resource "oci_load_balancer_load_balancer" "this" {
  compartment_id = var.compartment_id
  display_name   = var.display_name
  shape          = "flexible"

  shape_details {
    maximum_bandwidth_in_mbps = 10
    minimum_bandwidth_in_mbps = 10
  }

  subnet_ids = var.subnet_ids
}

resource "oci_load_balancer_backend_set" "this" {
  name             = "lbBackendSet1"
  load_balancer_id = oci_load_balancer_load_balancer.this.id
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

resource "oci_load_balancer_backend" "this" {
  for_each = { for idx, backend in var.backends : idx => backend }

  backendset_name  = oci_load_balancer_backend_set.this.name
  ip_address       = each.value.ip
  load_balancer_id = oci_load_balancer_load_balancer.this.id
  port             = tostring(each.value.port)
}

resource "oci_load_balancer_hostname" "this" {
  hostname         = var.hostname
  load_balancer_id = oci_load_balancer_load_balancer.this.id
  name             = "hostname1"
}

resource "oci_load_balancer_rule_set" "this" {
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

  load_balancer_id = oci_load_balancer_load_balancer.this.id
  name             = "load_balancer_rule_set"
}

resource "oci_load_balancer_listener" "http" {
  load_balancer_id         = oci_load_balancer_load_balancer.this.id
  name                     = "http"
  default_backend_set_name = oci_load_balancer_backend_set.this.name
  hostname_names           = [oci_load_balancer_hostname.this.name]
  port                     = 80
  protocol                 = "HTTP"
  rule_set_names           = [oci_load_balancer_rule_set.this.name]

  connection_configuration {
    idle_timeout_in_seconds = "240"
  }
}

// TLS certificate for the HTTPS listener (self-signed)
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

resource "oci_load_balancer_certificate" "this" {
  load_balancer_id   = oci_load_balancer_load_balancer.this.id
  ca_certificate     = tls_self_signed_cert.lb_cert.cert_pem
  certificate_name   = "certificate1"
  private_key        = tls_private_key.lb_key.private_key_pem
  public_certificate = tls_self_signed_cert.lb_cert.cert_pem

  lifecycle {
    create_before_destroy = true
  }
}

resource "oci_load_balancer_listener" "https" {
  load_balancer_id         = oci_load_balancer_load_balancer.this.id
  name                     = "https"
  default_backend_set_name = oci_load_balancer_backend_set.this.name
  port                     = 443
  protocol                 = "HTTP"

  ssl_configuration {
    certificate_name        = oci_load_balancer_certificate.this.certificate_name
    verify_peer_certificate = false
  }
}
