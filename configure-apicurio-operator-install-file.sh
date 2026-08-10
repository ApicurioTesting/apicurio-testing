#!/bin/bash

# Get the directory where this script is located
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ##################################################
# Function to display usage information
# ##################################################
show_usage() {
    echo "Usage: $0 [--cluster <cluster_name>] --version <registry_version> [OPTIONS]"
    echo ""
    echo "REQUIRED PARAMETERS:"
    echo "  --version <version>      Version of Apicurio Registry Operator to configure (e.g., 3.0.9)"
    echo ""
    echo "OPTIONAL PARAMETERS:"
    echo "  --cluster <name>         Name of the OpenShift cluster (default: $USER)"
    echo "  --namespace <namespace>  Namespace for the Apicurio Registry Operator (default: apicurio-registry-operator)"
    echo "  --appImage <image>       Container image for the Apicurio Registry app (optional)"
    echo "  --uiImage <image>        Container image for the Apicurio Registry UI (optional)"
    echo "  --operatorImage <image>  Container image for the Apicurio Registry Operator (optional)"
    echo "  --gitopsImage <image>    Container image for the GitOps sync sidecar (optional)"
    echo "  -h, --help               Display this help message and exit"
    echo ""
    echo "EXAMPLES:"
    echo "  # Basic operator template configuration:"
    echo "  $0 --cluster okd419 --version 3.0.9"
    echo ""
    echo "NOTES:"
    echo "  - Downloads operator template using download-apicurio-operator-install-file.sh"
    echo "  - Creates configured YAML file with environment variables substituted"
    echo "  - Output file will have 'configured' suffix"
}

# ##################################################
# Function to parse command line arguments
# ##################################################
parse_arguments() {
    CLUSTER_NAME="$USER"
    OPERATOR_NAMESPACE="apicurio-registry-operator"
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
            --namespace)
                OPERATOR_NAMESPACE="$2"
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
    # Set default values if not set by arguments
    if [ -z "$OPERATOR_NAMESPACE" ]; then
        OPERATOR_NAMESPACE="apicurio-registry-operator"
    fi

    # Validate cluster name (should not be empty after defaulting to $USER)
    if [ -z "$CLUSTER_NAME" ]; then
        echo "Error: cluster name is empty (default: \$USER)"
        show_usage
        exit 1
    fi

    if [ -z "$APICURIO_REGISTRY_VERSION" ]; then
        echo "Error: --version argument is required"
        show_usage
        exit 1
    fi

    # Set default image values
    if [ -z "$REGISTRY_APP_IMAGE" ]; then
        REGISTRY_APP_IMAGE="quay.io/apicurio/apicurio-registry:$APICURIO_REGISTRY_VERSION"
    fi
    if [ -z "$REGISTRY_UI_IMAGE" ]; then
        REGISTRY_UI_IMAGE="quay.io/apicurio/apicurio-registry-ui:$APICURIO_REGISTRY_VERSION"
    fi
    if [ -z "$REGISTRY_OPERATOR_IMAGE" ]; then
        REGISTRY_OPERATOR_IMAGE="quay.io/apicurio/apicurio-registry-3-operator:$APICURIO_REGISTRY_VERSION"
    fi
    if [ -z "$REGISTRY_GITOPS_SYNC_IMAGE" ]; then
        REGISTRY_GITOPS_SYNC_IMAGE="quay.io/apicurio/apicurio-registry-gitops-sync:$APICURIO_REGISTRY_VERSION"
    fi

    # Set up environment variables
    export CLUSTER_NAME
    export APICURIO_REGISTRY_VERSION
    export APICURIO_OPERATOR_YAML="$BASE_DIR/templates/registry-operator/$APICURIO_REGISTRY_VERSION/apicurio-registry-operator.yaml"
    export CONFIGURED_OPERATOR_YAML="$BASE_DIR/templates/registry-operator/$APICURIO_REGISTRY_VERSION/apicurio-registry-operator-configured.yaml"
}

# ##################################################
# Function to download operator template if needed
# ##################################################
download_template_if_needed() {
    # Check if operator YAML template exists, download it if not
    if [ ! -f "$APICURIO_OPERATOR_YAML" ]; then
        echo "Operator YAML template '$APICURIO_OPERATOR_YAML' does not exist locally"
        echo "Calling download-apicurio-operator-install-file.sh to download template..."

        # Build arguments for download script
        DOWNLOAD_ARGS="--version $APICURIO_REGISTRY_VERSION"

        # Call the download script
        if ! "$BASE_DIR/download-apicurio-operator-install-file.sh" $DOWNLOAD_ARGS; then
            echo "Error: Failed to download operator template"
            exit 1
        fi

        # Verify the download was successful
        if [ ! -f "$APICURIO_OPERATOR_YAML" ]; then
            echo "Error: Failed to download operator template"
            exit 1
        fi
    else
        echo "Using existing operator YAML template: $APICURIO_OPERATOR_YAML"
    fi
}

# ##################################################
# Function to configure the template with environment variables
# ##################################################
configure_template() {
    echo "Configuring operator template with environment variables..."
    echo "Creating configured YAML: $CONFIGURED_OPERATOR_YAML"

    # Export environment variables for envsubst
    export OPERATOR_NAMESPACE
    export REGISTRY_APP_IMAGE
    export REGISTRY_UI_IMAGE
    export REGISTRY_OPERATOR_IMAGE
    export REGISTRY_GITOPS_SYNC_IMAGE

    # Substitute environment variables in template
    envsubst < "$APICURIO_OPERATOR_YAML" > "$CONFIGURED_OPERATOR_YAML"

    if [ ! -f "$CONFIGURED_OPERATOR_YAML" ]; then
        echo "Error: Failed to create configured operator YAML"
        exit 1
    fi

    echo "Template configured successfully: $CONFIGURED_OPERATOR_YAML"
}

# ##################################################
# Function to display summary
# ##################################################
display_summary() {
    echo "Apicurio Registry Operator template configuration completed successfully!"
    echo "Source template: $APICURIO_OPERATOR_YAML"
    echo "Configured YAML: $CONFIGURED_OPERATOR_YAML"
    echo "Images configured:"
    echo "  App Image: $REGISTRY_APP_IMAGE"
    echo "  UI Image: $REGISTRY_UI_IMAGE"
    echo "  Operator Image: $REGISTRY_OPERATOR_IMAGE"
    echo "  GitOps Image: $REGISTRY_GITOPS_SYNC_IMAGE"
    echo "  Namespace: $OPERATOR_NAMESPACE"
}

# ##################################################
# Main execution
# ##################################################
main() {
    # Parse command line arguments
    parse_arguments "$@"

    # Validate parameters and set defaults
    validate_and_set_defaults

    # Download template if needed
    download_template_if_needed

    # Configure the template
    configure_template

    # Display summary
    display_summary
}

# Execute main function with all arguments
main "$@"
