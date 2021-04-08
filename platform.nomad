job "platform" {
  datacenters = ["dc1","dc2"]
  namespace = "platform"
  type = "service"

  group "demo" {
    count = 2

    network {
      port "webapp_http" {}
      port "toxiproxy_webapp" {}
      port "toxiproxy_api" {
        to = 8474
      }
    }

    scaling {
      enabled = true
      min     = 1
      max     = 10

      policy {
        cooldown = "20s"

        check "avg_instance_sessions" {
          source = "prometheus"
          query  = "sum(traefik_entrypoint_open_connections{entrypoint=\"http\"})/scalar(nomad_nomad_job_summary_running{task_group=\"demo\"})"

          strategy "target-value" {
            target = 5
          }
        }
      }
    }

    task "webapp" {
      driver = "docker"

      config {
        image = "hashicorp/demo-webapp-lb-guide"
        ports = ["webapp_http"]
      }

      env {
        PORT    = "${NOMAD_PORT_webapp_http}"
        NODE_IP = "${NOMAD_IP_webapp_http}"
      }

      resources {
        cpu    = 100
        memory = 16
      }
    }

    task "toxiproxy" {
      driver = "docker"

      lifecycle {
        hook    = "prestart"
        sidecar = true
      }

      config {
        image      = "shopify/toxiproxy:2.1.4"
        entrypoint = ["/go/bin/toxiproxy", "-host", "0.0.0.0", "-config", "/toxiproxy.json"]
        ports      = ["toxiproxy_webapp","toxiproxy_api"]

        volumes = [
          "local/config/toxiproxy.json:/toxiproxy.json",
        ]
      }

      template {
        data = <<EOH
[
  {
    "name": "webapp",
    "listen": "[::]:{{ env "NOMAD_PORT_toxiproxy_webapp" }}",
    "upstream": "{{ env "NOMAD_ADDR_webapp_http" }}",
    "enabled": true
  }
]
EOH

        change_mode   = "signal"
        change_signal = "SIGHUP"
        destination   = "local/config/toxiproxy.json"
      }

      resources {
        cpu    = 100
        memory = 32
      }

      service {
        name = "webapp"
        port = "toxiproxy_webapp"
        tags = ["traefik.enable=true"]
        check {
          type           = "http"
          path           = "/"
          interval       = "5s"
          timeout        = "3s"
          initial_status = "passing"
        }
      }
    }
  }
}
