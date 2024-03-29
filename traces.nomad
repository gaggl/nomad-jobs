job "traces" {
  datacenters = ["mgmt"]
  namespace = "mgmt"
  type = "service"

  group "tempo" {
    count = 1

    network {
      mbits = 10

      port "tempo" {
        to = 3100
      }
      port "tempo-ui" {
        to = 16686
      }
      port "zipkin" {
        static = 9411
        to = 9411
      }
    }

    service {
      name = "tempo"
      port = "tempo"

      check {
        type     = "tcp"
        interval = "10s"
        timeout  = "2s"
      }
    }

    service {
      name = "tempo-ui"
      port = "tempo-ui"

      check {
        type     = "http"
        path     = "/"
        interval = "10s"
        timeout  = "2s"
      }
    }

    service {
      name = "zipkin"
      port = "zipkin"
      check {
        type     = "tcp"
        interval = "10s"
        timeout  = "2s"
      }
    }

    task "tempo" {
      driver = "docker"

      config {
        image = "grafana/tempo:1.5.0"

        args = [
          "--config.file=/etc/tempo/config/tempo.yml",
        ]
        ports = ["tempo","zipkin"]
        volumes = [
          "local/config:/etc/tempo/config",
        ]
      }

      template {
        data = <<EOH
---
auth_enabled: false
server:
  http_listen_port: 3100
distributor:
  receivers:                           # this configuration will listen on all ports and protocols that tempo is capable of.
    jaeger:                            # the receives all come from the OpenTelemetry collector.  more configuration information can
      protocols:                       # be found there: https://github.com/open-telemetry/opentelemetry-collector/tree/master/receiver
        thrift_http:                   #
        grpc:                          # for a production deployment you should only enable the receivers you need!
        thrift_binary:
        thrift_compact:
    zipkin:
    otlp:
      protocols:
        http:
        grpc:
    opencensus:
ingester:
  trace_idle_period: 10s               # the length of time after a trace has not received spans to consider it complete and flush it
  max_block_duration: 5m               #   this much time passes
compactor:
  compaction:
    compaction_window: 1h              # blocks in this time window will be compacted together
    max_compaction_objects: 1000000    # maximum size of compacted blocks
    block_retention: 1h
    compacted_block_retention: 10m
storage:
  trace:
    backend: local                     # backend configuration to use
    wal:
      path: /tmp/tempo/wal             # where to store the the wal locally
    local:
      path: /tmp/tempo/blocks
    pool:
      max_workers: 100                 # the worker pool mainly drives querying, but is also used for polling the blocklist
      queue_depth: 10000
EOH

        change_mode   = "signal"
        change_signal = "SIGHUP"
        destination   = "local/config/tempo.yml"
      }

      resources {
        cpu    = 100
        memory = 256
      }
    }
  }
}
