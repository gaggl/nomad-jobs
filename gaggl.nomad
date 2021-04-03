job "gaggl" {
  datacenters = ["mgmt"]
  namespace = "gaggl"
  type = "service"

  group "gamemaster" {

    network {
      port "gamemaster" {}
    }

    service {
      name = "gamemaster"
      port = "gamemaster"
      tags = ["traefik.enable=true"]
      check {
        type     = "tcp"
        interval = "10s"
        timeout  = "2s"
      }
    }

    task "gamemaster" {
      driver = "docker"

      config {
        image = "hashicorp/demo-webapp-lb-guide"
        ports = [
          "gamemaster"]
      }

      env {
        PORT = "${NOMAD_PORT_gamemaster}"
        NODE_IP = "${NOMAD_IP_gamemaster}"
      }

      resources {
        cpu = 100
        memory = 16
      }
    }
  }
}