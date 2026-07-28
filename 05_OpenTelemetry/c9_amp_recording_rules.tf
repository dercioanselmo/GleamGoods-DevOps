# --------------------------------------------------------------------
# AMP recording rules: kubernetes-mixin subset
# --------------------------------------------------------------------
# The dotdc "Kubernetes / Views" Grafana dashboard family (Global 15760,
# Namespaces 15757, Pods 15759, Nodes 15761) queries precomputed recording
# rules (e.g. node_namespace_pod_container:container_memory_working_set_bytes,
# namespace_workload_pod:kube_pod_owner:relabel, node:node_num_cpu:sum) -
# not raw scraped metrics. Confirmed via direct AMP query that none of these
# existed: our ADOT collector (12_Open_Telemetry/03_OpenTelemetry_AMP_AMG)
# is a pure receiver -> processor -> exporter pipeline with no rule
# evaluation engine, so it was never going to produce them regardless of
# scrape/relabel config.
#
# AMP has its own server-side rule evaluation feature - this resource loads
# the standard kubernetes-mixin recording rules (same ones kube-prometheus-
# stack ships, same ones these dashboards were built against) into AMP,
# which evaluates them on its own schedule against data already in the
# workspace. No collector changes needed for this part.
#
# IMPORTANT - VERIFY BEFORE APPLYING: the rule expressions below are a
# best-effort reproduction of the well-known kubernetes-mixin k8s.rules /
# node.rules groups, written from memory rather than copied byte-for-byte
# from the upstream source. The join logic (kube_pod_info node join, kube_pod_owner
# relabeling) is intricate and has shifted slightly across kube-state-metrics
# versions. Before applying, diff this against the current upstream source:
#   https://github.com/kubernetes-monitoring/kubernetes-mixin
# or the rendered rules from the kube-prometheus-stack Helm chart
# (kube-prometheus-stack-k8s.rules.yaml / kube-prometheus-stack-node.rules.yaml).
# A wrong expression here won't error loudly - AMP will just evaluate it and
# store whatever it computes, which could be silently incorrect rather than
# missing.
resource "aws_prometheus_rule_group_namespace" "kubernetes_mixin_recording_rules" {
  name         = "kubernetes-mixin-recording-rules"
  workspace_id = aws_prometheus_workspace.amp.id

  data = <<-EOT
  groups:
    - name: k8s.rules.container_resource
      rules:
        - record: node_namespace_pod_container:container_cpu_usage_seconds_total:sum_irate
          expr: |
            sum by (namespace, pod, container) (
              irate(container_cpu_usage_seconds_total{job="cadvisor", image!=""}[5m])
            ) * on (namespace, pod) group_left(node) topk by (namespace, pod) (
              1, max by (namespace, pod, node) (kube_pod_info{job="kube-state-metrics", node!=""})
            )
        - record: node_namespace_pod_container:container_memory_working_set_bytes
          expr: |
            container_memory_working_set_bytes{job="cadvisor", image!=""}
            * on (namespace, pod) group_left(node) topk by (namespace, pod) (
              1, max by (namespace, pod, node) (kube_pod_info{job="kube-state-metrics", node!=""})
            )
        - record: node_namespace_pod_container:container_memory_rss
          expr: |
            container_memory_rss{job="cadvisor", image!=""}
            * on (namespace, pod) group_left(node) topk by (namespace, pod) (
              1, max by (namespace, pod, node) (kube_pod_info{job="kube-state-metrics", node!=""})
            )
        - record: node_namespace_pod_container:container_memory_cache
          expr: |
            container_memory_cache{job="cadvisor", image!=""}
            * on (namespace, pod) group_left(node) topk by (namespace, pod) (
              1, max by (namespace, pod, node) (kube_pod_info{job="kube-state-metrics", node!=""})
            )
        - record: node_namespace_pod_container:container_memory_swap
          expr: |
            container_memory_swap{job="cadvisor", image!=""}
            * on (namespace, pod) group_left(node) topk by (namespace, pod) (
              1, max by (namespace, pod, node) (kube_pod_info{job="kube-state-metrics", node!=""})
            )
        - record: namespace_memory:kube_pod_container_resource_requests:sum
          expr: |
            sum by (namespace) (
              sum by (namespace, pod) (
                max by (namespace, pod, container) (
                  kube_pod_container_resource_requests{job="kube-state-metrics", resource="memory"}
                ) * on (namespace, pod) group_left() max by (namespace, pod) (
                  kube_pod_status_phase{job="kube-state-metrics", phase=~"Pending|Running"} == 1
                )
              )
            )
        - record: namespace_cpu:kube_pod_container_resource_requests:sum
          expr: |
            sum by (namespace) (
              sum by (namespace, pod) (
                max by (namespace, pod, container) (
                  kube_pod_container_resource_requests{job="kube-state-metrics", resource="cpu"}
                ) * on (namespace, pod) group_left() max by (namespace, pod) (
                  kube_pod_status_phase{job="kube-state-metrics", phase=~"Pending|Running"} == 1
                )
              )
            )
        - record: namespace_workload_pod:kube_pod_owner:relabel
          expr: |
            max by (namespace, workload, pod) (
              label_replace(
                kube_pod_owner{job="kube-state-metrics", owner_kind="ReplicaSet"},
                "workload", "$1", "owner_name", "(.*)"
              )
            )
          labels:
            workload_type: deployment
        - record: namespace_workload_pod:kube_pod_owner:relabel
          expr: |
            max by (namespace, workload, pod) (
              label_replace(
                kube_pod_owner{job="kube-state-metrics", owner_kind="DaemonSet"},
                "workload", "$1", "owner_name", "(.*)"
              )
            )
          labels:
            workload_type: daemonset
        - record: namespace_workload_pod:kube_pod_owner:relabel
          expr: |
            max by (namespace, workload, pod) (
              label_replace(
                kube_pod_owner{job="kube-state-metrics", owner_kind="StatefulSet"},
                "workload", "$1", "owner_name", "(.*)"
              )
            )
          labels:
            workload_type: statefulset
        - record: namespace_workload_pod:kube_pod_owner:relabel
          expr: |
            max by (namespace, workload, pod) (
              label_replace(
                kube_pod_owner{job="kube-state-metrics", owner_kind="Job"},
                "workload", "$1", "owner_name", "(.*)"
              )
            )
          labels:
            workload_type: job

    - name: node.rules
      rules:
        - record: node:node_num_cpu:sum
          expr: |
            count by (node) (
              sum by (node, cpu) (
                node_cpu_seconds_total{job="node-exporter"}
              )
            )
        - record: ':node_memory_MemAvailable_bytes:sum'
          expr: |
            sum (
              node_memory_MemAvailable_bytes{job="node-exporter"} or (
                node_memory_Buffers_bytes{job="node-exporter"} +
                node_memory_Cached_bytes{job="node-exporter"} +
                node_memory_MemFree_bytes{job="node-exporter"} +
                node_memory_Slab_bytes{job="node-exporter"}
              )
            )
        - record: node:node_cpu_utilisation:avg1m
          expr: |
            1 - avg by (node) (
              sum without (mode) (
                rate(node_cpu_seconds_total{job="node-exporter", mode=~"idle|iowait|steal"}[1m])
              )
            )
        - record: node:node_memory_bytes_available:sum
          expr: |
            sum by (node) (
              node_memory_MemFree_bytes{job="node-exporter"} +
              node_memory_Cached_bytes{job="node-exporter"} +
              node_memory_Buffers_bytes{job="node-exporter"}
            )
        - record: node:node_memory_bytes_total:sum
          expr: |
            sum by (node) (
              node_memory_MemTotal_bytes{job="node-exporter"}
            )
        - record: 'node:node_memory_utilisation:'
          expr: |
            1 - (
              node:node_memory_bytes_available:sum / node:node_memory_bytes_total:sum
            )
        - record: node:node_disk_utilisation:avg_irate
          expr: |
            avg by (node) (
              irate(node_disk_io_time_seconds_total{job="node-exporter", device!=""}[1m])
            )
        - record: node:node_net_utilisation:sum_irate
          expr: |
            sum by (node) (
              irate(node_network_receive_bytes_total{job="node-exporter", device!="lo"}[1m])
              +
              irate(node_network_transmit_bytes_total{job="node-exporter", device!="lo"}[1m])
            )
        - record: 'node:node_filesystem_usage:'
          expr: |
            max by (node) (
              1 - (
                node_filesystem_avail_bytes{job="node-exporter", fstype!=""}
                /
                node_filesystem_size_bytes{job="node-exporter", fstype!=""}
              )
            )
  EOT
}

output "kubernetes_mixin_recording_rules_arn" {
  description = "ARN of the AMP recording-rule group namespace backing the dotdc Kubernetes Views dashboards"
  value       = aws_prometheus_rule_group_namespace.kubernetes_mixin_recording_rules.arn
}
