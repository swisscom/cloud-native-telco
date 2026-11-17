# 01 · Kyverno Chainsaw

[← Overview](../README.md) · [02 vCluster →](../02_vcluster/README.md)

## What is Chainsaw?

TL;DR: Declarative K8s e2e testing.

- **KRM-native.** Tests are Kubernetes-style YAML (`kind: Test`), so you write them in the same language as the resources under test, with no Go or Bash glue
- **Declarative assertions.** assert on partial objects, and the live resource only has to contain what you specify. JMESPath expressions (``(readyReplicas > `1`)``) and array filters (`(conditions[?type == 'Ready'])`) are supported
- **Eventually consistent by design.** Assertions are retried until they match or a timeout expires. That's exactly how reconciling controllers behave, so there's no `sleep 10` anywhere
- **Batteries included.** ephemeral namespaces, clean up automatically, diagnostics on failure
- **Test chained Controller e2e** can help in testing multiple nested controllers (think Deployment-ReplicaSet-Pod)
- **A binary** that runs against any kube-apiserver

Repo: <https://github.com/kyverno/chainsaw>

## How does it compare to other testing methods common for Kubernetes Controllers?

| | Unit | Integration (envtest) | E2E (Chainsaw) |
|---|---|---|---|
| Speed | ms | seconds | seconds to minutes |
| Real API server | ❌ | ✅ | ✅ |
| Built-in controllers, scheduler, kubelet | ❌ | ❌ | ✅ |
| Webhooks, RBAC, real images | ❌ | partial | ✅ |
| **Nested operators** (your operator creates CRs of another operator) | ❌ | ❌ | ✅ |
| Written in | Go | Go | YAML |

Typical uses:

- e2e tests for operators, including **nested or multi-controller setups** where your operator relies on resources of another operator
- testing Helm charts, Kustomize overlays and GitOps output
- testing policies (Kyverno, Gatekeeper, ValidatingAdmissionPolicies), using `error` / `check` to assert that something is *rejected*
- upgrade and chaos-style tests: delete pods or nodes, then assert recovery

## Demo

Run the commands from this folder (`01_chainsaw/`), against the kind cluster from the [setup](../README.md#setup).

```bash
cd 01_chainsaw
kubectl config use-context kind-chainsaw-vcluster-demo
```

### 1. Warm-up: a one-off assertion against the live cluster

```bash
kubectl -n kube-system get deploy coredns
```

```bash
chainsaw assert -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: coredns
  namespace: kube-system
status:
  (readyReplicas > `0`): true
EOF
```

When an assertion fails, Chainsaw shows a diff between what you expected and what is actually in the cluster:

```bash
chainsaw assert --timeout 1s -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: coredns
  namespace: kube-system
spec:
  replicas: 3
EOF
```

### 2. Run the basic test

```bash
kubectl get pods -A -l app=web -w
```

```bash
chainsaw test --test-dir basic
```

### 3. Run the advanced test

```bash
chainsaw test --test-dir advanced
```

In a second terminal, watch the pods being replaced. Chainsaw uses a random `chainsaw-*` namespace:

```bash
kubectl get pods -A -l app=web -w
```

### 4. Run everything in parallel and write a JUnit report

```bash
chainsaw test --assert-timeout 5s --parallel 2 --report-format JUNIT-TEST --report-path /tmp --report-name chainsaw-01
```

```bash
cat /tmp/chainsaw-01.xml
```

### 6. Debugging tip: keep the resources

```bash
chainsaw test --assert-timeout 5s --parallel 2 --skip-delete
kubectl get ns | grep chainsaw-   # the namespace and resources are still there
```

Clean up manually afterwards:

```bash
kubectl get ns -o name | grep chainsaw- | xargs kubectl delete
```

## The catch: a shared cluster

Chainsaw isolates tests with namespaces. Operators install **cluster-scoped** resources such as CRDs, ClusterRoles, webhooks and `cnpg-system`-style namespaces. Two tests, or two branches in CI, that install different versions of the same operator on one cluster will clash.

➡️ That's what [vCluster](../02_vcluster/README.md) solves.

## Learn more

- [Chainsaw on GitHub](https://github.com/kyverno/chainsaw)
- [Chainsaw docs](https://kyverno.github.io/chainsaw/latest/) and [examples](https://kyverno.github.io/chainsaw/latest/examples/)
- [Assertion trees](https://kyverno.github.io/chainsaw/latest/quick-start/assertion-trees/)
- [Operation reference](https://kyverno.github.io/chainsaw/latest/operations/)
