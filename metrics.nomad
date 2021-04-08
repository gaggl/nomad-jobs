job "metrics" {
  datacenters = ["mgmt"]
  namespace = "mgmt"
  type = "service"

  group "prometheus" {
    count = 1

    network {
      port "prometheus_ui" {
        to = 9090
      }
    }

    service {
      name = "prometheus"
      port = "prometheus_ui"
      tags = ["traefik.enable=true"]
      check {
        type     = "http"
        path     = "/-/healthy"
        interval = "10s"
        timeout  = "2s"
      }
    }

    task "prometheus" {
      driver = "docker"

      config {
        image = "prom/prometheus:v2.26.0"

        args = [
          "--config.file=/etc/prometheus/config/prometheus.yml",
          "--storage.tsdb.path=/prometheus",
          "--web.console.libraries=/usr/share/prometheus/console_libraries",
          "--web.console.templates=/usr/share/prometheus/consoles",
        ]
        ports = ["prometheus_ui"]
        volumes = [
          "local/config:/etc/prometheus/config",
        ]
      }

      template {
        data = <<EOH
---
global:
  scrape_interval:     1s
  evaluation_interval: 1s

alerting:
 alertmanagers:
   - static_configs:
     - targets:
       - '{{ range $i, $s := service "alertmanager" }}{{ if eq $i 0 }}{{.Address}}:{{.Port}}{{end}}{{end}}'

scrape_configs:
  - job_name: consul
    metrics_path: /v1/agent/metrics
    params:
      format: ['prometheus']
    static_configs:
    - targets: ['{{ range $i, $s := service "consul-ui" }}{{ if eq $i 0 }}{{.Address}}:{{.Port}}{{end}}{{end}}']

  - job_name: grafana
    static_configs:
    - targets: ['{{ range $i, $s := service "grafana" }}{{ if eq $i 0 }}{{.Address}}:{{.Port}}{{end}}{{end}}']

  - job_name: loki
    static_configs:
    - targets: ['{{ range $i, $s := service "loki" }}{{ if eq $i 0 }}{{.Address}}:{{.Port}}{{end}}{{end}}']

  - job_name: node_exporter
    static_configs:
    - targets: ['{{ range $i, $s := service "node_exporter" }}{{ if eq $i 0 }}{{.Address}}:{{.Port}}{{end}}{{end}}']

  - job_name: nomad
    metrics_path: /v1/metrics
    params:
      format: ['prometheus']
    static_configs:
    - targets: ['{{ range $i, $s := service "nomad-ui" }}{{ if eq $i 0 }}{{.Address}}:{{.Port}}{{end}}{{end}}']

  - job_name: prometheus
    static_configs:
    - targets: ['{{ range $i, $s := service "prometheus" }}{{ if eq $i 0 }}{{.Address}}:{{.Port}}{{end}}{{end}}']

  - job_name: tempo
    static_configs:
    - targets: ['{{ range $i, $s := service "tempo" }}{{ if eq $i 0 }}{{.Address}}:{{.Port}}{{end}}{{end}}']

  - job_name: traefik
    static_configs:
    - targets: ['{{ range $i, $s := service "traefik" }}{{ if eq $i 0 }}{{.Address}}:{{.Port}}{{end}}{{end}}']

  - job_name: vault
    metrics_path: /v1/sys/metrics
    params:
      format: ['prometheus']
    static_configs:
    - targets: ['{{ range $i, $s := service "vault" }}{{ if eq $i 0 }}{{.Address}}:{{.Port}}{{end}}{{end}}']

EOH

        change_mode   = "signal"
        change_signal = "SIGHUP"
        destination   = "local/config/prometheus.yml"
      }

      resources {
        cpu    = 100
        memory = 256
      }
    }
  }
}
