#!/bin/bash

# Function to display usage information
show_usage() {
    # Get the directory where this script is located for dynamic config file listing
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local rapidast_templates_dir="$script_dir/templates/rapidast"
    
    echo "Usage: $0 [--cluster <cluster_name>] --namespace <namespace> [--config <config_file>] [--tag <rapidast_tag>] [--authEnabled <true|false>] [--gcsKeyFile <path>]"
    echo ""
    echo "This script runs RapiDAST (Rapid DAST) security scanning against a deployed application."
    echo "The target application URL should be configured in the provided rapidast YAML configuration file."
    echo ""
    echo "Arguments:"
    echo "  --cluster           Optional. The OpenShift cluster name (default: \$USER)"
    echo "  --namespace         Required. The namespace where the target application is deployed"
    echo "  --config            Optional. Path to the rapidast YAML configuration file (default: registry_v3_unauthenticated.yaml)"
    
    # Dynamically list available configuration files
    if [ -d "$rapidast_templates_dir" ]; then
        echo "                      Valid values:"
        for config_file in "$rapidast_templates_dir"/*.yaml; do
            if [ -f "$config_file" ]; then
                local filename=$(basename "$config_file")
                echo "                        - $filename"
            fi
        done
    else
        echo "                      (Configuration files directory not found: $rapidast_templates_dir)"
    fi
    
    echo "  --tag               Optional. Git branch/tag of rapidast to use (default: development)"
    echo "  --authEnabled       Optional. Enable OAuth2 authentication (true|false). When enabled, automatically derives auth settings."
    echo "  --gcsKeyFile        Optional. Path to Google Cloud Storage service account key file. When provided, scan results"
    echo "                      are exported to the ProdSec central storage bucket (secaut-bucket)."
    echo ""
    echo "Example: $0 --cluster okd419 --namespace testns1"
    echo "Example: $0 --cluster okd419 --namespace testns1 --config registry_v3_authenticated.yaml --tag 2.12.1"
    echo "Example: $0 --cluster okd419 --namespace testns1 --authEnabled true"
    echo "Example: $0 --cluster okd419 --namespace testns1 --gcsKeyFile /path/to/gcs-key.json"
}

ACCESS_TOKEN=""

# Function to retrieve OAuth2 access token using Resource Owner Password Credentials Grant
get_oauth2_token() {
    local token_url="$1"
    local client_id="$2"
    local client_secret="$3"
    local username="$4"
    local password="$5"
    
    # Check if jq is available
    if ! command -v jq &> /dev/null; then
        echo "Error: jq is required for JSON parsing but not found. Please install jq."
        exit 1
    fi
    
    echo "Retrieving OAuth2 access token from: $token_url"
    
    # Make the OAuth2 token request
    local response
    response=$(curl -s -X POST "$token_url" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "grant_type=password" \
        -d "client_id=$client_id" \
        -d "client_secret=$client_secret" \
        -d "username=$username" \
        -d "password=$password")
    
    # Check if curl command was successful
    if [ $? -ne 0 ]; then
        echo "Error: Failed to retrieve OAuth2 token - curl command failed"
        exit 1
    fi
    
    # Extract access token from JSON response using jq
    local access_token
    access_token=$(echo "$response" | jq -r '.access_token')
    
    # Check if jq parsing was successful and token exists
    if [ $? -ne 0 ]; then
        echo "Error: Failed to parse JSON response with jq"
        exit 1
    fi
    
    if [ -z "$access_token" ] || [ "$access_token" = "null" ]; then
        echo "Error: Failed to extract access token from OAuth2 response"
        exit 1
    fi
    
    echo "Successfully retrieved OAuth2 access token"
    ACCESS_TOKEN="$access_token"
}


# Install ZAP if not already available
install_zap() {
    local dast_tests_dir="$1"

    echo "Checking for ZAP installation..."
    
    # Check if ZAP is already available on PATH
    if command -v zap.sh &> /dev/null || command -v zap &> /dev/null; then
        echo "ZAP is already installed and available on PATH"
        return 0
    fi
    
    # Check if ZAP is already installed in our local directory
    if [ -f "$dast_tests_dir/ZAP_2.16.1/zap.sh" ]; then
        echo "ZAP found in local directory, adding to PATH"
        export PATH="$dast_tests_dir/ZAP_2.16.1:$PATH"
        return 0
    fi
    
    echo "ZAP not found, downloading and installing..."
    
    # Download ZAP Linux package
    ZAP_VERSION="2.16.1"
    ZAP_DOWNLOAD_URL="https://github.com/zaproxy/zaproxy/releases/download/v${ZAP_VERSION}/ZAP_${ZAP_VERSION}_Linux.tar.gz"
    ZAP_ARCHIVE="ZAP_${ZAP_VERSION}_Linux.tar.gz"
    
    echo "Downloading ZAP from: $ZAP_DOWNLOAD_URL"
    if ! curl -L -o "$ZAP_ARCHIVE" "$ZAP_DOWNLOAD_URL"; then
        echo "Error: Failed to download ZAP"
        exit 1
    fi
    
    # Extract ZAP
    echo "Extracting ZAP..."
    if ! tar -xzf "$ZAP_ARCHIVE"; then
        echo "Error: Failed to extract ZAP archive"
        exit 1
    fi
    
    # Clean up archive
    rm -f "$ZAP_ARCHIVE"
    
    # Check if extraction was successful
    if [ ! -f "ZAP_${ZAP_VERSION}/zap.sh" ]; then
        echo "Error: ZAP installation failed - zap.sh not found"
        exit 1
    fi
    
    # Make zap.sh executable
    chmod +x "ZAP_${ZAP_VERSION}/zap.sh"
    
    # Add ZAP to PATH for this session
    export PATH="$dast_tests_dir/ZAP_${ZAP_VERSION}:$PATH"
    
    echo "ZAP ${ZAP_VERSION} installed successfully"
    
    # Verify installation
    if command -v zap.sh &> /dev/null; then
        echo "ZAP is now available on PATH"
    else
        echo "Warning: ZAP may not be properly configured on PATH"
    fi
}


# Parse command line arguments
CLUSTER_NAME="$USER"
NAMESPACE=""
CONFIG_FILE=""
RAPIDAST_TAG="development"
AUTH_ENABLED="false"
GCS_KEY_FILE=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --cluster)
            CLUSTER_NAME="$2"
            shift 2
            ;;
        --namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        --config)
            CONFIG_FILE="$2"
            shift 2
            ;;
        --tag)
            RAPIDAST_TAG="$2"
            shift 2
            ;;
        --authEnabled)
            AUTH_ENABLED="$2"
            shift 2
            ;;
        --gcsKeyFile)
            GCS_KEY_FILE="$2"
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

# Validate cluster name (should not be empty after defaulting to $USER)
if [ -z "$CLUSTER_NAME" ]; then
    echo "Error: cluster name is empty (default: \$USER)"
    show_usage
    exit 1
fi

if [ -z "$NAMESPACE" ]; then
    echo "Error: --namespace argument is required"
    show_usage
    exit 1
fi

if [ -z "$CONFIG_FILE" ]; then
    CONFIG_FILE="registry_v3_unauthenticated.yaml"
fi

# Validate authEnabled parameter
if [ -n "$AUTH_ENABLED" ] && [ "$AUTH_ENABLED" != "true" ] && [ "$AUTH_ENABLED" != "false" ]; then
    echo "Error: --authEnabled must be 'true' or 'false'"
    show_usage
    exit 1
fi

# Validate GCS key file if provided
if [ -n "$GCS_KEY_FILE" ]; then
    if [ ! -f "$GCS_KEY_FILE" ]; then
        echo "Error: GCS key file not found: $GCS_KEY_FILE"
        exit 1
    fi
fi

# Set base domain for URL construction
BASE_DOMAIN="apicurio-testing.org"
SCHEME="http"

# Validate and auto-configure authentication
AUTH_TOKEN_URL=""
AUTH_CLIENT_ID=""
AUTH_CLIENT_SECRET=""
AUTH_USERNAME=""
AUTH_PASSWORD=""

if [ "$AUTH_ENABLED" = "true" ]; then
    # Auto-derive authentication variables
    echo "Authentication enabled - auto-configuring auth variables..."
    
    # Auto-derive Keycloak token URL based on cluster and namespace
    KEYCLOAK_URL="keycloak-$NAMESPACE.apps.$CLUSTER_NAME.$BASE_DOMAIN"
    AUTH_TOKEN_URL="https://$KEYCLOAK_URL/realms/registry/protocol/openid-connect/token"
    
    # Use placeholder values for credentials (to be replaced with actual values)
    AUTH_CLIENT_ID="rapidast-client"
    AUTH_CLIENT_SECRET="rapidast-client-secret"
    AUTH_USERNAME="registry-admin"
    AUTH_PASSWORD="secret"
    SCHEME="https"
    
    echo "Auto-configured authentication settings:"
    echo "  Token URL: $AUTH_TOKEN_URL"
    echo "  Client ID: $AUTH_CLIENT_ID"
    echo "  Client Secret: **********"
    echo "  Username: $AUTH_USERNAME (placeholder)"
    echo "  Password: **********"
    echo ""
    echo "NOTE: Replace placeholder credentials with actual values in your environment or credential store."
fi

# Get the directory where this script is located
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$BASE_DIR/shared.sh"

load_cluster_config "$CLUSTER_NAME"

export CLUSTER_NAME
export RAPIDAST_TAG
export NAMESPACE
export BASE_DOMAIN
export TESTS_DIR="$CLUSTER_DIR/namespaces/$NAMESPACE/tests"
export DAST_TESTS_DIR="$TESTS_DIR/dast"
export APPS_URL="apps.$CLUSTER_NAME.$BASE_DOMAIN"

# Common application URLs that might be useful for rapidast configuration
export REGISTRY_APP_URL="$SCHEME://registry-app-$NAMESPACE.$APPS_URL"
export REGISTRY_UI_URL="$SCHEME://registry-ui-$NAMESPACE.$APPS_URL"

mkdir -p $DAST_TESTS_DIR
cd $DAST_TESTS_DIR

# Make sure ZAP is installed
install_zap $DAST_TESTS_DIR

# Clone the rapidast repository
echo "Cloning rapidast git repository at branch/tag: $RAPIDAST_TAG"
if [ -d "rapidast" ]; then
    echo "Repository already exists, removing and re-cloning..."
    rm -rf rapidast
fi
git clone --branch $RAPIDAST_TAG --depth 1 https://github.com/RedHatProductSecurity/rapidast.git

# Change to the repository directory
cd rapidast

# Check if config file exists
if [ ! -f "$BASE_DIR/templates/rapidast/$CONFIG_FILE" ]; then
    echo "Error: Configuration file '$CONFIG_FILE' does not exist"
    exit 1
fi

# Retrieve OAuth2 access token if authentication is configured
if [ -n "$AUTH_TOKEN_URL" ]; then
    get_oauth2_token "$AUTH_TOKEN_URL" "$AUTH_CLIENT_ID" "$AUTH_CLIENT_SECRET" "$AUTH_USERNAME" "$AUTH_PASSWORD"
    export ACCESS_TOKEN
    echo "Access token retrieved and exported as ACCESS_TOKEN environment variable"

    echo "Checking that the access token works..."
    echo "--"
    
    # Get user info and validate the response
    USER_INFO_RESPONSE=$(curl -s -H "Authorization: Bearer $ACCESS_TOKEN" $REGISTRY_APP_URL/apis/registry/v3/users/me)
    echo "User info response: $USER_INFO_RESPONSE"
    
    # Parse and validate the response
    USERNAME=$(echo "$USER_INFO_RESPONSE" | jq -r '.username // empty')
    IS_ADMIN=$(echo "$USER_INFO_RESPONSE" | jq -r '.admin // false')
    
    echo "Username: $USERNAME"
    echo "Is Admin: $IS_ADMIN"
    
    # Validate that username is "registry-admin" and admin is true
    if [ "$USERNAME" != "registry-admin" ]; then
        echo "ERROR: Expected username 'registry-admin' but got '$USERNAME'"
        exit 1
    fi
    
    if [ "$IS_ADMIN" != "true" ]; then
        echo "ERROR: Expected admin field to be true but got '$IS_ADMIN'"
        exit 1
    fi
    
    echo "✓ Access token validation successful - user is registry-admin with admin privileges"
    echo "--"
fi

# Copy the configuration file to the rapidast directory
export DAST_BASE_URL=$REGISTRY_APP_URL
RAPIDAST_CONFIG=$DAST_TESTS_DIR/rapidast-config.yaml
envsubst < $BASE_DIR/templates/rapidast/$CONFIG_FILE > $RAPIDAST_CONFIG

# Inject Google Cloud Storage export configuration if a GCS key file was provided
if [ -n "$GCS_KEY_FILE" ]; then
    echo "Configuring Google Cloud Storage export..."
    GCS_CONFIG="  googleCloudStorage:\n    keyFile: \"$GCS_KEY_FILE\"\n    bucketName: secaut-bucket\n    directory: \"apicurio-registry\""
    sed -i "/^config:/a\\$GCS_CONFIG" $RAPIDAST_CONFIG
fi

# Check if Python 3.12+ is available
if ! command -v python3.12 &> /dev/null; then
    if ! command -v python3 &> /dev/null; then
        echo "Error: Python 3 is required but not found. Please install Python 3.12 or later."
        exit 1
    else
        PYTHON_CMD="python3"
        echo "Warning: python3.12 not found, using python3. RapiDAST requires Python 3.12+."
    fi
else
    PYTHON_CMD="python3.12"
fi

# Display some diagnostic info
echo ""
echo "RapiDAST DAST Scan Info:"
echo "--"
echo "Cluster: $CLUSTER_NAME"
echo "Namespace: $NAMESPACE"
echo "RapiDAST version: $RAPIDAST_TAG"
echo "Configuration file: $RAPIDAST_CONFIG"
echo "URL under test: $DAST_BASE_URL"
if [ -n "$AUTH_TOKEN_URL" ]; then
    echo "OAuth2 Authentication: Enabled (Token URL: $AUTH_TOKEN_URL)"
else
    echo "OAuth2 Authentication: Disabled"
fi
if [ -n "$GCS_KEY_FILE" ]; then
    echo "GCS Export: Enabled (bucket: secaut-bucket, directory: apicurio-registry)"
else
    echo "GCS Export: Disabled"
fi
echo "Available application URLs:"
echo "  Registry App:  $REGISTRY_APP_URL"
echo "  Registry UI:   $REGISTRY_UI_URL"
if [ "$AUTH_ENABLED" = "true" ]; then
    echo "  Keycloak:      https://$KEYCLOAK_URL"
fi
echo "--"
echo ""

# Create the virtual environment
echo "Creating the virtual environment"
$PYTHON_CMD -m venv venv
source venv/bin/activate

# Install requirements
echo "Installing requirements"
pip install -U pip
pip install -r requirements.txt

# Run rapidast with the provided configuration
echo ""
echo "------------------------------------"
echo "Running RapiDAST DAST Security Scan..."
echo "------------------------------------"
echo ""
$PYTHON_CMD rapidast.py --config $RAPIDAST_CONFIG

RAPIDAST_EXIT_CODE=$?

echo ""
if [ $RAPIDAST_EXIT_CODE -eq 0 ]; then
    echo "RapiDAST DAST scan completed successfully."
    echo ""
    echo "Results are available in the 'results/' directory:"
    if [ -d "results" ]; then
        find results -type f -name "*.html" -o -name "*.json" -o -name "*.xml" -o -name "*.sarif" | head -10
        if [ $(find results -type f | wc -l) -gt 10 ]; then
            echo "... and more files in results/"
        fi
    fi
else
    echo "RapiDAST DAST scan failed with exit code: $RAPIDAST_EXIT_CODE"
    exit $RAPIDAST_EXIT_CODE
fi
