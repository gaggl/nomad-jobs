job "scaling" {
  datacenters = ["mgmt"]
  namespace = "mgmt"
  type = "service"

  group "nomad-autoscaler" {
    count = 1

    network {
      port "autoscaler" {
        to = 8080
      }
      port "promtail" {
        to = 9080
      }
    }

    service {
      name = "nomad-autoscaler"
      port = "autoscaler"

      check {
        type     = "http"
        path     = "/v1/health"
        interval = "5s"
        timeout  = "2s"
      }
    }

    service {
      name = "promtail"
      port = "promtail"

      check {
        type     = "http"
        path     = "/ready"
        interval = "10s"
        timeout  = "2s"
      }
    }

    task "nomad-autoscaler" {
      driver = "docker"

      config {
        image = "hashicorp/nomad-autoscaler:0.3.7"
        command = "nomad-autoscaler"
        ports = ["autoscaler"]
        args = [
          "agent",
          "-config",
          "${NOMAD_TASK_DIR}/config.hcl",
          "-http-bind-address",
          "0.0.0.0",
        ]
      }

      template {
        data = <<EOF
log_json = true

nomad {
  address = "http://{{env "attr.unique.network.ip-address" }}:4646"
}

apm "prometheus" {
  driver = "prometheus"
  config = {
    address = "http://{{ range $i, $s := service "prometheus" }}{{ if eq $i 0 }}{{.Address}}:{{.Port}}{{end}}{{end}}"
  }
}

strategy "target-value" {
  driver = "target-value"
}

telemetry {
  disable_hostname = true
  prometheus_metrics = true
}
          EOF

        destination = "${NOMAD_TASK_DIR}/config.hcl"
      }

      resources {
        cpu    = 50
        memory = 128
      }
    }

    task "promtail" {
      driver = "docker"

      lifecycle {
        hook    = "prestart"
        sidecar = true
      }

      config {
        image = "grafana/promtail:2.6.1"
        ports = ["promtail"]
        args = [
          "-config.file",
          "local/promtail.yaml",
        ]
      }

      template {
        data = <<EOH
server:
  http_listen_port: 9080
  grpc_listen_port: 0

positions:
  filename: /tmp/positions.yaml

client:
  url: http://{{ range $i, $s := service "loki" }}{{ if eq $i 0 }}{{.Address}}:{{.Port}}{{end}}{{end}}/loki/api/v1/push

scrape_configs:
- job_name: system
  static_configs:
  - targets:
      - localhost
    labels:
      task: nomad-autoscaler
      __path__: /alloc/logs/nomad-autoscaler*
  pipeline_stages:
  - match:
      selector: '{task="nomad-autoscaler"}'
      stages:
      - json:
          expressions:
            policy_id: '"@policy_id"'
            source: '"@source"'
            strategy: '"@strategy"'
            target: '"@target"'
            group: '"@group"'
            job: '"@job"'
            namespace: '"@namespace"'

EOH

        destination = "local/promtail.yaml"
      }

      resources {
        cpu    = 50
        memory = 32
      }
    }
  }
}
