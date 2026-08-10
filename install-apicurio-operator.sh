#!/bin/bash

# Get the directory where this script is located
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$BASE_DIR/shared.sh"

# ##################################################
# Function to display usage information
# ##################################################
show_usage() {
    echo "Usage: $0 [--cluster <cluster_name>] --version <registry_version> [OPTIONS]"
    echo ""
    echo "REQUIRED PARAMETERS:"
    echo "  --version <version>      Version of Apicurio Registry Operator to deploy (e.g., 3.0.9)"
    echo ""
    echo "OPTIONAL PARAMETERS:"
    echo "  --cluster <name>         Name of the OpenShift cluster where Apicurio Registry Operator will be deployed (default: \$USER)"
    echo "  --appImage <image>       Container image for the Apicurio Registry app (optional)"
    echo "  --uiImage <image>        Container image for the Apicurio Registry UI (optional)"
    echo "  --operatorImage <image>  Container image for the Apicurio Registry Operator (optional)"
    echo "  --gitopsImage <image>    Container image for the GitOps sync sidecar (optional)"
    echo "  -h, --help               Display this help message and exit"
    echo ""
    echo "EXAMPLES:"
    echo "  # Basic operator deployment:"
    echo "  $0 --cluster okd419 --version 3.0.9"
    echo ""
    echo "NOTES:"
    echo "  - The cluster must already exist and be properly configured"
    echo "  - Kubeconfig file must be present at clusters/<cluster_name>/auth/kubeconfig"
    echo "  - This script deploys the Apicurio Registry Operator cluster-wide"
    echo "  - Will automatically call configure-apicurio-operator.sh if configured template doesn't exist"
}

# ##################################################
# Function to parse command line arguments
# ##################################################
parse_arguments() {
    CLUSTER_NAME="$USER"
    APICURIO_REGISTRY_VERSION=""
    REGISTRY_APP_IMAGE=""
    REGISTRY_UI_IMAGE=""
    REGISTRY_OPERATOR_IMAGE=""
    REGISTRY_GITOPS_SYNC_IMAGE=""

    while [[ $# -gt 0 ]]; do
        case $1 in
            --cluster)
                CLUSTER_NAME="$2"
                shift 2
                ;;
            --version)
                APICURIO_REGISTRY_VERSION="$2"
                shift 2
                ;;
            --appImage)
                REGISTRY_APP_IMAGE="$2"
                shift 2
                ;;
            --uiImage)
                REGISTRY_UI_IMAGE="$2"
                shift 2
                ;;
            --operatorImage)
                REGISTRY_OPERATOR_IMAGE="$2"
                shift 2
                ;;
            --gitopsImage)
                REGISTRY_GITOPS_SYNC_IMAGE="$2"
                shift 2
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
}

# ##################################################
# Function to validate parameters and set defaults
# ##################################################
validate_and_set_defaults() {
    # Set default values
    OPERATOR_NAMESPACE="apicurio-registry-operator"

    if [ -z "$APICURIO_REGISTRY_VERSION" ]; then
        echo "Error: --version argument is required"
        show_usage
        exit 1
    fi

    # Set up environment variables
    export CLUSTER_NAME
    export APICURIO_REGISTRY_VERSION
    export CONFIGURED_OPERATOR_YAML="$BASE_DIR/templates/registry-operator/$APICURIO_REGISTRY_VERSION/apicurio-registry-operator-configured.yaml"
}

# ##################################################
# Function to configure operator template if needed
# ##################################################
configure_template_if_needed() {
    # Check if configured operator YAML exists, configure it if not
    if [ ! -f "$CONFIGURED_OPERATOR_YAML" ]; then
        echo "Configured operator YAML '$CONFIGURED_OPERATOR_YAML' does not exist"
        echo "Calling configure-apicurio-operator-install-file.sh to configure template..."

        # Build arguments for configure script
        CONFIGURE_ARGS="--cluster $CLUSTER_NAME --version $APICURIO_REGISTRY_VERSION"
        if [ -n "$REGISTRY_APP_IMAGE" ]; then
            CONFIGURE_ARGS="$CONFIGURE_ARGS --appImage $REGISTRY_APP_IMAGE"
        fi
        if [ -n "$REGISTRY_UI_IMAGE" ]; then
            CONFIGURE_ARGS="$CONFIGURE_ARGS --uiImage $REGISTRY_UI_IMAGE"
        fi
        if [ -n "$REGISTRY_OPERATOR_IMAGE" ]; then
            CONFIGURE_ARGS="$CONFIGURE_ARGS --operatorImage $REGISTRY_OPERATOR_IMAGE"
        fi
        if [ -n "$REGISTRY_GITOPS_SYNC_IMAGE" ]; then
            CONFIGURE_ARGS="$CONFIGURE_ARGS --gitopsImage $REGISTRY_GITOPS_SYNC_IMAGE"
        fi

        # Call the configure script
        if ! "$BASE_DIR/configure-apicurio-operator-install-file.sh" $CONFIGURE_ARGS; then
            echo "Error: Failed to configure operator template"
            exit 1
        fi

        # Verify the configuration was successful
        if [ ! -f "$CONFIGURED_OPERATOR_YAML" ]; then
            echo "Error: Failed to configure operator template"
            exit 1
        fi
    else
        echo "Using existing configured operator YAML: $CONFIGURED_OPERATOR_YAML"
    fi
}

