
terraform {
  required_providers {
    yandex = {
      source  = "yandex-cloud/yandex"
      version = ">= 0.130.0"
    }
  }
}

provider "yandex" {
  folder_id = "b1gfnu4a5b6l9c2kol46"
}

data "yandex_compute_image" "ubuntu" {
  family = "ubuntu-2204-lts"
}

resource "yandex_vpc_network" "k8s" {
  name = "k8s-network"
}

locals {
  subnets = {
    a = {
      zone = "ru-central1-a"
      cidr = "10.20.0.0/24"
    }
    d = {
      zone = "ru-central1-d"
      cidr = "10.21.0.0/24"
    }
    e = {
      zone = "ru-central1-e"
      cidr = "10.22.0.0/24"
    }
  }

  nodes = {
    k8s-master = {
      subnet = "d"
      cores  = 2
      memory = 4
    }

    k8s-worker-1 = {
      subnet = "a"
      cores  = 2
      memory = 2
    }

    k8s-worker-2 = {
      subnet = "a"
      cores  = 2
      memory = 2
    }

    k8s-worker-3 = {
      subnet = "d"
      cores  = 2
      memory = 2
    }

    k8s-worker-4 = {
      subnet = "e"
      cores  = 2
      memory = 2
    }
  }
}

resource "yandex_vpc_subnet" "k8s" {
  for_each = local.subnets

  name           = "k8s-subnet-${each.key}"
  zone           = each.value.zone
  network_id     = yandex_vpc_network.k8s.id
  v4_cidr_blocks = [each.value.cidr]
}

resource "yandex_compute_instance" "node" {
  for_each = local.nodes

  name        = each.key
  platform_id = "standard-v3"
  zone        = local.subnets[each.value.subnet].zone

  resources {
    cores         = each.value.cores
    memory        = each.value.memory
    core_fraction = 20
  }

  boot_disk {
    initialize_params {
      image_id = data.yandex_compute_image.ubuntu.id
      size     = 10
      type     = "network-hdd"
    }
  }

  network_interface {
    subnet_id = yandex_vpc_subnet.k8s[each.value.subnet].id
    nat       = true
  }

  metadata = {
  ssh-keys = join("\n", concat(
    [
      "ubuntu:${file(pathexpand("~/.ssh/yandex_k8s.pub"))}"
    ],
    each.key == "k8s-worker-4" ? [
      "ubuntu:ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPmQL8D9+zXRs/m/Btc4JJlYxVQ7RF1QMBMNTLaUokEo ubuntu@fv4lp3ghq785c5fmkec2"
    ] : []
  ))
}
}

output "public_ips" {
  value = {
    for name, vm in yandex_compute_instance.node :
    name => vm.network_interface[0].nat_ip_address
  }
}

output "private_ips" {
  value = {
    for name, vm in yandex_compute_instance.node :
    name => vm.network_interface[0].ip_address
  }
}
