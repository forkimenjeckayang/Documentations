# What is Kubernetes?

Kubernetes is an open-source container orchestration platform designed to automate the deployment, scaling, and management of containerized applications. Originally developed by Google, it is now maintained by the Cloud Native Computing Foundation (CNCF). Kubernetes helps manage containers at scale, making it easier to deploy and operate applications in a cloud environment.

## Key Features of Kubernetes

1. **Container Orchestration**: 
   - Kubernetes automates the deployment, scaling, and management of containerized applications across clusters of hosts.

2. **Scalability**:
   - It allows for automatic scaling of applications based on demand. Kubernetes can scale up or down the number of container instances running an application based on metrics such as CPU or memory usage.

3. **Self-Healing**:
   - Kubernetes monitors the health of containers and nodes. If a container fails or a node becomes unresponsive, Kubernetes automatically restarts, reschedules, or replaces them to maintain application availability.

4. **Service Discovery and Load Balancing**:
   - Kubernetes provides built-in service discovery, allowing containers to communicate with each other seamlessly. It also balances the load among containers to optimize resource utilization.

5. **Rolling Updates and Rollbacks**:
   - Kubernetes supports rolling updates to applications, allowing for updates with zero downtime. If an issue occurs during the update, Kubernetes can roll back to a previous stable version.

6. **Storage Orchestration**:
   - Kubernetes manages storage resources, allowing you to automatically mount and manage storage volumes for your containers.

7. **Declarative Configuration**:
   - Users can define the desired state of their applications and Kubernetes works to maintain that state. This is typically done using YAML or JSON files.

8. **Multi-Cloud and Hybrid Cloud Support**:
   - Kubernetes can be deployed on various cloud platforms or on-premises, enabling organizations to run applications in multi-cloud or hybrid cloud environments.

## Core Concepts of Kubernetes

- **Pod**: The smallest deployable unit in Kubernetes, a pod can contain one or more containers that share the same network namespace.
  
- **Node**: A worker machine in Kubernetes, which can be a physical or virtual machine. Each node runs the necessary services to run pods.

- **Cluster**: A set of nodes that run containerized applications managed by Kubernetes.

- **Deployment**: A resource that provides declarative updates to applications, managing the lifecycle of pods.

- **Service**: An abstraction that defines a logical set of pods and a policy to access them, enabling stable network access to applications.

- **Namespace**: A way to divide cluster resources between multiple users or applications, providing a scope for names.

## Use Cases for Kubernetes

- **Microservices Architecture**: Kubernetes is particularly well-suited for applications built using microservices, where each service can run in its own container and be managed independently.

- **Continuous Deployment and Integration**: Organizations use Kubernetes to facilitate continuous integration and continuous deployment (CI/CD) pipelines, allowing for faster and more reliable software releases.

- **Hybrid and Multi-Cloud Deployments**: Businesses that want to leverage both on-premises and cloud resources can use Kubernetes to manage workloads across different environments seamlessly.


# What is GKE?

Google Kubernetes Engine (GKE) is a managed Kubernetes service provided by Google Cloud Platform (GCP) that allows users to deploy, manage, and scale containerized applications using Kubernetes. GKE simplifies the process of setting up and managing Kubernetes clusters, handling tasks such as provisioning, scaling, and updating the infrastructure.

## Key Features of GKE

1. **Managed Service**:
   - GKE automates the deployment and management of Kubernetes clusters, reducing the operational overhead for users. Google handles tasks like cluster creation, upgrades, and monitoring.

2. **Integration with Google Cloud**:
   - GKE integrates seamlessly with other Google Cloud services, such as Cloud Storage, BigQuery, and Cloud Pub/Sub, allowing users to build comprehensive applications that leverage the full capabilities of GCP.

3. **Autoscaling**:
   - GKE supports both cluster autoscaling and horizontal pod autoscaling. Cluster autoscaling adjusts the number of nodes in a cluster based on resource demand, while horizontal pod autoscaling adjusts the number of pods running in a deployment based on metrics like CPU and memory usage.

