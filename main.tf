
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    yandex = {
      source  = "yandex-cloud/yandex"
      version = "0.245.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "4.4.2"
    }
  }
}

variable "yandex_token" {
  type      = string
  sensitive = true
}

variable "yandex_cloud_id" {
  type = string
}

variable "yandex_folder_id" {
  type = string
}

provider "yandex" {
  token     = var.yandex_token
  cloud_id  = var.yandex_cloud_id
  folder_id = var.yandex_folder_id
  zone      = "ru-central1-a"
}

resource "tls_private_key" "ssh" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

data "yandex_compute_image" "ubuntu" {
  family = "ubuntu-2204-lts"
}

resource "yandex_vpc_network" "net" {
  name = "my-custom-vpc"
}

resource "yandex_vpc_subnet" "public_a" {
  name           = "public-a"
  zone           = "ru-central1-a"
  network_id     = yandex_vpc_network.net.id
  v4_cidr_blocks = ["192.168.11.0/24"]
}

resource "yandex_vpc_subnet" "public_b" {
  name           = "public"
  zone           = "ru-central1-e"
  network_id     = yandex_vpc_network.net.id
  v4_cidr_blocks = ["192.168.10.0/24"]
}

resource "yandex_vpc_route_table" "private_rt" {
  name       = "private-route-table"
  network_id = yandex_vpc_network.net.id

  static_route {
    destination_prefix = "0.0.0.0/0"
    next_hop_address   = "192.168.10.254"
  }
}

resource "yandex_vpc_subnet" "private" {
  name           = "private"
  zone           = "ru-central1-d"
  network_id     = yandex_vpc_network.net.id
  v4_cidr_blocks = ["192.168.20.0/24"]
  route_table_id = yandex_vpc_route_table.private_rt.id
}

resource "yandex_compute_instance" "public_vm" {
  name        = "public-vm"
  platform_id = "standard-v2"
  zone        = "ru-central1-a"

  resources {
    cores  = 2
    memory = 2
  }

  boot_disk {
    initialize_params {
      image_id = data.yandex_compute_image.ubuntu.id
      size     = 10
      type     = "network-hdd"
    }
  }

  network_interface {
    subnet_id = yandex_vpc_subnet.public_a.id
    nat       = true
  }

  metadata = {
    ssh-keys = "ubuntu:${tls_private_key.ssh.public_key_openssh}"
  }
}

resource "yandex_compute_instance" "nat_instance" {
  name        = "nat-instance"
  platform_id = "standard-v2"
  zone        = "ru-central1-e"

  resources {
    cores  = 2
    memory = 2
  }

  boot_disk {
    initialize_params {
      image_id = "fd80mrhj8fl2oe87o4e1"
      size     = 5
      type     = "network-hdd"
    }
  }

  network_interface {
    subnet_id  = yandex_vpc_subnet.public_b.id
    ip_address = "192.168.10.254"
    nat        = true
  }
}

resource "yandex_compute_instance" "private_vm" {
  name        = "private-vm"
  platform_id = "standard-v2"
  zone        = "ru-central1-d"

  resources {
    cores  = 2
    memory = 2
  }

  boot_disk {
    initialize_params {
      image_id = data.yandex_compute_image.ubuntu.id
      size     = 10
      type     = "network-hdd"
    }
  }

  network_interface {
    subnet_id = yandex_vpc_subnet.private.id
    nat       = false
  }

  metadata = {
    ssh-keys = "ubuntu:${tls_private_key.ssh.public_key_openssh}"
  }

  depends_on = [
    yandex_compute_instance.nat_instance
  ]
}

output "public_vm_ip" {
  value = yandex_compute_instance.public_vm.network_interface[0].nat_ip_address
}

output "nat_instance_internal_ip" {
  value = yandex_compute_instance.nat_instance.network_interface[0].ip_address
}

output "private_vm_internal_ip" {
  value = yandex_compute_instance.private_vm.network_interface[0].ip_address
}

output "ssh_private_key" {
  value     = tls_private_key.ssh.private_key_pem
  sensitive = true
}

