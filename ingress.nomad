job "ingress" {
  datacenters = ["mgmt"]
  namespace = "mgmt"
  type = "service"

  group "traefik" {
    count = 1

    network {
      port "traefik" {
        static = 80
        to = 80
      }
      port "traefik-ui" {
        static = 8080
        to = 8080
      }
    }

    service {
      name = "traefik"
      port = "traefik-ui"
      tags = [
        "traefik.enable=true",
        "traefik.http.routers.traefik.rule=Host(`ingress.gaggl.vagrant`)"
      ]
      check {
        type = "http"
        path = "/ping"
        interval = "10s"
        timeout  = "2s"
      }
    }

    task "traefik" {
      driver = "docker"

      config {
        image = "traefik:v2.4.8"

        args = [
          "--config.file=/etc/traefik/traefik.yml",
        ]
        ports = ["traefik","traefik-ui"]
        volumes = [
          "local/config:/etc/traefik",
        ]
      }

      template {
        data = <<EOH
---
accessLog:
  filePath: "/var/log/traefik-access.log"
api:
  dashboard: true
  insecure: true
entryPoints:
  http:
    address: ":80"
  traefik:
    address: ":8080"
log:
  filePath: "/var/log/traefik.log"
metrics:
  prometheus:
    addEntryPointsLabels: true
    addServicesLabels: true
ping: {}
providers:
  consulCatalog:
    defaultRule: Host(`{{`{{ .Name }}`}}.gaggl.vagrant`)
    endpoint:
      address: {{ range $i, $s := service "consul" }}{{ if eq $i 0 }}{{.Address}}:8500{{end}}{{end}}
    exposedByDefault: false
tracing:
  zipkin:
    httpEndpoint: http://{{ range $i, $s := service "zipkin" }}{{ if eq $i 0 }}{{.Address}}:{{.Port}}{{end}}{{end}}/api/v2/spans
EOH

        change_mode   = "signal"
        change_signal = "SIGHUP"
        destination   = "local/config/traefik.yml"
      }

      resources {
        cpu    = 100
        memory = 256
      }
    }
  }
}
