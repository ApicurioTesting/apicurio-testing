#!/bin/bash

# Get the directory where this script is located
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ##################################################
# Function to display usage information
# ##################################################
show_usage() {
    echo "Usage: $0 --version <registry_version> [OPTIONS]"
    echo ""
    echo "REQUIRED PARAMETERS:"
    echo "  --version <version>      Version of Apicurio Registry Operator to prepare (e.g., 3.0.9)"
    echo ""
    echo "OPTIONAL PARAMETERS:"
    echo "  -h, --help               Display this help message and exit"
    echo ""
    echo "EXAMPLES:"
    echo "  # Basic operator template preparation:"
    echo "  $0 --version 3.0.9"
    echo ""
    echo "NOTES:"
    echo "  - This script downloads and processes the Apicurio Registry Operator template"
    echo "  - If operator template doesn't exist locally, it will be downloaded from GitHub automatically"
    echo "  - The processed template will be saved in templates/registry-operator/<version>/"
}

# ##################################################
# Function to parse command line arguments
# ##################################################
parse_arguments() {
    APICURIO_REGISTRY_VERSION=""

    while [[ $# -gt 0 ]]; do
        case $1 in
            --version)
                APICURIO_REGISTRY_VERSION="$2"
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
# Function to validate required parameters and set defaults
# ##################################################
validate_and_set_defaults() {
    # Validate required parameters
    if [ -z "$APICURIO_REGISTRY_VERSION" ]; then
        echo "Error: --version argument is required"
        show_usage
        exit 1
    fi

    # Set up environment variables
    export APICURIO_REGISTRY_VERSION
    export APICURIO_OPERATOR_YAML="$BASE_DIR/templates/registry-operator/$APICURIO_REGISTRY_VERSION/apicurio-registry-operator.yaml"
}

# ##################################################
# Function to download operator template from GitHub
# ##################################################
download_template() {
    local version="$1"
    local template_dir="$2"
    local template_file="$3"
    local download_url="https://raw.githubusercontent.com/Apicurio/apicurio-registry/refs/tags/v$version/operator/install/install.yaml"

    echo "Operator YAML template not found locally. Downloading from GitHub..."
    echo "URL: $download_url"

    # Create the directory if it doesn't exist
    mkdir -p "$template_dir"

    # Download the template
    if ! curl -s -f -L "$download_url" -o "$template_file.tmp"; then
        echo "Error: Failed to download operator template from $download_url"
        echo "Please check if version '$version' exists or download manually"
        exit 1
    fi

    echo "Template downloaded successfully from GitHub"
}

# ##################################################
# Function to process template by replacing placeholders with environment variables
# ##################################################
process_template() {
    local version="$1"
    local template_file="$2"

    echo "Processing template to replace placeholders..."

    # Process the template to replace placeholders with environment variable references
    sed -e 's/PLACEHOLDER_NAMESPACE/$OPERATOR_NAMESPACE/g' \
        -e "s|quay.io/apicurio/apicurio-registry:$version|\$REGISTRY_APP_IMAGE|g" \
        -e "s|quay.io/apicurio/apicurio-registry-ui:$version|\$REGISTRY_UI_IMAGE|g" \
        -e "s|quay.io/apicurio/apicurio-registry-3-operator:$version|\$REGISTRY_OPERATOR_IMAGE|g" \
        -e "s|quay.io/apicurio/apicurio-registry-gitops-sync:$version|\$REGISTRY_GITOPS_SYNC_IMAGE|g" \
        "$template_file.tmp" > "$template_file"

    # Remove temporary file
    rm "$template_file.tmp"

    echo "Template processed successfully: $template_file"
}

# ##################################################
# Function to handle template preparation (download if needed, then process)
# ##################################################
prepare_template() {
    local version="$1"
    local template_dir="$BASE_DIR/templates/registry-operator/$version"
    local template_file="$template_dir/apicurio-registry-operator.yaml"

    # Check if template exists locally
    if [ -f "$template_file" ]; then
        echo "Operator YAML template already exists: $template_file"
        return 0
    fi

    echo "Operator YAML template '$template_file' does not exist locally"

    # Download the template
    download_template "$version" "$template_dir" "$template_file"

    # Process the template
    process_template "$version" "$template_file"

    # Verify the preparation was successful
    if [ ! -f "$template_file" ]; then
        echo "Error: Failed to download or process operator template"
        exit 1
    fi
}

# ##################################################
# Function to display summary information
# ##################################################
display_summary() {
    echo "Apicurio Registry Operator template preparation completed successfully!"
    echo "Template location: $APICURIO_OPERATOR_YAML"
}

# ##################################################
# Main execution
# ##################################################
main() {
    # Parse command line arguments
    parse_arguments "$@"

    # Validate parameters and set defaults
    validate_and_set_defaults

    # Prepare the template (download if needed, then process)
    prepare_template "$APICURIO_REGISTRY_VERSION"

    # Display summary
    display_summary
}

# Execute main function with all arguments
main "$@"
