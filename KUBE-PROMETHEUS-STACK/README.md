# kube-prometheus-stack: a practical guide for EKS and application teams

This is a standalone guide, using a fictional checkout application. It does not depend on a particular infrastructure repository.

## The complete idea in one minute

kube-prometheus-stack is a Helm chart that installs a coordinated **metrics monitoring and alerting system** into Kubernetes. Instead of deploying a separate Prometheus and Grafana for every application, a platform team operates a shared stack, often in a namespace called monitoring.

Think of it as five cooperating jobs:

1. **Exporters and instrumented applications expose measurements.**
2. **Prometheus collects and stores those measurements.**
3. **Prometheus Operator turns Kubernetes monitoring declarations into working configuration.**
4. **Grafana queries the stored measurements and displays dashboards.**
5. **Prometheus evaluates alert rules; Alertmanager routes the resulting alerts to people.**

Installing the stack provides substantial Kubernetes monitoring. It does **not** teach Prometheus your application's business logic, create every application dashboard, or know which team should receive an alert. Application teams supply that information through a small onboarding contract.

There is no subscription API or requirement to send normal metrics to Grafana. Here, “subscribe” means **expose a compatible metrics endpoint and deploy a monitor that the shared Prometheus selects**. [Prometheus overview](https://prometheus.io/docs/introduction/overview/), [Operator getting started](https://prometheus-operator.dev/docs/developer/getting-started/).

## Contents

- [1. What is installed](#1-what-is-installed)
- [2. How the components cooperate](#2-how-the-components-cooperate)
- [3. Metrics, logs and traces are different](#3-metrics-logs-and-traces-are-different)
- [4. Deploying through EKS Blueprints Addons](#4-deploying-through-eks-blueprints-addons)
- [5. What the platform team must configure](#5-what-the-platform-team-must-configure)
- [6. What every application must provide](#6-what-every-application-must-provide)
- [7. A complete application onboarding example](#7-a-complete-application-onboarding-example)
- [8. Turning application metrics into Grafana dashboards](#8-turning-application-metrics-into-grafana-dashboards)
- [9. How alerts fire and reach the right team](#9-how-alerts-fire-and-reach-the-right-team)
- [10. Credentials and external notification services](#10-credentials-and-external-notification-services)
- [11. Security and isolation](#11-security-and-isolation)
- [12. Testing and troubleshooting end to end](#12-testing-and-troubleshooting-end-to-end)
- [13. Operating and upgrading the stack](#13-operating-and-upgrading-the-stack)
- [14. Ownership and readiness checklists](#14-ownership-and-readiness-checklists)
- [15. Glossary and common questions](#15-glossary-and-common-questions)
- [Example files](#example-files)

## 1. What is installed

The exact objects depend on the pinned chart version and enabled values. The table describes a typical installation, including the configuration in this guide. Not every Kubernetes CRD represents a running workload.

| Component or resource | What it does | Typical Kubernetes form |
| --- | --- | --- |
| Prometheus Operator | Watches monitoring declarations and reconciles Prometheus/Alertmanager workloads and their generated configuration. It does not scrape application metrics itself. | Deployment, ServiceAccount and cluster RBAC |
| Prometheus | Discovers targets, repeatedly scrapes metrics, stores time series, evaluates PromQL recording/alert rules, and exposes a query API. | Prometheus custom resource; Operator creates StatefulSet, Pods and configuration |
| Alertmanager | Receives firing alerts, groups/deduplicates them, applies silences/inhibition, and sends notifications to configured receivers. It does not evaluate PrometheusRule expressions. | Alertmanager custom resource; Operator creates StatefulSet and configuration |
| Grafana | Queries data sources and renders dashboards/Explore views. Its own storage holds dashboard/account/configuration state, not the primary Prometheus metric history. | Deployment or StatefulSet, depending on persistence mode |
| kube-state-metrics | Reads Kubernetes objects and exposes their state: desired/ready replicas, Pod phases, restart counters, Job/PVC state, and similar signals. | Deployment and Service |
| node-exporter | Exposes machine-level measurements such as CPU, memory, filesystem and network metrics on supported worker nodes. | DaemonSet: one Pod per eligible node |
| Configuration reloaders | Reload generated configuration into Prometheus/Alertmanager as declarations change. | Containers alongside those workloads |
| Grafana sidecars | Discover selected dashboard/data-source ConfigMaps and provision them into Grafana. Enablement and permissions control their scope. | Containers inside the Grafana Pod |
| Bundled monitoring objects | Define targets for the stack/Kubernetes components and standard alert/recording rules. | ServiceMonitors and PrometheusRules |
| Dashboard/data-source provisioning | Provides starting Kubernetes dashboards and a Prometheus data source. Application dashboards remain your responsibility. | ConfigMaps and Grafana provisioning |
| Admission infrastructure | Validates supported monitoring declarations; chart defaults can include certificate/bootstrap Jobs and webhook configuration. | Services, webhook configurations, Jobs and Secrets |
| Services, RBAC and configuration | Permit discovery/scraping and connect workloads. Some permissions/CRDs are cluster-scoped even when Pods are in monitoring. | Services, Roles/ClusterRoles, bindings, Secrets and ConfigMaps |
| Persistent storage, when enabled | Keeps Prometheus history, Alertmanager notification/silence state and Grafana state across Pod replacement. | PVCs and dynamically provisioned PVs |

kube-state-metrics is not a CPU usage collector: its source is the Kubernetes API's object state. node-exporter provides host metrics. Container usage is commonly obtained from **existing kubelet/cAdvisor endpoints**. The chart configures scraping for those endpoints; it does not install a separate kubelet or cAdvisor DaemonSet. [kube-state-metrics](https://github.com/kubernetes/kube-state-metrics), [node-exporter](https://github.com/prometheus/node_exporter), [Kubernetes system metrics](https://kubernetes.io/docs/concepts/cluster-administration/system-metrics/).

### The custom resource vocabulary

A **CustomResourceDefinition (CRD)** adds an object type to Kubernetes. A **custom resource** is an instance of that type. For example, the ServiceMonitor CRD enables Kubernetes to accept a ServiceMonitor named checkout.

| Declaration | What it describes |
| --- | --- |
| Prometheus | The desired Prometheus instance, discovery scope, resources and persistence. |
| Alertmanager | The desired Alertmanager instance and configuration selection. |
| ServiceMonitor | Which Services/endpoints to scrape, through which named ports, path, interval and authentication. |
| PodMonitor | Which Pods to scrape directly, without a Service. |
| PrometheusRule | PromQL alert rules and/or recording rules for a selected Prometheus. |
| AlertmanagerConfig | Receivers, routes and related alert-notification configuration. |
| Probe | A desired synthetic check through a compatible prober, usually a separately deployed blackbox exporter. |
| ScrapeConfig | Additional supported discovery/scrape arrangements; not normally needed for a standard internal application. |
| PrometheusAgent / ThanosRuler | Definitions supporting optional agent/rule-evaluation architectures. Installing their CRDs does not deploy these systems automatically. |

Chart 91.4.0 bundles the ten CRD kinds listed above. An application usually needs only ServiceMonitor (or PodMonitor) and PrometheusRule; AlertmanagerConfig is optional when the platform fallback route is sufficient. Check APIs served by your actual CRDs, not an arbitrary example from the internet. [Operator API reference](https://prometheus-operator.dev/docs/api-reference/api/).

## 2. How the components cooperate

This diagram separates **configuration** from the actual **metrics and notifications**. Mermaid renders in compatible Markdown viewers; the numbered flow below remains readable without diagram support.

~~~mermaid
flowchart LR
    subgraph APP[Application namespace: shop-prod]
        Pod[Checkout Pods: internal /metrics]
        Service[Metrics Service]
        SM[ServiceMonitor]
        Rules[PrometheusRule]
        Dash[Dashboard ConfigMap]
        Route[Optional AlertmanagerConfig]
        Creds[Team receiver Secret]
    end
    API[Kubernetes API: declarations and endpoints]
    subgraph MON[Shared monitoring namespace]
        Op[Prometheus Operator]
        Prom[Prometheus: scrape, store, evaluate]
        AM[Alertmanager: group and route]
        Graf[Grafana and provisioning sidecars]
    end
    Sources[Node exporter, kube-state-metrics, kubelet]
    People[Notification receiver and team]
    SM -. declaration .-> API
    Rules -. declaration .-> API
    Route -. declaration .-> API
    Service -. endpoint discovery .-> API
    API -. watched resources .-> Op
    Op -. generated configuration .-> Prom
    Op -. generated configuration .-> AM
    Op -. resolves Secret references .-> Creds
    Prom -->|HTTP scrape of discovered Pod endpoints| Pod
    Pod -->|metric samples in scrape response| Prom
    Prom -->|HTTP scrape| Sources
    Graf -->|PromQL query API| Prom
    Dash -. dashboard provisioning .-> Graf
    Prom -->|firing and resolved alerts| AM
    AM -->|notification through configured integration| People
~~~

The Service is the discovery anchor. Prometheus normally scrapes each discovered Pod endpoint, rather than repeatedly querying one load-balanced Service DNS address. Endpoint/EndpointSlice discovery behavior depends on the Operator configuration/version.

End to end:

1. The application updates in-process counters, gauges and histograms as it handles work.
2. Its metrics HTTP handler exposes current measurements.
3. Kubernetes records the application's monitoring resources and endpoint addresses.
4. Operator selects the declarations and generates scrape/rule/notification configuration.
5. Prometheus sends scheduled HTTP requests to the discovered metrics endpoints.
6. Responses become timestamped, labelled samples in Prometheus storage.
7. Grafana asks Prometheus questions through its query API and draws the results.
8. Prometheus independently evaluates selected rules. A matching alert enters pending, then firing after its configured duration.
9. Alertmanager matches alert labels against routes and sends a notification to the real receiver.

Grafana does not need to be open for Prometheus alerts to fire. Operator is the configuration controller, not the metrics collector or the notification sender.

## 3. Metrics, logs and traces are different

| Signal | Example | Does this installation provide it? |
| --- | --- | --- |
| Metrics | Requests/second, error fraction, p95 latency, ready replicas | Yes, for configured exporters/endpoints. |
| Logs | A specific request's error message | No log backend/collector is installed by kube-prometheus-stack. |
| Traces | The path of one request across services | No distributed tracing backend/instrumentation is installed by this chart. |

Grafana can display logs/traces after separate data sources and pipelines are configured. For example, a separate log collector can send logs to Loki, then Grafana can query Loki. Do not draw Loki or a log collector inside kube-prometheus-stack or imply that dashboard filters create secure log isolation. Loki tenancy requires a separately designed authenticated gateway/tenant boundary. [Loki tenant isolation](https://grafana.com/docs/loki/latest/operations/multi-tenancy/).

AWS CloudWatch, Amazon Managed Service for Prometheus and Amazon Managed Grafana are also separate services. A Helm-based local stack does not automatically enable/export to them.

Kubernetes metrics-server is separate too: it primarily serves current resource measurements through the Metrics API for tools/autoscaling. It is not Prometheus's historical store or application alert engine. Using application metrics to drive an HPA requires a separately configured adapter/custom or external metrics path; adding a ServiceMonitor alone does not configure autoscaling. [metrics-server documentation](https://github.com/kubernetes-sigs/metrics-server).

## 4. Deploying through EKS Blueprints Addons

### What “EKS add-on” means here

The AWS-IA **EKS Blueprints Addons Terraform module** offers a kube-prometheus-stack integration. Terraform invokes its Helm-based add-on implementation, which installs the upstream chart.

This is **not** an AWS-managed kube-prometheus-stack resource created with aws_eks_addon. The platform remains responsible for Helm values, upgrades, capacity, storage, credentials, routing and operations. [Blueprints Addons module](https://registry.terraform.io/modules/aws-ia/eks-blueprints-addons/aws/latest), [verified v1.21.0 implementation](https://github.com/aws-ia/terraform-aws-eks-blueprints-addons/blob/v1.21.0/main.tf#L3126-L3173).

Use one chart owner. Integrate the configuration into your existing add-on module/state instead of also installing the same release using helm CLI, another Terraform root or an independent GitOps Helm owner.

### Prerequisites before enabling

- A reachable, working EKS cluster with compatible Kubernetes and supported worker nodes.
- Terraform runner AWS permissions and EKS/Kubernetes authorization, including the required cluster-scoped installation permissions.
- Providers bound to the intended cluster's endpoint and CA; explicit account/region checks and an explicit context for operational kubectl commands.
- Sufficient node allocatable CPU/memory and suitable security settings for node-exporter's host access.
- A working storage provisioner and permissions. This example assumes **EC2-backed EKS plus the standard EBS CSI driver**.
- For the supplied credential example: a ready shared External Secrets Operator (ESO), its CRDs serving external-secrets.io/v1, and a controller AWS identity that can read exactly the intended secrets.
- For the supplied Terraform wiring: an existing IAM OIDC provider for the cluster and an existing ESO IAM role. Alternative identity arrangements must be adapted explicitly rather than passing a fictitious OIDC ARN.
- Real Grafana admin credentials and a real Platform/SRE notification destination provisioned in the external secret backend.
- Network paths for API/discovery, DNS, scraping and required outbound notifications/secret retrieval.

Fargate does not support DaemonSets or EBS-mounted Pods, so this example is not a Fargate-only design. EKS Auto Mode storage uses the ebs.csi.eks.amazonaws.com provisioner instead of the standard ebs.csi.aws.com provisioner. Select the correct storage and compute arrangement before adapting the example. [EKS Fargate](https://docs.aws.amazon.com/eks/latest/userguide/fargate.html), [EKS EBS storage](https://docs.aws.amazon.com/eks/latest/userguide/ebs-csi.html).

### The example deployment boundary

The [Terraform example](examples/platform/main.tf) targets an **existing cluster**; it is not cluster creation code. It:

1. Reads the intended EKS endpoint/CA/version and uses explicit provider authentication.
2. Creates the monitoring namespace and an encrypted, expandable gp3 StorageClass.
3. Attaches exact-secret read permissions to an existing shared ESO IAM role.
4. Reads a small [values override file](examples/platform/values.yaml).
5. Renders a list of [platform declarations](examples/platform/platform-manifests.yaml.tftpl) using secret identifiers, not credential values.
6. Supplies that list as extraManifests to one Blueprints-owned Helm release.
7. Enables wait, job waiting, atomic failure handling, cleanup and a bounded timeout.

The module version 1.21.0 is a **known verified interface pin**, not a claim it is the newest Terraform module. Chart 91.4.0 is an explicit chart pin verified on this guide's date. Provider constraints intentionally use the AWS v5 / Kubernetes v3 / Helm v2 syntax family. When selecting a newer module/provider family, review its migration guide and revalidate these examples. Module version, chart version, Operator version and provider versions are different things.

The exact chart is [91.4.0](https://github.com/prometheus-community/helm-charts/tree/kube-prometheus-stack-91.4.0/charts/kube-prometheus-stack), with Operator v0.94.0 and Kubernetes constraint >=1.25.0-0. Recheck the [official index](https://prometheus-community.github.io/helm-charts/index.yaml) when implementing; a later stable chart should be reviewed and pinned, not requested through a floating latest value.

### Why the prerequisites do not require a second monitoring state

ESO and its APIs exist before this release. Helm installs the chart's monitoring CRDs before normal chart manifests; its normal manifests can therefore include the platform AlertmanagerConfig. ESO asynchronously materializes the Grafana Secret, allowing Grafana to become ready during Helm's bounded wait. Operator reconciles Alertmanager configuration after its object/Secret become available.

~~~mermaid
flowchart TD
    Cluster[Existing cluster and reachable API]
    Ready[Ready ESO, supported storage and worker capacity]
    Boot[Namespace, StorageClass, exact-secret IAM permissions]
    Helm[Blueprints Helm release]
    CRD[Chart installs monitoring CRDs first]
    Extra[Normal templates plus platform extraManifests]
    ESO[ESO creates Kubernetes Secrets]
    Operator[Operator configures Prometheus and Alertmanager]
    Work[Workload readiness within Helm timeout]
    Test[Configuration acceptance and real alert-delivery test]
    Cluster --> Ready --> Boot --> Helm --> CRD --> Extra
    Extra --> ESO --> Work
    Extra --> Operator --> Work
    Work --> Test
~~~

Do not set wait/atomic false to hide failed Secret reconciliation. Conversely, Helm readiness is not proof that Alertmanager's destination works. Functional checks follow installation.

If provisioning the cluster or ESO in the same broader infrastructure project, preserve real dependency order. Providers or CRD-dependent resource schemas can need a live API at plan time; adding depends_on does not magically make every first-cluster plan valid. Establish cluster/bootstrap readiness before planning API-dependent add-ons. [Helm CRD lifecycle](https://helm.sh/docs/chart_best_practices/custom_resource_definitions/).

### Applying intentionally

The example starts disabled. Supply metadata inputs through your normal reviewed configuration/CI path, then enable after prerequisites are verified. Plain shell assignments are not exported automatically.

~~~bash
export TF_VAR_cluster_name="example-eks"
export TF_VAR_aws_region="eu-central-1"
export TF_VAR_aws_account_id="111122223333"
export TF_VAR_eso_role_name="existing-shared-eso-role"
export TF_VAR_grafana_secret_arn="REPLACE_WITH_REAL_GRAFANA_SECRET_ARN"
export TF_VAR_platform_receiver_secret_arn="REPLACE_WITH_REAL_PLATFORM_RECEIVER_SECRET_ARN"
export TF_VAR_enable_monitoring="true"
terraform init
terraform plan -out=monitoring.tfplan
# Review the plan and intended account/cluster before running:
terraform apply monitoring.tfplan
~~~

Run these commands from the integrated Terraform root, not from an unrelated folder. Use the existing secure remote backend/locking; the teaching example does not configure a new backend. Plan files and state must be access-controlled. Required-input protection uses a blocking resource precondition, not warning-only check blocks. [Terraform validation behavior](https://developer.hashicorp.com/terraform/language/validate).

## 5. What the platform team must configure

Installing default values is not a production design. [Version-pinned chart values reference](https://github.com/prometheus-community/helm-charts/blob/kube-prometheus-stack-91.4.0/charts/kube-prometheus-stack/values.yaml).

### Discovery scope and the opt-in label

This guide uses one contract: monitoring declarations carry **release: kube-prometheus-stack**. It is an agreed selector label, not a magic subscription keyword or necessarily the application's own Helm release name.

The [values file](examples/platform/values.yaml) explicitly selects labelled ServiceMonitors, PodMonitors, PrometheusRules, Probes and ScrapeConfigs across namespaces. Alertmanager separately selects labelled AlertmanagerConfigs across namespaces. Grafana selects dashboards by a different label: grafana_dashboard: "1".

There are three distinct label matches for ServiceMonitor onboarding:

| Match | Selector lives on | Labels must exist on |
| --- | --- | --- |
| Prometheus chooses a monitor | Prometheus serviceMonitorSelector | ServiceMonitor metadata |
| Monitor chooses Services | ServiceMonitor spec.selector | Service metadata |
| Service chooses Pods | Service spec.selector | Pod template metadata |

There are also **two different namespace scopes**:

- Prometheus serviceMonitorNamespaceSelector selects where monitor objects may live.
- ServiceMonitor spec.namespaceSelector selects where the target Services may live.

Allowing monitors in all namespaces does not automatically make each monitor select Services everywhere. The application example intentionally restricts its target scope to shop-prod.

At the Operator API level an empty selector object commonly means “all,” while a null object selector can mean “none” and a null namespace selector can mean “own namespace.” Helm can substitute release-label defaults through SelectorNilUsesHelmValues options. Use explicit matchLabels/namespace scopes and inspect the generated resources rather than assuming null and {} are equivalent. Application pods and every Kubernetes namespace do not need the release label in this example.

### Cluster targets appropriate for EKS

Keep node-exporter, kube-state-metrics, kubelet/cAdvisor and reachable API/DNS monitoring. Disable unreachable managed-control-plane targets, and review the corresponding bundled alerts/rules. The example disables direct etcd, scheduler and controller-manager scraping, and conservatively disables kube-proxy scraping until its endpoint is verified.

A self-managed cluster may expose targets that EKS does not. Do not silence every failing target without diagnosing it, or assume these exclusions provide visibility into all managed-control-plane internals. Additional AWS/control-plane telemetry is a separate configuration task.

### Persistence, retention and resources

The example enables encrypted gp3 persistence for all three stateful consumers: Prometheus, Alertmanager and Grafana. Grafana explicitly uses StatefulSet persistence mode; deployments with different values may render as a Deployment instead.

Prometheus uses 100Gi storage, 35-day time retention and an 80GB size cap as **illustrative starting values**. If the size cap is reached earlier, older data can be removed before 35 days. Disk headroom is needed for WAL/head/compaction and operating conditions. Do not claim a 30+ day guarantee until ingestion/cardinality/load testing proves it. [Prometheus storage](https://prometheus.io/docs/prometheus/latest/storage/).

Set requests/limits for the Operator, Prometheus, Alertmanager, Grafana, exporters and sidecars. Count all containers and replicas when comparing requests with node allocatable capacity. A single replica is not HA. Stable worker placement, multiple replicas where appropriate, distribution across failure domains, EBS zone constraints and Grafana database design need deliberate availability planning.

The example uses WaitForFirstConsumer so storage provisioning can consider Pod scheduling. Retain helps prevent automatic PV backing-volume deletion, but is not a backup: PVC deletion can still lose application availability and require manual recovery. Define EBS snapshots, Grafana/database backup and restoration tests. [Kubernetes StorageClasses](https://kubernetes.io/docs/concepts/storage/storage-classes/).

### Data sources and alert routing

Provision one stable Grafana Prometheus data-source UID, here prometheus. The chart's data-source template points Grafana at the shared Prometheus Service. Dashboard JSON refers to the UID; it does not contain metric samples.

Provide a real Platform/SRE root receiver and optional labelled application routing. OnNamespace confines selected application AlertmanagerConfigs to alerts carrying the matching namespace label. The explicitly referenced platform root configuration is global and provides fallback routing; it must not be constrained to monitoring-only alerts. Never leave the enabled platform using only the chart's null receiver.

## 6. What every application must provide

An application without /metrics still has infrastructure signals: Pod readiness/restarts, replicas and container/node usage. Prometheus cannot infer requests, failures, queue lag or business outcomes from those signals.

For application-specific monitoring, provide the following:

| Item | Required for | Owner |
| --- | --- | --- |
| Instrumentation or exporter | Actual application/business measurements | Application team |
| Internal metrics endpoint | Prometheus-compatible scrape response | Application team |
| Named metrics container port and Service, or direct Pod port | Reachable scrape targets | Application deployment |
| Compatible ServiceMonitor or PodMonitor | Declarative target registration | Application deployment |
| PrometheusRule with scoped expressions and useful labels | App alerts and optional precomputed series | Application team |
| Dashboard JSON / labelled ConfigMap | App-specific Grafana visualizations | Application team |
| Optional AlertmanagerConfig and receiver Secret | Dedicated team destination rather than fallback | App team, with platform approval |
| Deployment RBAC and network access | Creating declarations and reaching endpoints | Platform and app owners |
| Metric/alert tests and runbook | Trusted data and actionable response | Application team |

You do **not** install a Prometheus/Grafana per application, hard-code Pod IPs, or routinely edit the central Prometheus configuration for every new ServiceMonitor.

### Does the endpoint have to be /metrics?

No. /metrics is conventional. A framework may expose /actuator/prometheus or another path; the monitor's path must match. What matters is a reachable Prometheus/OpenMetrics response with a supported Content-Type and format—not a JSON business API that happens to be called metrics.

Reuse existing instrumentation when it is correct. Add an exporter or client library when needed. The endpoint should bind to a reachable Pod interface, not only localhost; keep it internal and protect it appropriately. Scrape authentication/TLS can be configured through monitor endpoint settings and Secret references. [Prometheus exporters](https://prometheus.io/docs/instrumenting/exporters/).

### Useful measurements, without unsafe labels

- HTTP services: request counter, failures, request-duration histogram and in-flight gauge.
- Workers: completed/failed work, backlog, processing duration and progress/heartbeat signals.
- Databases/third-party systems: compatible exporters, using their documented permissions.
- Static sites: web-server exporter and/or separately deployed synthetic prober; browser JavaScript is not a normal Pod scrape endpoint.
- Short-lived Jobs: Kubernetes Job-state metrics and purpose-specific completion signals. A Pushgateway is a separate, limited design choice, not the default onboarding path. [Pushgateway guidance](https://prometheus.io/docs/practices/pushing/).

Counter values increase until restart; use rate/increase to reason about activity. Gauges move up/down. Histograms represent distributions; this guide's latency example uses classic histogram buckets. [Metric types](https://prometheus.io/docs/concepts/metric_types/), [instrumentation guidance](https://prometheus.io/docs/practices/instrumentation/).

Use bounded labels such as method, status and route template. Do not use user IDs, tokens, emails, request IDs or raw URLs containing arbitrary IDs. Each distinct label combination creates another time series; histograms multiply the count through buckets. Counters should end in _total and durations use seconds. [Naming and labels](https://prometheus.io/docs/practices/naming/).

## 7. A complete application onboarding example

The fictional checkout deployment runs in shop-prod and already implements an internal metrics handler on port 9090. Its Pod template needs matching labels and a named port:

~~~yaml
metadata:
  labels:
    app.kubernetes.io/name: checkout
spec:
  containers:
    - name: checkout
      # Supply your own real instrumented image and normal deployment settings.
      ports:
        - name: metrics
          containerPort: 9090
~~~

This is a Pod-template fragment, not a complete Deployment. Naming a containerPort does not create an HTTP server or make an uninstrumented image emit metrics.

A real scrape response can contain values such as:

~~~text
# HELP checkout_requests_total Completed checkout HTTP requests.
# TYPE checkout_requests_total counter
checkout_requests_total{method="POST",route="/checkout",status="200"} 1240
checkout_requests_total{method="POST",route="/checkout",status="500"} 12
# HELP checkout_in_flight_requests Currently executing requests.
# TYPE checkout_in_flight_requests gauge
checkout_in_flight_requests 3
~~~

Use a client library's handler rather than manually maintaining a text response. The application must update these counters in its request path; simply defining the metric leaves a permanently uninformative value. Initialize known bounded label combinations as appropriate so zero errors are distinguishable from missing instrumentation.

Deploy [onboarding.yaml](examples/application/onboarding.yaml) through the application's normal chart/manifests workflow. It contains:

1. A ClusterIP metrics Service selecting checkout Pods and targeting the named metrics port.
2. A labelled ServiceMonitor selecting that Service and scraping /metrics every 30 seconds.
3. A labelled PrometheusRule with a recording rule and two illustrative alerts.
4. A dashboard ConfigMap labelled for the shared Grafana sidecar.

The monitor's endpoint port is the **Service port name**, not the integer 9090. The metrics Service can be separate from the public API Service; it needs no ingress or load balancer.

The application example is **raw manifest YAML**, not a ready-made Helm template. If putting it under a Helm chart's templates directory, escape Prometheus annotation expressions so Helm does not try to evaluate $labels itself. For example, this Helm template line preserves the expression for Prometheus:

~~~yaml
description: 'Prometheus cannot scrape {{ "{{" }} $labels.instance {{ "}}" }}.'
~~~

With a raw kubectl/Kustomize manifest, keep the original {{ $labels.instance }} expression instead. Test the rendered application chart, not only the unrendered file.

All paths/names/namespace/metric names are a coordinated example. Adapt them together. After deployment, selected Prometheus target metadata normally adds namespace, service, pod and instance labels. Verify them in the actual target/series view; application-exported labels can collide with discovery labels.

For a direct PodMonitor alternative, use the same release label, select the Pod labels and configure podMetricsEndpoints with the named **container** metrics port. Choose ServiceMonitor or PodMonitor for the same target rather than accidentally scraping it twice.

Monitoring CRDs must exist before the application deploys these objects. An app can gate optional monitoring manifests behind a Helm value until the platform rollout is ready, but should not silently omit them while claiming monitoring is active. Application deployment credentials need authorization for monitoring.coreos.com resources; namespace admin assumptions do not replace an explicit permission check.

A platform-managed namespace Role can explicitly grant the deployment identity permission to publish the approved monitoring objects:

~~~yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: application-monitoring-publisher
  namespace: shop-prod
rules:
  - apiGroups: [monitoring.coreos.com]
    resources: [servicemonitors, podmonitors, prometheusrules, alertmanagerconfigs]
    verbs: [get, list, watch, create, update, patch, delete]
~~~

Bind it through an approved RoleBinding to the application's actual deploy group/ServiceAccount. This Role fragment does not grant Services/ConfigMaps or ESO resources; include only necessary permissions in the existing deployment role. Developers should not receive unrestricted cluster-level Operator permissions just to onboard one namespace.

## 8. Turning application metrics into Grafana dashboards

### Where the data lives

The flow is application → scrape response → Prometheus time-series storage → Grafana query. Grafana does not receive application metric pushes. Its provisioned Prometheus data source runs PromQL requests against the shared server. [Grafana Prometheus data source](https://grafana.com/docs/grafana/latest/datasources/prometheus/).

Start in Grafana Explore, select Prometheus, and confirm the raw metric exists. Then use meaningful calculations:

~~~promql
# Request throughput, not the cumulative lifetime count
sum(rate(checkout_requests_total{namespace="shop-prod"}[5m]))

# Server-error fraction, between 0 and 1 during nonzero traffic
sum(rate(checkout_requests_total{namespace="shop-prod",status=~"5.."}[5m]))
/
sum(rate(checkout_requests_total{namespace="shop-prod"}[5m]))

# p95 latency, if the application exports compatible classic histogram buckets
histogram_quantile(
  0.95,
  sum by (le) (
    rate(checkout_request_duration_seconds_bucket{namespace="shop-prod"}[5m])
  )
)
~~~

Rates require enough samples; a newly scraped counter does not immediately provide a stable five-minute rate. Zero traffic or an absent error series can produce no result/NaN in a ratio; decide how the dashboard should show “no traffic” without disguising missing telemetry as success. Use identical classic bucket boundaries when aggregating replicas. [PromQL functions](https://prometheus.io/docs/prometheus/latest/querying/functions/).

The example dashboard has request/error panels and a stable UID, checkout-overview. Its data-source UID is prometheus, matching platform provisioning. Add a latency panel only after that histogram actually exists.

### Dashboard provisioning is separate from scrape registration

A ServiceMonitor makes measurements discoverable. A dashboard ConfigMap provides layout/query JSON. A PrometheusRule defines calculations/alerts. None automatically creates the others.

Grafana's sidecar watches ConfigMaps carrying grafana_dashboard: "1" in the configured scope, writes dashboard files and provisions them. Application dashboard changes should remain in version control; manual edits to provisioned dashboards can be overwritten. Avoid duplicate dashboard UIDs and duplicate data-source definitions. [Grafana community Helm documentation](https://github.com/grafana-community/helm-charts/blob/main/charts/grafana/README.md).

The example sidecar searches all namespaces. This is convenience for trusted teams, not permission to treat arbitrary dashboard/data-source ConfigMaps as harmless. Limit who can publish them.

Recording rules can save expensive expressions as new time series, such as checkout:request_rate5m. Grafana can query these instead of repeating a heavy calculation. Recording rules do not notify anyone. [Recording rules](https://prometheus.io/docs/prometheus/latest/configuration/recording_rules/).

## 9. How alerts fire and reach the right team

### Evaluation happens in Prometheus

The example rules are deliberately distinct:

- CheckoutMetricsUnreachable fires when a discovered target has up == 0 for two minutes. It means scraping failed, not necessarily that the public API is unavailable.
- CheckoutHighErrorRate requires a server-error fraction above 5% and throughput above one request/second for ten minutes. These thresholds are illustrative, not a production SLO.

The rule expression and any recording dependencies must refer to metrics the application really emits. Each result becomes a labelled alert instance. The error rule aggregates by namespace so that label survives and can drive namespace routing. Aggregating away namespace without restoring a correct, reviewed namespace label breaks that routing.

An up == 0 rule does not detect a monitor that was never selected or an endpoint that completely disappeared: there may be no up series. Complement it with expected-deployment/target-presence checks and independent service/synthetic health signals. Handle intentional scale-to-zero/removal explicitly.

Prometheus reevaluates rules on the evaluation interval:

1. False condition: inactive.
2. First true evaluation: pending.
3. Continuously true for the rule's for duration: firing.
4. Condition clears: no longer firing; the alert resolves.

Scrape/evaluation schedules, the rolling query window and Alertmanager groupWait add latency. The ten-minute for does not mean an exact ten-minute wall-clock notification from the first bad request. [Prometheus alert rules](https://prometheus.io/docs/prometheus/latest/configuration/alerting_rules/).

### Alertmanager controls notifications, not thresholds

Alertmanager receives the alert's labels/annotations, then:

- Groups related alerts into fewer messages.
- Deduplicates repeated/HA submissions.
- Uses route matchers to choose receivers.
- Honors silences and inhibition rules to suppress selected notifications.
- Retries supported notification delivery and sends resolved messages when configured.

groupWait delays an initial group notification; groupInterval controls later notifications for changes in an existing group; repeatInterval controls reminders for ongoing alerts. The example uses 30 seconds, five minutes and four hours. A silence does not make the Prometheus expression false or erase stored metrics. [Alertmanager concepts](https://prometheus.io/docs/alerting/latest/alertmanager/).

### Platform fallback plus application routes

The platform example references platform-routing in Alertmanager's own monitoring namespace as its root configuration. Its receiver is a real Platform/SRE webhook. Unmatched alerts fall back there, including cluster alerts without an application namespace.

An application can use this fallback without creating its own AlertmanagerConfig. If it needs a team receiver, [optional-team-routing.yaml](examples/application/optional-team-routing.yaml) defines one in shop-prod. The Operator selects it by the release label and applies OnNamespace: it must match namespace=shop-prod, plus the example's service=checkout matcher.

Receiver Secret references resolve within the AlertmanagerConfig's namespace. Team credentials therefore belong in shop-prod, even though Alertmanager runs in monitoring. Operator resolves these references into managed configuration; manually copying every team Secret into monitoring is not the contract. [Operator alert routing](https://prometheus-operator.dev/docs/developer/alerting/).

The explicit platform root is the global configuration; selected application configs are namespace-bound additions. Do not apply an ordinary monitoring-namespace-only matcher to the root, or assume every selected config is global.

Matching a team route does not automatically CC Platform/SRE. Route ordering/continuation and the generated tree determine whether multiple receivers get an alert. Review intentional escalation/fan-out separately. Likewise, missing an invalid config does not prove the desired fallback behavior; inspect the generated config and test the result.

### Grafana alerting is another possible evaluator

Grafana can evaluate its own alerts, but this guide deliberately uses **PrometheusRule → Prometheus → Alertmanager** as the application alert path. Dashboard panels are not alerts. Creating the same condition in both Grafana and Prometheus without a routing plan produces duplicate/confusing ownership.

## 10. Credentials and external notification services

kube-prometheus-stack does not create your Slack/email account, provision external secret values, or deploy ESO automatically. The examples integrate an already functioning ESO controller.

The platform owner creates two external secret records:

| Record | Properties | Used by |
| --- | --- | --- |
| Grafana admin record | admin-user, admin-password | ESO creates grafana-admin; Grafana references it. |
| Platform receiver record | webhook_url, username, password | ESO creates platform-receiver; root AlertmanagerConfig references it. |

The optional team receiver uses a third external record with the same receiver properties. The example's generic webhook assumes an endpoint accepting **Alertmanager's JSON payload over HTTPS with HTTP basic authentication**. It does not assume every chat webhook supports this. Use native slackConfigs/emailConfigs/etc or a separately operated compatible adapter when appropriate, and validate support in the pinned CRD/integration.

In AlertmanagerConfig, HTTP basic credentials are nested under **webhookConfigs[].httpConfig.basicAuth**; they are not a direct webhookConfigs field. urlSecret holds a Secret selector for the URL, not the literal URL. This keeps values out of chart files/Terraform output. [Alertmanager notification configuration](https://prometheus.io/docs/alerting/latest/configuration/).

SecretStore describes the backend/region/authentication method; ExternalSecret describes which remote properties become Kubernetes Secret keys. Omitting explicit AWS auth in these examples deliberately uses the controller Pod's established AWS identity. It is valid only when that identity has the required policy. The Terraform policy grants the platform's two exact ARNs; optional team secrets require additional approved scope. Customer-managed KMS keys can require kms:Decrypt permissions and key-policy access too. [ESO AWS provider](https://external-secrets.io/latest/provider/aws-secrets-manager/), [SecretStore](https://external-secrets.io/latest/api/secretstore/).

ESO sync/Ready status verifies retrieval, not actual receiver compatibility. Rotating a Secret also does not guarantee every consumer immediately uses it: verify notification reload behavior and note that Grafana admin bootstrap credentials are not a general-purpose automatic rotation mechanism for an already persisted admin account. Plan account/SSO credential lifecycle explicitly. [ExternalSecret behavior](https://external-secrets.io/latest/api/externalsecret/).

## 11. Security and isolation

### Namespace discovery is not tenant isolation

One shared Prometheus stores cluster/app data together. Kubernetes namespace RBAC does not add per-user query authorization to Prometheus, and a Grafana folder/dashboard filter is not an enforced data boundary. A user with a shared query-capable data source may query other namespaces.

If teams require strong separation, design an enforced query gateway/tenant backend, separate data-source/organization arrangements with real authorization, or separate Prometheus instances. Do not claim this trusted-team shared stack is secure multi-tenancy just because queries include namespace labels. [Prometheus security model](https://prometheus.io/docs/operating/security/), [Grafana permissions](https://grafana.com/docs/grafana/latest/administration/roles-and-permissions/).

OnNamespace limits routing for selected configurations, not all attacks. A team able to author arbitrary PrometheusRule expressions can query shared data or set misleading alert labels unless admission/review policies constrain it. Scope rule expressions/labels and govern monitoring declarations.

### Separate permissions by role

- Platform installers: approved cluster-level CRD/webhook/RBAC permissions and infrastructure IAM changes.
- Application deployers: only their namespace's permitted monitors/rules/dashboard ConfigMaps and optional routing/ESO objects.
- Operator/Prometheus: required cross-namespace discovery and Secret/configuration access, not arbitrary developer impersonation.
- ESO: exact external-secret read permissions and an approved SecretStore model. A shared controller with broad IAM access can become a cross-team secret exposure path if anyone can request arbitrary remote keys.
- Grafana users: authenticated identities/roles; provisioned data-source access must match the intended security model.

Use kubectl auth can-i to test real deploy identities. Secrets' base64 encoding is not encryption; protect etcd/EKS encryption, API access, backups, state and logs. Do not export credential values through Terraform or paste them into review comments.

### Network paths to allow

Prometheus needs access to app metrics ports, exporters/kubelet and Kubernetes discovery. Operator needs API and appropriate configuration/Secret reads. Grafana needs Prometheus. Alertmanager needs chosen outbound notification destinations (and peer traffic if HA). ESO needs its backend; DNS must remain reachable.

Use NetworkPolicies supported/enforced by the actual cluster networking to restrict these paths. EKS security groups/network policies must be checked together. Do not expose Prometheus/Alertmanager or unauthenticated Grafana through public ingress by default. Notification traffic and backend retrieval may leave the cluster: “all traffic stays internal” is incorrect. [EKS network-policy guidance](https://docs.aws.amazon.com/eks/latest/userguide/cni-network-policy.html).

## 12. Testing and troubleshooting end to end

Use an explicitly selected cluster context and account/region. A post-apply check cannot undo writes to the wrong cluster. The commands below are diagnostic examples; adapt the context and actual resource names.

### Step 1: APIs and authorization

~~~bash
kubectl --context YOUR_CONTEXT get crd servicemonitors.monitoring.coreos.com
kubectl --context YOUR_CONTEXT get crd alertmanagerconfigs.monitoring.coreos.com
kubectl --context YOUR_CONTEXT get crd externalsecrets.external-secrets.io
kubectl --context YOUR_CONTEXT auth can-i create servicemonitors.monitoring.coreos.com -n shop-prod
kubectl --context YOUR_CONTEXT auth can-i create prometheusrules.monitoring.coreos.com -n shop-prod
~~~

Confirm served versions, including v1 for the supplied ESO examples and v1alpha1 for the pinned AlertmanagerConfig example. If CRDs are missing, register the platform first; don't deploy a second application-local stack as a workaround.

### Step 2: application and endpoint

~~~bash
kubectl --context YOUR_CONTEXT -n shop-prod get pods -l app.kubernetes.io/name=checkout
kubectl --context YOUR_CONTEXT -n shop-prod get endpointslices -l kubernetes.io/service-name=checkout-metrics
kubectl --context YOUR_CONTEXT -n shop-prod port-forward svc/checkout-metrics 19090:9090
# In another terminal:
curl --fail --include http://localhost:19090/metrics
~~~

Check successful response, supported Content-Type and real metric values. Port-forward success does not prove monitoring-to-app NetworkPolicy connectivity; test that path separately without logging secrets.

### Step 3: selection and scraping

~~~bash
kubectl --context YOUR_CONTEXT -n shop-prod get servicemonitor checkout -o yaml
kubectl --context YOUR_CONTEXT -n monitoring get prometheus -o yaml
kubectl --context YOUR_CONTEXT -n monitoring port-forward svc/kube-prometheus-stack-prometheus 19091:9090
~~~

In Prometheus at localhost:19091, inspect Targets and query up{namespace="shop-prod",service="checkout-metrics"}, then checkout_requests_total. If the target is absent, inspect labels/namespace selectors, RBAC and Operator events. If present but down, inspect target errors, ports/path/Content-Type, TLS/authentication and network connectivity. [Operator troubleshooting](https://prometheus-operator.dev/docs/platform/troubleshooting/).

### Step 4: dashboard

~~~bash
kubectl --context YOUR_CONTEXT -n shop-prod get configmap checkout-dashboard
kubectl --context YOUR_CONTEXT -n monitoring port-forward svc/kube-prometheus-stack-grafana 13000:80
~~~

Log in through your approved credential process, select Prometheus in Explore, then open Checkout overview. If raw queries work but the dashboard does not, inspect JSON provisioning, UID, namespace/metric labels and time range. Never add a second data source merely to hide a wrong UID.

### Step 5: routing and credentials

~~~bash
kubectl --context YOUR_CONTEXT -n monitoring get externalsecret
kubectl --context YOUR_CONTEXT -n monitoring get alertmanagerconfig platform-routing -o yaml
kubectl --context YOUR_CONTEXT -n shop-prod get alertmanagerconfig checkout-team -o yaml
kubectl --context YOUR_CONTEXT -n monitoring port-forward svc/kube-prometheus-stack-alertmanager 19093:9093
~~~

Check ESO Ready and Operator acceptance where supported/enabled, plus nonempty required Secret keys without printing values. Inspect Alertmanager's generated routing and delivery metrics/logs safely. A Ready Pod and an accepted CR are necessary but not proof of notification success.

### Step 6: real firing and resolved test

In a disposable/test namespace, create a reviewed temporary PrometheusRule selected by the same contract with expression vector(1), short for, and an explicit correct namespace/service label. Warn the recipient first; use an approved test destination. Verify it appears in Prometheus, reaches Alertmanager and arrives at the intended receiver. Then change the expression to vector(0) == 1 so it produces **no alert result**, and verify a resolved notification. Merely changing to vector(0) still produces a result and can keep an alert active.

Repeat a namespace-routed test, and check that a different namespace does not reach the wrong team. Remove the temporary test resources afterward. Also test invalid receiver credentials and confirm a failed delivery is observable; do not mark installation successful solely because pods are Ready.

### What to validate before applying

Terraform fmt/validate and Helm lint/template catch important syntax/render problems. They do not fully validate extra custom resources against Kubernetes schemas or prove network delivery. Validate rendered ServiceMonitor/PrometheusRule/AlertmanagerConfig against the **pinned CRDs**, perform server-side dry runs in an appropriately prepared disposable cluster, and unit-test PromQL alert behavior with promtool. [Rule unit testing](https://prometheus.io/docs/prometheus/latest/configuration/unit_testing_rules/).

## 13. Operating and upgrading the stack

- Monitor the monitoring system: scrape failures, rule evaluation errors, storage fullness, Operator reconciliation, notification failures and loss of monitoring availability.
- Track ingestion/cardinality and actual retained history. Adjust storage/retention/resources with measurements.
- Keep dashboards/rules in source control and attach real runbooks/escalation ownership. Alert on symptoms users care about, not every transient internal event.
- Define backup/restore and lifecycle behavior for PVCs and external credentials.
- Pin chart/module/provider versions; retain provider lockfiles and reviewed values.
- Review major-version migration notes and CRD changes before upgrading. Helm rollback does not guarantee reversal of CRD schemas or application database migrations.
- Coordinate application manifests with served CRD versions. Updating the platform cannot fix an application's unsupported API version automatically.
- Before disabling/uninstalling, determine which apps depend on the CRDs. Helm usually leaves CRDs behind; deleting a CRD removes all instances of that kind cluster-wide. Do not delete shared CRDs to tidy up a release.

The 91.4.0 migration path crosses Grafana chart v13, control-plane authorization changes and Operator/RBAC updates. Treat it as a tested upgrade, not just “latest is better.” [Pinned upgrade guide](https://github.com/prometheus-community/helm-charts/blob/kube-prometheus-stack-91.4.0/charts/kube-prometheus-stack/UPGRADE.md).

## 14. Ownership and readiness checklists

### Platform ready

- [ ] One add-on/Helm owner, explicit versions and reviewed override values.
- [ ] Exact cluster/account/region target checked before mutation.
- [ ] ESO/API/storage/compute prerequisites ready and correctly authorized.
- [ ] Cross-namespace opt-in selectors, restricted publisher permissions and app deploy RBAC agreed.
- [ ] Requests/limits, encrypted persistence, measured retention and availability assumptions documented.
- [ ] Stable Grafana data-source UID, authenticated access and deliberate dashboard publishing scope.
- [ ] Real root receiver, namespace route strategy, least-privilege secrets and tested delivery.
- [ ] Fresh install, secret failure, rollback, upgrade, disable/destroy and recovery exercised.
- [ ] No misleading guarantees about logs, business metrics, HA or tenant isolation.

### Application ready

- [ ] Real internal metrics handler and compatible exposition format/Content-Type.
- [ ] Useful bounded metrics actually updated by the application's work.
- [ ] Matching Pod/Service labels and named metrics port.
- [ ] Correctly labelled ServiceMonitor or PodMonitor selected by shared Prometheus.
- [ ] Successful discovered target and real series/query checks.
- [ ] Scoped alert rules with namespace/team/service labels and tested thresholds/runbooks.
- [ ] Dashboard JSON with matching data-source UID and unique dashboard UID.
- [ ] Optional team route/ESO secret authorized and verified, or explicit use of platform fallback.
- [ ] Firing/resolved delivery and namespace routing verified.
- [ ] Monitoring resources deployed/versioned with the application, not manually recreated on every release.

## 15. Glossary and common questions

| Term | Plain meaning |
| --- | --- |
| Scrape | Prometheus sends an HTTP request to read measurements. |
| Time series | One metric name plus one unique label set, with samples over time. |
| Exporter | A process translating an existing system's measurements into a scrapeable format. |
| PromQL | The query/calculation language used by Prometheus. |
| Recording rule | A periodically evaluated query saved as another metric series. |
| Alert rule | A query whose matching results become pending/firing alerts. |
| Receiver | An Alertmanager notification destination/integration. |
| Reconciliation | A controller repeatedly makes running/configured state match declarations. |
| Data-source UID | Stable identifier a Grafana dashboard uses to choose its query backend. |

**Does every app need /metrics?** Only for directly scraped app-specific metrics; the path can differ. Infrastructure monitoring remains possible without application instrumentation.

**Does adding a label to the Deployment subscribe it?** Not by itself. A selected monitor and a compatible reachable endpoint are required.

**Does Grafana store the application metric history?** Prometheus stores it. Grafana stores its own state and queries Prometheus.

**Does ServiceMonitor create an alert or dashboard?** No. PrometheusRule and dashboard provisioning are separate declarations.

**Must each application own a receiver Secret?** No. It can use the platform fallback. A dedicated receiver needs its own appropriately scoped configuration/credentials.

**Can a namespace be visible on a dashboard but have no application metrics?** Yes. Cluster exporters can expose its Pods/resources while its own endpoint remains uninstrumented or undiscovered.

**Will simply installing the chart send notifications?** No. A real receiver, selected rules, valid configuration and working network/authentication must be configured and tested.

## Example files

- [Platform Terraform](examples/platform/main.tf): existing-cluster provider binding, namespace/storage/IAM prerequisites and one Blueprints chart owner.
- [Platform values](examples/platform/values.yaml): explicit discovery, persistence, budgets, Grafana provisioning and EKS target choices.
- [Platform manifests template](examples/platform/platform-manifests.yaml.tftpl): ESO store/secrets and global root notification config, supplied as extraManifests.
- [Application onboarding](examples/application/onboarding.yaml): metrics Service, ServiceMonitor, rules and dashboard ConfigMap.
- [Optional team routing](examples/application/optional-team-routing.yaml): application namespace ESO credentials and AlertmanagerConfig.

These are coordinated **teaching examples**, not a turnkey production deployment. Supply a real instrumented application, compatible prerequisites/versions, actual secret identifiers/destinations, approved state/permissions and measured sizing. No real credential values are included.

### Checks performed while writing this guide

- Terraform formatting and full configuration validation passed with the pinned module and locally available AWS 5.100.0, Kubernetes 3.2.1 and Helm 2.17.0 providers.
- A provider-free Terraform fixture rendered the platform manifests using synthetic secret identifiers only.
- Helm lint/template passed for chart 91.4.0 with the combined example values, extra manifests and Kubernetes 1.33.0.
- All rendered monitoring custom resources and application monitor/rule/routing examples passed a local strict unknown-field check against the chart's shipped CRDs.
- Dashboard JSON, data-source UIDs, explicit discovery labels, Grafana StatefulSet persistence and its container requests were checked.
- Local document links and code-fence pairing were checked. Official supporting links were checked with read-only HTTP requests.
- No application, live cluster, real notification delivery or upgrade was deployed/tested. ESO objects require compatible installed ESO CRDs and live reconciliation; schema checking here covered the monitoring CRDs, not a live API server.
