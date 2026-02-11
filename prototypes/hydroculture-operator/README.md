# hydroculture-operator

**Demo project for Container Days London 2026**  
Talk: *"defer: The Silent Hero of Kubernetes Operators"*

A Kubernetes operator that manages hudroculture gardens by monitoring and adjusting temperature. This project demonstrates best practices for using Go's `defer` statement to manage status conditions in Kubernetes operators.

## What This Demonstrates

This operator showcases:
- **Defer for status updates**: Ensures conditions are always set, even on error paths
- **Error sanitization**: Strips stack traces for user-friendly condition messages
- **Dynamic requeue intervals**: Adjusts retry timing based on reconciliation state
- **Centralized condition logic**: All condition management in one place

## Quick Start with Kind

### Prerequisites
- [Kind](https://kind.sigs.k8s.io/) v0.20.0+
- [kubectl](https://kubernetes.io/docs/tasks/tools/) v1.28.0+
- [Go](https://go.dev/dl/) v1.24.6+

### 1. Create a Kind Cluster
 How It Works

### The Defer Pattern

The key pattern demonstrated in this operator is the use of `defer` to manage status conditions:

```go
defer func() {
    conditionResult, conditionErr := r.updateConditions(ctx, herbs, reconcileErr)
    if conditionErr != nil {
        log.Error(conditionErr, "Failed to update conditions")
        reconcileErr = errors.Join(reconcileErr, conditionErr)
    }
    // Defer can override the requeue interval
    if conditionResult.RequeueAfter > 0 {
        result = conditionResult
    }
}()
```

**Benefits:**
- ✅ Conditions are **always** updated, regardless of which return path is taken
- ✅ Errors are **sanitized** for user-friendly messages
- ✅ Requeue intervals are **dynamically adjusted** based on state
- ✅ All condition logic is **centralized** in one function

### Supported Plants

- **Basil**: Ideal temperature 24°C
- **Lettuce**: Ideal temperature 20°C  
- **Spinach**: Ideal temperature 18°C

### Status Conditions

- `TempReady`: Indicates if the temperature matches the ideal for the plant
- `Ready`: Overall readiness of the herb garden

## Advanced Deployment

##
```sh
kind create cluster --name hydroculture-demo
```

### 2. Install the CRDs

```sh
make install
```

### 3. Run the Operator Locally

```sh
make run
```

The operator will start and connect to your Kind cluster. Leave this running in your terminal.

### 4. Create a Temperature ConfigMap

Open a new terminal and create a ConfigMap to simulate the temperature sensor:

```sh
kubectl create namespace demo
kubectl create configmap temperature -n demo --from-literal=value=22
```

### 5. Deploy a Herbs Resource

```sh
cat <<EOF | kubectl apply -f -
apiVersion: hydroculture.containerdays.io/v1
kind: Herbs
metadata:
  name: basil-garden
  namespace: demo
spec:
  plant: basil
EOF
```

### 6. Watch the Operator in Action

```sh
# Watch the status conditions
kubectl get herbs -n demo basil-garden -o yaml -w

# Or use kubectl describe
kubectl describe herbs -n demo basil-garden
```

You'll see the operator detecting that the temperature (22°C) is below the ideal for basil (24°C), and the conditions reflecting this state.

### 7. Adjust the Temperature

Simulate the heating system working by updating the temperature:

```sh
kubectl patch configmap temperature -n demo --type merge -p '{"data":{"value":"24"}}'
```

Watch the conditions change to `Ready=True` and `TempReady=True` once the ideal temperature is reached!

### 8. Test Error Handling

Delete the ConfigMap to see how the operator handles errors:

```sh
kubectl delete configmap temperature -n demo
```

Notice how the defer pattern ensures conditions are set even when errors occur, with sanitized error messages in the status.

### 9. Cleanup

```sh
kubectl delete herbs -n demo basil-garden
kubectl delete namespace demo
kind delete cluster --name hydroculture-demo
```

### To Deploy on the cluster
**Build and push your image to the location specified by `IMG`:**

```sh
make docker-build docker-push IMG=<some-registry>/hydroculture-operator:tag
```

**NOTE:** This image ought to be published in the personal registry you specified.
And it is required to have access to pull the image from the working environment.
Make sure you have the proper permission to the registry if the above commands don’t work.

**Install the CRDs into the cluster:**

```sh
make install
```

**Deploy the Manager to the cluster with the image specified by `IMG`:**

```sh
make deploy IMG=<some-registry>/hydroculture-operator:tag
```

> **NOTE**: If you encounter RBAC errors, you may need to grant yourself cluster-admin
privileges or be logged in as admin.

**Create instances of your solution**
You can apply the samples (examples) from the config/sample:

```sh
kubectl apply -k config/samples/
```

>**NOTE**: Ensure that the samples has default values to test it out.

### To Uninstall
**Delete the instances (CRs) from the cluster:**

```sh
kubectl delete -k config/samples/
```

**Delete the APIs(CRDs) from the cluster:**

```sh
make uninstall
```

**UnDeploy the controller from the cluster:**

```sh
make undeploy
```

## Project Distribution

Following the options to release and provide this solution to the users.

### By providing a bundle with all YAML files
Learn More

- [Kubebuilder Documentation](https://book.kubebuilder.io/)
- [Kubernetes Operator Pattern](https://kubernetes.io/docs/concepts/extend-kubernetes/operator/)
- [Controller Runtime](https://github.com/kubernetes-sigs/controller-runtime)

**NOTE:** Run `make help` for more information on all potential `make` targets

## Conference Resources

**Container Days London 2026**  
Talk: *"defer: The Silent Hero of Kubernetes Operators"*

This demo showcases production patterns for status management in Kubernetes operators using Go's defer statement. Check the [internal/controller/herbs_controller.go](internal/controller/herbs_controller.go) file to see the defer pattern in action!

**NOTE:** The makefile target mentioned above generates an 'install.yaml'
file in the dist directory. This file contains all the resources built
with Kustomize, which are necessary to install this project without its
dependencies.

2. Using the installer

Users can just run 'kubectl apply -f <URL for YAML BUNDLE>' to install
the project, i.e.:

```sh
kubectl apply -f https://raw.githubusercontent.com/<org>/hydroculture-operator/<tag or branch>/dist/install.yaml
```

### By providing a Helm Chart

1. Build the chart using the optional helm plugin

```sh
kubebuilder edit --plugins=helm/v2-alpha
```

2. See that a chart was generated under 'dist/chart', and users
can obtain this solution from there.

**NOTE:** If you change the project, you need to update the Helm Chart
using the same command above to sync the latest changes. Furthermore,
if you create webhooks, you need to use the above command with
the '--force' flag and manually ensure that any custom configuration
previously added to 'dist/chart/values.yaml' or 'dist/chart/manager/manager.yaml'
is manually re-applied afterwards.

## Contributing
// TODO(user): Add detailed information on how you would like others to contribute to this project

**NOTE:** Run `make help` for more information on all potential `make` targets

More information can be found via the [Kubebuilder Documentation](https://book.kubebuilder.io/introduction.html)

## License

Copyright 2026.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
