# OpenShift Deployment Guide

This directory contains the Kubernetes/OpenShift deployment resources for the Tier-to-Group Admin service.

## Prerequisites

- OpenShift cluster access
- `oc` CLI tool installed and configured
- Container registry access
- RBAC permissions to create resources in the `maas-dev` namespace

## Files

- `kustomization.yaml` - Kustomize configuration for managing all resources
- `namespace.yaml` - Creates the `maas-dev` namespace
- `serviceaccount.yaml` - Creates the service account for the application
- `rbac.yaml` - Defines Role and RoleBinding for ConfigMap access
- `deployment.yaml` - Defines the pod specification (uses service account token automatically)
- `service.yaml` - Exposes the service within the cluster
- `route.yaml` - Exposes the service outside the cluster (OpenShift specific)
- `secret.yaml` - Optional, no longer required (service account token is automatically managed)

## Deployment Steps

### 1. Build and Push Container Image

```bash
# Build the image
make build

# Push to registry
make push
```

Or manually:

```bash
# Build the image
podman build -t tier-to-group-admin:latest .

# Tag for your registry (replace with your registry URL)
podman tag tier-to-group-admin:latest <registry-url>/tier-to-group-admin:latest

# Push to registry
podman push <registry-url>/tier-to-group-admin:latest
```

### 2. Create Namespace

```bash
oc apply -f yaml/namespace.yaml
```

### 3. Create Service Account and RBAC

```bash
# Create service account
oc apply -f yaml/serviceaccount.yaml

# Create RBAC (Role and RoleBinding)
oc apply -f yaml/rbac.yaml
```

### 4. Service Account Token (Automatic)

The application uses Kubernetes client-go's `rest.InClusterConfig()` which automatically:
- Reads the service account token from the mounted secret volume at `/var/run/secrets/kubernetes.io/serviceaccount/token`
- Handles token refresh for projected service account tokens
- Reads the CA certificate from `/var/run/secrets/kubernetes.io/serviceaccount/ca.crt`
- Uses the service account's namespace

**No manual token configuration is required.** The service account token is automatically mounted and managed by Kubernetes when the pod runs in-cluster.

**Note**: The `secret.yaml` file is no longer needed and can be skipped. The deployment uses the default service account, or you can create a dedicated service account with appropriate RBAC permissions.

### 5. Update Deployment Image (if needed)

The deployment already references `quay.io/bryonbaker/tier-to-group-admin:latest`. If using a different registry, edit `deployment.yaml` and update the `image` field:

```yaml
image: <registry-url>/tier-to-group-admin:latest
```

### 6. Deploy Resources

You can deploy using either method:

**Option A: Using Kustomize (Recommended)**

```bash
# Build and apply using kustomize
oc apply -k yaml/

# Or build first to preview
oc kustomize yaml/ | oc apply -f -
```

**Option B: Apply individual files**

```bash
# Deploy all resources
oc apply -f yaml/deployment.yaml
oc apply -f yaml/service.yaml
oc apply -f yaml/route.yaml
```

Or apply all at once:

```bash
oc apply -f yaml/
```

### 7. Verify Deployment

```bash
# Check pods
oc get pods -n maas-dev

# Check service
oc get svc -n maas-dev

# Check route
oc get route -n maas-dev

# View logs
oc logs -f deployment/tier-to-group-admin -n maas-dev
```

### 8. Test the API

Get the route URL:

```bash
ROUTE_URL=$(oc get route tier-to-group-admin -n maas-dev -o jsonpath='{.spec.host}')
echo "API URL: https://$ROUTE_URL"
```

Test the health endpoint:

```bash
curl https://$ROUTE_URL/health
```

## Environment Variables

The deployment uses the following environment variables:

| Variable | Source | Description |
|----------|--------|-------------|
| `NAMESPACE` | Field ref | Current namespace (maas-dev) |
| `CONFIGMAP_NAME` | Hardcoded | ConfigMap name (tier-to-group-mapping) |
| `PORT` | Hardcoded | Server port (8080) |

**Note**: `BEARER_TOKEN` and `HOST_PATH` are no longer used. The application automatically uses the service account token mounted by Kubernetes at `/var/run/secrets/kubernetes.io/serviceaccount/token`.

## ConfigMap Management

The application will automatically:
- Create the ConfigMap if it doesn't exist
- Read from the ConfigMap on startup
- Update the ConfigMap when tiers are modified

The ConfigMap will be created in the `maas-dev` namespace with the name `tier-to-group-mapping`.

## RBAC Requirements

The service account used by the deployment needs permissions to manage ConfigMaps. These are defined in `rbac.yaml`:

- **Role**: Grants `get`, `list`, `watch`, `create`, `update`, and `patch` permissions on ConfigMaps in the `maas-dev` namespace
- **RoleBinding**: Binds the `tier-to-group-admin` service account to the `tier-admin-role`

The RBAC resources are automatically applied when you run:

```bash
oc apply -f yaml/rbac.yaml
```

Or when applying all resources at once:

```bash
oc apply -f yaml/
```

## Troubleshooting

### Pod not starting

```bash
# Check pod status
oc describe pod <pod-name> -n maas-dev

# Check logs
oc logs <pod-name> -n maas-dev
```

### Cannot connect to Kubernetes API

- Verify the service account has proper RBAC permissions (see RBAC Requirements section)
- Check that the service account token is mounted: `oc exec <pod-name> -n maas-dev -- ls -la /var/run/secrets/kubernetes.io/serviceaccount/`
- Verify the pod is running in-cluster
- Check network policies if applicable

### ConfigMap not found

- The application will create the ConfigMap automatically on first write
- Verify RBAC permissions allow ConfigMap creation

## Cleanup

To remove all resources:

```bash
oc delete -f yaml/
```