4. **Security and Compliance**:
   - GKE provides built-in security features such as Identity and Access Management (IAM), private clusters, and integration with Google Cloud Armor for DDoS protection. It also supports compliance with various security standards.

5. **Continuous Integration and Delivery (CI/CD)**:
   - GKE supports CI/CD pipelines, allowing developers to automate the deployment of applications using tools like Cloud Build, Spinnaker, and Jenkins.

## Important Concepts of GKE

1. **Clusters**:
   - A GKE cluster is a set of virtual machines (nodes) that run your containerized applications. Each cluster consists of a master (control plane) and worker nodes (where the application runs).

2. **Node Pools**:
   - Node pools are groups of nodes within a cluster that share the same configuration, such as machine type and disk size. Different node pools can be created for different workloads.

3. **Kubernetes Resources**:
   - GKE supports all standard Kubernetes resources, including Pods, Deployments, Services, and StatefulSets. Users can define and manage these resources to run their applications.

4. **Workload Identity**:
   - This feature allows Kubernetes applications to securely access Google Cloud services using IAM roles without the need for service account keys. It simplifies authentication and improves security.

5. **Cloud Operations (formerly Stackdriver)**:
   - GKE integrates with Google Cloud's operations suite, providing monitoring, logging, and diagnostics for applications running in Kubernetes.

6. **Networking**:
   - GKE provides advanced networking features, including VPC-native clusters, private clusters, and load balancing, to ensure efficient communication between applications and services.

7. **Serverless Features**:
   - GKE can integrate with Cloud Run, enabling serverless deployment of containers that automatically scale based on traffic.

8. **Release Channels**:
   - GKE offers different release channels (Rapid, Regular, Stable) to manage the updates and features available to the cluster, allowing users to choose the level of stability versus new features they prefer.


# Important Kubernetes Concepts

Here are some important Kubernetes concepts you need to know:

## 1. Pod
- **Definition**: The smallest deployable unit in Kubernetes. A pod can contain one or more containers that share the same network namespace and storage resources. Pods represent processes running in the cluster

## 2. Node
- **Definition**: A worker machine in Kubernetes, which can be a physical or virtual machine. Each node runs the necessary services to manage the pods.

## 3. Cluster
- **Definition**: A set of nodes that run containerized applications managed by Kubernetes. It includes a control plane and one or more worker nodes.

## 4. Deployment
- **Definition**: A Kubernetes resource that provides declarative updates to applications. It manages the lifecycle of pods and ensures the desired number of replicas are running.

## 5. Service
- **Definition**: An abstraction that defines a logical set of pods and a policy for accessing them. Services provide stable network access to pods. SErvices handle communication form the outside world to the inside of your cluster. It handles traffi c and knows where to redirected if calls are made from outside the cluster. So it's like a gateway service.
- **Some types**:
  -  Cluster IP service which is not externally reachable
  - Load Balancing service
  - External namespace service
  - Node pod service (exposing pods externally )

## 6. ReplicaSet
- **Definition**: Ensures that a specified number of pod replicas are running at all times. It is usually managed by a Deployment.

## 7. StatefulSet
- **Definition**: A resource used for managing stateful applications. It maintains a unique identity and persistent storage for each pod.

## 8. Namespace
- **Definition**: A way to divide cluster resources between multiple users or applications. Namespaces are a logical partitioning of cluster resources that helps organize and manage resources within a Kubernetes cluster. Namespaces provide a way to divide cluster resources between multiple users, teams, or applications, allowing for better resource management and isolation.

## 9. ConfigMap
- **Definition**: A resource used to store non-confidential configuration data in key-value pairs. ConfigMaps allow applications to be configured dynamically.

## 10. Ingress
- **Definition**: A collection of rules that allow external HTTP/S traffic to access services within a cluster. It provides a way to manage access to services based on the URL.


