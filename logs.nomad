job "logs" {
  datacenters = ["mgmt"]
  namespace = "mgmt"
  type = "service"

  group "loki" {
    count = 1

    network {
      port "loki" {
        static = 3100
        to = 3100
      }
      port "promtail" {
        to =9080
      }
      port "syslog" {
        static = 1514
        to = 1514
      }
    }

    service {
      name = "loki"
      port = "loki"
      tags = [
        "traefik.enable=true",
        "traefik.http.routers.loki.rule=Host(`logs.gaggl.vagrant`)"
      ]
      check {
        type     = "http"
        path     = "/ready"
        interval = "10s"
        timeout  = "2s"
      }
    }

    service {
      name = "promtail"
      port = "promtail"

      check {
        type     = "tcp"
        interval = "10s"
        timeout  = "2s"
      }
    }

    service {
      name = "syslog"
      port = "syslog"

      check {
        type     = "tcp"
        interval = "10s"
        timeout  = "2s"
      }
    }

    task "loki" {
      driver = "docker"

      config {
        image = "grafana/loki:2.2.1"

        args = [
          "--config.file=/etc/loki/config/loki.yml",
        ]
        ports = ["loki"]
        volumes = [
          "local/config:/etc/loki/config",
        ]
      }

      template {
        data = <<EOH
---
auth_enabled: false

server:
  http_listen_port: 3100
  grpc_listen_port: 9096

ingester:
  lifecycler:
    address: 127.0.0.1
    ring:
      kvstore:
        store: inmemory
      replication_factor: 1
    final_sleep: 0s
  chunk_idle_period: 1h       # Any chunk not receiving new logs in this time will be flushed
  max_chunk_age: 1h           # All chunks will be flushed when they hit this age, default is 1h
  chunk_target_size: 1048576  # Loki will attempt to build chunks up to 1.5MB, flushing first if chunk_idle_period or max_chunk_age is reached first
  chunk_retain_period: 30s    # Must be greater than index read cache TTL if using an index cache (Default index read cache TTL is 5m)
  max_transfer_retries: 0     # Chunk transfers disabled

schema_config:
  configs:
    - from: 2020-10-24
      store: boltdb-shipper
      object_store: filesystem
      schema: v11
      index:
        prefix: index_
        period: 24h

storage_config:
  boltdb_shipper:
    active_index_directory: /tmp/loki/boltdb-shipper-active
    cache_location: /tmp/loki/boltdb-shipper-cache
    cache_ttl: 24h         # Can be increased for faster performance over longer query periods, uses more disk space
    shared_store: filesystem
  filesystem:
    directory: /tmp/loki/chunks

compactor:
  working_directory: /tmp/loki/boltdb-shipper-compactor
  shared_store: filesystem

limits_config:
  reject_old_samples: true
  reject_old_samples_max_age: 168h

chunk_store_config:
  max_look_back_period: 0s

table_manager:
  retention_deletes_enabled: false
  retention_period: 0s

ruler:
  storage:
    type: local
    local:
      directory: /tmp/loki/rules
  rule_path: /tmp/loki/rules-temp
  alertmanager_url: http://{{ range $i, $s := service "alertmanager" }}{{ if eq $i 0 }}{{.Address}}:{{.Port}}{{end}}{{end}}
  ring:
    kvstore:
      store: inmemory
  enable_api: true
EOH

        change_mode   = "signal"
        change_signal = "SIGHUP"
        destination   = "local/config/loki.yml"
      }

      resources {
        cpu    = 100
        memory = 256
      }
    }

    task "promtail" {
      driver = "docker"

      config {
        image = "grafana/promtail:2.2.1"

        args = [
          "--config.file=/etc/promtail/config.yml",
        ]
        ports = ["promtail","syslog"]
        volumes = [
          "local/config:/etc/promtail",
        ]
      }

      template {
        data = <<EOH
server:
  http_listen_port: 9080
  grpc_listen_port: 0

positions:
  filename: /tmp/positions.yaml

clients:
  - url: http://{{ range $i, $s := service "loki" }}{{ if eq $i 0 }}{{.Address}}:{{.Port}}{{end}}{{end}}/loki/api/v1/push

scrape_configs:
  - job_name: syslog
    syslog:
      listen_address: 0.0.0.0:1514
      labels:
        job: "syslog"
    relabel_configs:
      - source_labels: ['__syslog_message_hostname']
        target_label: 'host'
EOH

        change_mode   = "signal"
        change_signal = "SIGHUP"
        destination   = "local/config/config.yml"
      }

      resources {
        cpu    = 100
        memory = 256
      }
    }
  }
}
