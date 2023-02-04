# Namespace Eraser

Namespace Eraser is a script that enumerates and deletes all resources within a namespace before deleting the namespace itself from a Kubernetes cluster. It also identifies if the target namespace is associated with a downstream Rancher cluster and removes the accompanying `clusters.management.cattle.io` resource. The intended use-case for this script is to clean up namespaces that time out or hang during deletion while using conventional means (e.g. `kubectl delete ns $namespace`)

## Usage
`./namespace-eraser $namespace`

## Dependencies
- `kubectl`
- `awk`
- `grep`
- `bash`