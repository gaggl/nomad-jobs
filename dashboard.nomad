job "dashboard" {
  datacenters = ["mgmt"]
  namespace = "shared"
  type = "service"

  group "alertmanager" {
    count = 1

    update {
      max_parallel     = 1
      canary           = 1
      auto_revert      = true
      auto_promote     = true
    }

    network {
      port "alertmanager_ui" {
        to = 9093
      }
    }

    service {
      name = "alertmanager"
      port = "alertmanager_ui"
      tags = ["traefik.enable=true"]
      check {
        type = "http"
        path = "/"
        interval = "10s"
        timeout = "2s"
      }
    }

    task "alertmanager" {
      driver = "docker"

      config {
        image = "prom/alertmanager:v0.21.0"

        ports = ["alertmanager_ui"]
        volumes = [
          "local/config/alertmanager.yml:/etc/alertmanager/config.yml",
        ]

        logging {
          type = "journald"
          config {
            tag = "ALERTMANAGER"
          }
        }
      }

      template {
        data = <<EOH
---
route:
 group_by: [cluster]
 # If an alert isn't caught by a route, send it slack.
 receiver: slack_general
 routes:
  # Send severity=slack alerts to slack.
  - match:
      severity: slack
    receiver: slack_general

receivers:
- name: slack_general
  slack_configs:
  - api_url: 'https://hooks.slack.com/services/token'
    channel: '#alerts'
EOH

        change_mode   = "signal"
        change_signal = "SIGHUP"
        destination   = "local/config/alertmanager.yml"
      }

      resources {
        cpu    = 100
        memory = 64
      }
    }
  }

  group "grafana" {
    count = 1

    ephemeral_disk {
      migrate = true
    }

    network {
      port "grafana_ui" {
        to = 3000
      }
    }

    service {
      name = "grafana"
      port = "grafana_ui"
      tags = ["traefik.enable=true"]
      check {
        type     = "http"
        path     = "/"
        interval = "10s"
        timeout  = "2s"
      }
    }

    task "grafana" {
      driver = "docker"

      config {
        image = "grafana/grafana:7.5.0"
        ports = ["grafana_ui"]
        volumes = [
          "local/datasources:/etc/grafana/provisioning/datasources",
        ]
      }

      env {
        GF_INSTALL_PLUGINS = "grafana-piechart-panel,natel-discrete-panel,jdbranham-diagram-panel"
        GF_SECURITY_ADMIN_USER = "admin"
        GF_SECURITY_ADMIN_PASSWORD = "secret"
      }

      template {
        data = <<EOH
apiVersion: 1
datasources:
- name: Loki
  type: loki
  access: proxy
  url: http://{{ range $i, $s := service "loki" }}{{ if eq $i 0 }}{{.Address}}:{{.Port}}{{end}}{{end}}
  isDefault: false
  version: 1
  editable: false
EOH

        destination = "local/datasources/loki.yaml"
      }

      resources {
        cpu    = 100
        memory = 64
      }
      
      template {
        data = <<EOH
apiVersion: 1
datasources:
- name: Prometheus
  type: prometheus
  access: proxy
  url: http://{{ range $i, $s := service "prometheus" }}{{ if eq $i 0 }}{{.Address}}:{{.Port}}{{end}}{{end}}
  isDefault: true
  version: 1
  editable: false
EOH

        destination = "local/datasources/prometheus.yaml"
      }

      template {
        data = <<EOH
apiVersion: 1
datasources:
- name: Tempo
  type: tempo
  access: proxy
  url: http://{{ range $i, $s := service "tempo" }}{{ if eq $i 0 }}{{.Address}}:{{.Port}}{{end}}{{end}}
  isDefault: false
  version: 1
  editable: false
EOH

        destination = "local/datasources/tempo.yaml"
      }
    }
  }

  group "mailhog" {
    count = 1

    network {
      port "http" {
        to = 8025
      }
      port "smtp" {
        static = 1025
        to = 1025
      }
    }

    service {
      name = "mailhog"
      tags = ["traefik.enable=true"]
      port = "http"
      check {
        type     = "tcp"
        interval = "10s"
        timeout  = "2s"
      }
    }

    service {
      name = "smtp"
      port = "smtp"
      check {
        type     = "tcp"
        interval = "10s"
        timeout  = "2s"
      }
    }

    task "mailhog" {
      driver = "docker"

      config {
        image = "mailhog/mailhog:v1.0.1"
        ports = ["http","smtp"]
      }

      resources {
        cpu    = 100
        memory = 128
      }
    }
  }
}