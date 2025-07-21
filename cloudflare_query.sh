#!/bin/bash

# Cloudflare API Query Script
# This script queries Cloudflare zones and DNS records

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to display usage
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -e, --email EMAIL        Cloudflare API email"
    echo "  -k, --key KEY           Cloudflare API key"
    echo "  -z, --zone-id ZONE_ID   Cloudflare Zone ID (optional)"
    echo "  -h, --help              Show this help message"
    echo ""
    echo "Environment Variables:"
    echo "  CLOUDFLARE_API_EMAIL    Cloudflare API email"
    echo "  CLOUDFLARE_API_KEY      Cloudflare API key"
    echo "  CLOUDFLARE_ZONE_ID      Cloudflare Zone ID (optional)"
    echo ""
    echo "Examples:"
    echo "  $0 -e user@example.com -k your_api_key"
    echo "  $0 -e user@example.com -k your_api_key -z zone_id_here"
    echo "  CLOUDFLARE_API_EMAIL=user@example.com CLOUDFLARE_API_KEY=key $0"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -e|--email)
            CLOUDFLARE_API_EMAIL="$2"
            shift 2
            ;;
        -k|--key)
            CLOUDFLARE_API_KEY="$2"
            shift 2
            ;;
        -z|--zone-id)
            CLOUDFLARE_ZONE_ID="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Check if required credentials are provided
if [[ -z "$CLOUDFLARE_API_EMAIL" ]]; then
    print_error "Cloudflare API email is required"
    usage
    exit 1
fi

if [[ -z "$CLOUDFLARE_API_KEY" ]]; then
    print_error "Cloudflare API key is required"
    usage
    exit 1
fi

# Cloudflare API base URL
CF_API_BASE="https://api.cloudflare.com/client/v4"

# Function to make API requests
make_api_request() {
    local endpoint="$1"
    local response
    
    response=$(curl -s -X GET "$CF_API_BASE$endpoint" \
        -H "X-Auth-Email: $CLOUDFLARE_API_EMAIL" \
        -H "X-Auth-Key: $CLOUDFLARE_API_KEY" \
        -H "Content-Type: application/json")
    
    echo "$response"
}

# Function to check if API response was successful
check_api_response() {
    local response="$1"
    local success
    
    success=$(echo "$response" | jq -r '.success // false')
    
    if [[ "$success" != "true" ]]; then
        print_error "API request failed"
        echo "$response" | jq -r '.errors[]?.message // "Unknown error"' | while read -r error; do
            print_error "$error"
        done
        return 1
    fi
    
    return 0
}

# Function to find zone ID for example.com
find_zone_id() {
    print_info "Searching for example.com zone..."
    
    local response
    response=$(make_api_request "/zones?name=example.com")
    
    if ! check_api_response "$response"; then
        return 1
    fi
    
    local zone_id
    zone_id=$(echo "$response" | jq -r '.result[0]?.id // empty')
    
    if [[ -n "$zone_id" ]]; then
        print_success "Found example.com zone ID: $zone_id"
        echo "$zone_id"
        return 0
    else
        print_warning "Zone example.com not found"
        return 1
    fi
}

# Function to list all zones
list_all_zones() {
    print_info "Fetching all zones..."
    
    local response
    response=$(make_api_request "/zones")
    
    if ! check_api_response "$response"; then
        return 1
    fi
    
    local zones
    zones=$(echo "$response" | jq -r '.result[]? | "\(.name) (ID: \(.id)) - Status: \(.status)"')
    
    if [[ -n "$zones" ]]; then
        print_success "Found zones:"
        echo "$zones" | while read -r zone; do
            echo "  • $zone"
        done
    else
        print_warning "No zones found"
    fi
}

# Function to list DNS records for a zone
list_dns_records() {
    local zone_id="$1"
    local zone_name="$2"
    
    print_info "Fetching DNS records for zone: $zone_name ($zone_id)"
    
    local response
    response=$(make_api_request "/zones/$zone_id/dns_records")
    
    if ! check_api_response "$response"; then
        return 1
    fi
    
    local records
    records=$(echo "$response" | jq -r '.result[]? | "\(.type) \(.name) -> \(.content) (TTL: \(.ttl))"')
    
    if [[ -n "$records" ]]; then
        print_success "DNS records for $zone_name:"
        echo "$records" | while read -r record; do
            echo "  • $record"
        done
    else
        print_warning "No DNS records found for $zone_name"
    fi
}

# Main execution
main() {
    print_info "Starting Cloudflare API query..."
    print_info "Email: $CLOUDFLARE_API_EMAIL"
    
    # Check if jq is installed
    if ! command -v jq &> /dev/null; then
        print_error "jq is required but not installed. Please install jq to parse JSON responses."
        exit 1
    fi
    
    echo ""
    echo "========================="
    echo "  CLOUDFLARE API QUERY  "
    echo "========================="
    echo ""
    
    # List all zones first
    list_all_zones
    echo ""
    
    # Find and query example.com zone
    local kosmos_zone_id
    
    if [[ -n "$CLOUDFLARE_ZONE_ID" ]]; then
        print_info "Using provided Zone ID: $CLOUDFLARE_ZONE_ID"
        kosmos_zone_id="$CLOUDFLARE_ZONE_ID"
    else
        kosmos_zone_id=$(find_zone_id)
    fi
    
    if [[ -n "$kosmos_zone_id" ]]; then
        echo ""
        list_dns_records "$kosmos_zone_id" "example.com"
    else
        print_error "Could not find or determine Zone ID for example.com"
        exit 1
    fi
    
    echo ""
    print_success "Query completed successfully!"
}

# Run main function
main "$@" 