// Copyright (c) 2017, 2019, Oracle and/or its affiliates. All rights reserved.

variable "tenancy_ocid" {}
variable "user_ocid" {}
variable "fingerprint" {}
variable "private_key_path" {}
variable "ssh_public_key" {}
variable "compartment_ocid" {}
variable "region" {}

provider "oci" {
  region           = var.region
  tenancy_ocid     = var.tenancy_ocid
  user_ocid        = var.user_ocid
  fingerprint      = var.fingerprint
  private_key_path = var.private_key_path
}

data "oci_identity_availability_domain" "ad" {
  compartment_id = var.tenancy_ocid
  ad_number = "3" # always free
}

resource "oci_core_virtual_network" "main_vcn" {
  cidr_block     = "10.1.0.0/16"
  compartment_id = var.compartment_ocid
  display_name   = "vcn-${var.project_nickname}"
  dns_label      = "vcn${var.project_nickname}"
}

resource "oci_core_subnet" "main_subnet" {
  cidr_block        = "10.1.20.0/24"
  display_name      = "subnet-${var.project_nickname}"
  dns_label         = "subnet${var.project_nickname}"
  security_list_ids = ["${oci_core_security_list.main_security_list.id}"]
  compartment_id    = var.compartment_ocid
  vcn_id            = oci_core_virtual_network.main_vcn.id
  route_table_id    = oci_core_route_table.main_route_table.id
  dhcp_options_id   = oci_core_virtual_network.main_vcn.default_dhcp_options_id
}

resource "oci_core_internet_gateway" "main_igw" {
  compartment_id = var.compartment_ocid
  display_name   = "igw-${var.project_nickname}"
  vcn_id         = oci_core_virtual_network.main_vcn.id
}

resource "oci_core_route_table" "main_route_table" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_virtual_network.main_vcn.id
  display_name   = "routeTable-${var.project_nickname}"

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.main_igw.id
  }
}

resource "oci_core_security_list" "main_security_list" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_virtual_network.main_vcn.id
  display_name   = "secList-${var.project_nickname}"

  egress_security_rules {
    protocol    = "6"
    destination = "0.0.0.0/0"
  }

  ingress_security_rules {
    protocol = "6"
    source   = "0.0.0.0/0"

    tcp_options {
      max = "22"
      min = "22"
    }
  }

  ingress_security_rules {
    protocol = "6"
    source   = "0.0.0.0/0"

    tcp_options {
      max = "9090"
      min = "9090"
    }
  }
}

resource "oci_core_instance" "main_instance" {
  availability_domain = data.oci_identity_availability_domain.ad.name
  compartment_id      = var.compartment_ocid
  display_name        = "instance-${var.project_nickname}"
  shape               = "VM.Standard.E2.1.Micro"

  create_vnic_details {
    subnet_id        = oci_core_subnet.main_subnet.id
    display_name     = "primaryvnic"
    assign_public_ip = true
    hostname_label   = "instance-${var.project_nickname}"
  }

  source_details {
    source_type = "image"
    source_id   = var.image_id
  }

  metadata = {
    ssh_authorized_keys = var.ssh_public_key
  }

  provisioner "remote-exec" {
    inline = [
      # step1
      "sudo apt install -y prometheus",
      # todo - use an prebuilt image instead of installing this way
    ]
    connection {
      type = "ssh"
      user = "ubuntu"
      agent = false
      host = self.public_ip
      private_key = file(var.ssh_key)
    }
  }
}

output "address" {
  value = oci_core_instance.main_instance.public_ip
}