# ##################################################
# Function to create namespace
# ##################################################
create_namespace() {
    # Create the namespace if it doesn't exist
    echo "Creating namespace: $OPERATOR_NAMESPACE (if it doesn't exist)"
    kubectl create namespace "$OPERATOR_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
}

# ##################################################
# Function to deploy operator
# ##################################################
deploy_operator() {
    # Deploy the Apicurio Registry operator to the namespace
    echo "Using configured Apicurio Registry Operator YAML: $CONFIGURED_OPERATOR_YAML"
    echo "Installing Apicurio Registry Operator into namespace $OPERATOR_NAMESPACE"
    kubectl apply -f "$CONFIGURED_OPERATOR_YAML" -n "$OPERATOR_NAMESPACE"
}

# ##################################################
# Function to wait for the operator pod to become
# ready after deployment.
# ##################################################
wait_for_operator_ready() {
    local namespace="$1"
    local timeout=300
    local interval=10
    local elapsed=0

    echo "Waiting for Apicurio Registry Operator pod to become ready..."
    echo "Looking for pod with label 'app=apicurio-registry-operator' in namespace $namespace..."
    echo "Timeout: ${timeout}s, Polling interval: ${interval}s"

    while [ $elapsed -lt $timeout ]; do
        local pod_names=$(kubectl get pods -l app=apicurio-registry-operator -n "$namespace" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)

        if [ -z "$pod_names" ]; then
            echo "No operator pods found yet, waiting for creation... (${elapsed}s/${timeout}s)"
        else
            for pod_name in $pod_names; do
                local ready_status=$(kubectl get pod "$pod_name" -n "$namespace" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "Unknown")
                local phase=$(kubectl get pod "$pod_name" -n "$namespace" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")

                if [ "$ready_status" = "True" ]; then
                    echo "Operator pod $pod_name is ready (Phase: $phase)"
                    return 0
                else
                    echo "Operator pod $pod_name: Ready=$ready_status, Phase=$phase (${elapsed}s/${timeout}s)"
                fi
            done
        fi

        sleep $interval
        elapsed=$((elapsed + interval))
    done

    echo ""
    echo "ERROR: Apicurio Registry Operator pod did not become ready within ${timeout} seconds"
    echo ""

    output_operator_debug_info "$namespace"

    return 1
}

# ##################################################
# Function to output debugging information when
# the operator fails to become ready.
# ##################################################
output_operator_debug_info() {
    local namespace="$1"

    echo "Collecting debugging information..."
    echo ""
    echo "=========================================="
    echo "OPERATOR DEBUGGING INFORMATION"
    echo "=========================================="
    echo ""

    echo "==================== DEPLOYMENTS ===================="
    kubectl get deployments -n "$namespace" -o wide 2>/dev/null || echo "Failed to get deployments"
    echo ""
    kubectl describe deployments -n "$namespace" 2>/dev/null || echo "Failed to describe deployments"
    echo ""

    echo "==================== REPLICASETS ===================="
    kubectl get replicasets -n "$namespace" -o wide 2>/dev/null || echo "Failed to get replicasets"
    echo ""

    echo "==================== PODS ===================="
    kubectl get pods -n "$namespace" -o wide 2>/dev/null || echo "Failed to get pods"
    echo ""
    kubectl describe pods -n "$namespace" 2>/dev/null || echo "Failed to describe pods"
    echo ""

    echo "==================== EVENTS ===================="
    kubectl get events -n "$namespace" --sort-by='.lastTimestamp' 2>/dev/null || echo "Failed to get events"
    echo ""

    echo "==================== POD LOGS ===================="
    local pods=$(kubectl get pods -n "$namespace" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)
    if [ -n "$pods" ]; then
        for pod in $pods; do
            echo "--- Logs for pod: $pod ---"
            kubectl logs "$pod" -n "$namespace" --tail=100 2>/dev/null || echo "Failed to get logs for pod $pod"
            echo ""
        done
    else
        echo "No pods found in namespace $namespace"
    fi

    echo "=========================================="
    echo "END OPERATOR DEBUGGING INFORMATION"
    echo "=========================================="
    echo ""
}

# ##################################################
# Function to display deployment summary
# ##################################################
display_summary() {
    echo "Apicurio Registry Operator deployment completed successfully!"
    echo "Operator deployed in namespace: $OPERATOR_NAMESPACE"
    echo "Configured YAML used: $CONFIGURED_OPERATOR_YAML"
}

# ##################################################
# Main execution
# ##################################################
main() {
    # Parse command line arguments
    parse_arguments "$@"

    # Validate parameters and set defaults
    validate_and_set_defaults

    load_cluster_config "$CLUSTER_NAME"

    # Configure template if needed
    configure_template_if_needed

    # Create namespace
    create_namespace

    # Deploy operator
    deploy_operator

    # Wait for operator to become ready
    if ! wait_for_operator_ready "$OPERATOR_NAMESPACE"; then
        echo "ERROR: Apicurio Registry Operator failed to start. Aborting."
        exit 1
    fi

    # Display summary
    display_summary
}

# Execute main function with all arguments
main "$@"
