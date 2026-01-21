#!/bin/bash

#############################################################################
# Keycloak Admin Menu - MaaS Tenants Realm Manager
# Menu structure implementation (API calls to be added incrementally)
#############################################################################

# Configuration
KEYCLOAK_URL="https://keycloak.apps.ethan-sno-kk.sandbox3469.opentlc.com"
REALM="maas-tenants"
CLIENT_ID="realm-admin-cli"
CLIENT_SECRET="${KEYCLOAK_ADMIN_SECRET}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Settings
DEBUG=false
AUTO_PAUSE=true
TOKEN=""
TOKEN_EXPIRES=0

#############################################################################
# Utility Functions
#############################################################################

# Clear screen
clear_screen() {
    clear
}

# Pause with message
pause() {
    local message="${1:-Press Enter to continue...}"
    echo ""
    echo -e "${CYAN}${message}${NC}"
    read
}

# Show success message
show_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

# Show error message
show_error() {
    echo -e "${RED}✗ Error: $1${NC}"
}

# Show warning message
show_warning() {
    echo -e "${YELLOW}⚠ Warning: $1${NC}"
}

# Show info message
show_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

# Draw box header
draw_header() {
    local title="$1"
    local width=60
    echo ""
    echo "╔$(printf '═%.0s' $(seq 1 $width))╗"
    printf "║ %-${width}s ║\n" "$title"
    echo "╚$(printf '═%.0s' $(seq 1 $width))╝"
    echo ""
}

# Draw separator
draw_separator() {
    echo "─────────────────────────────────────────────────────────────"
}

# Confirm action
confirm_action() {
    local prompt="$1"
    local confirm_text="${2:-yes}"
    
    echo ""
    echo -e "${YELLOW}${prompt}${NC}"
    echo -n "Type '${confirm_text}' to confirm: "
    read confirmation
    
    if [ "$confirmation" = "$confirm_text" ]; then
        return 0
    else
        show_info "Action cancelled"
        return 1
    fi
}

# Get user input
get_input() {
    local prompt="$1"
    local default="$2"
    local result
    
    # Redirect prompt to stderr so it doesn't get captured by command substitution
    if [ -n "$default" ]; then
        echo -n "${prompt} [${default}]: " >&2
    else
        echo -n "${prompt}: " >&2
    fi
    
    read result
    
    if [ -z "$result" ] && [ -n "$default" ]; then
        echo "$default"
    else
        echo "$result"
    fi
}

#############################################################################
# Authentication Functions
#############################################################################

# Get or refresh access token
get_token() {
    local current_time=$(date +%s)
    
    # Return cached token if still valid (with 60 second buffer)
    if [ -n "$TOKEN" ] && [ $current_time -lt $((TOKEN_EXPIRES - 60)) ]; then
        return 0
    fi
    
    if [ "$DEBUG" = true ]; then
        show_info "Getting access token..."
    fi
    
    # Get token using client_credentials grant
    local response=$(curl -s -X POST "${KEYCLOAK_URL}/realms/${REALM}/protocol/openid-connect/token" \
        -d "client_id=${CLIENT_ID}" \
        -d "client_secret=${CLIENT_SECRET}" \
        -d "grant_type=client_credentials")
    
    # Check if request was successful
    if [ $? -ne 0 ]; then
        show_error "Failed to connect to Keycloak"
        return 1
    fi
    
    # Extract token from response
    TOKEN=$(echo "$response" | jq -r '.access_token // empty')
    
    if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
        show_error "Failed to get access token"
        echo "Response: $response" >&2
        return 1
    fi
    
    # Extract expiry time
    local expires_in=$(echo "$response" | jq -r '.expires_in // 300')
    TOKEN_EXPIRES=$((current_time + expires_in))
    
    if [ "$DEBUG" = true ]; then
        show_success "Token acquired (expires in ${expires_in} seconds)"
    fi
    
    return 0
}

# Check token expiry and warn if needed
check_token_expiry() {
    local current_time=$(date +%s)
    local remaining=$((TOKEN_EXPIRES - current_time))
    
    if [ $remaining -lt 60 ] && [ $remaining -gt 0 ]; then
        show_warning "Token expires in ${remaining} seconds"
        return 1
    elif [ $remaining -le 0 ]; then
        show_error "Token expired"
        return 2
    fi
    
    return 0
}

# Display token status
show_token_status() {
    local current_time=$(date +%s)
    local remaining=$((TOKEN_EXPIRES - current_time))
    
    if [ $remaining -gt 0 ]; then
        echo "Token expires in: ${remaining} seconds"
    else
        echo "Token: expired"
    fi
}

#############################################################################
# API Wrapper Functions
#############################################################################

# API GET request
api_get() {
    local endpoint="$1"
    local response
    
    response=$(curl -s -X GET "${KEYCLOAK_URL}${endpoint}" \
        -H "Authorization: Bearer ${TOKEN}" \
        -H "Content-Type: application/json")
    
    echo "$response"
}

api_post() {
    local endpoint="$1"
    local payload="$2"
    local response
    
    response=$(curl -s -w "\n%{http_code}" -X POST "${KEYCLOAK_URL}${endpoint}" \
        -H "Authorization: Bearer ${TOKEN}" \
        -H "Content-Type: application/json" \
        -d "$payload")
    
    local http_code=$(echo "$response" | tail -1)
    local body=$(echo "$response" | sed '$d')
    
    if [ "$http_code" -ge 200 ] && [ "$http_code" -lt 300 ]; then
        echo "$body"
        return 0
    else
        echo "$body" >&2
        return 1
    fi
}

api_put() {
    local endpoint="$1"
    local payload="$2"
    local response
    
    response=$(curl -s -w "\n%{http_code}" -X PUT "${KEYCLOAK_URL}${endpoint}" \
        -H "Authorization: Bearer ${TOKEN}" \
        -H "Content-Type: application/json" \
        -d "$payload")
    
    local http_code=$(echo "$response" | tail -1)
    local body=$(echo "$response" | sed '$d')
    
    if [ "$http_code" -ge 200 ] && [ "$http_code" -lt 300 ]; then
        echo "$body"
        return 0
    else
        echo "$body" >&2
        return 1
    fi
}

api_delete() {
    local endpoint="$1"
    local response
    
    response=$(curl -s -w "\n%{http_code}" -X DELETE "${KEYCLOAK_URL}${endpoint}" \
        -H "Authorization: Bearer ${TOKEN}" \
        -H "Content-Type: application/json")
    
    local http_code=$(echo "$response" | tail -1)
    local body=$(echo "$response" | sed '$d')
    
    if [ "$http_code" -ge 200 ] && [ "$http_code" -lt 300 ]; then
        echo "$body"
        return 0
    else
        echo "$body" >&2
        return 1
    fi
}

# Extract ID from Location header
extract_id_from_location() {
    local location_header="$1"
    echo "$location_header" | grep -i "^Location:" | sed 's/.*\///g' | tr -d '\r\n'
}

# Find group by path
find_group_by_path() {
    local path="$1"
    
    # Split path into parts
    local parts=(${path//\// })
    
    # Filter out empty parts
    local filtered_parts=()
    for part in "${parts[@]}"; do
        if [ -n "$part" ]; then
            filtered_parts+=("$part")
        fi
    done
    parts=("${filtered_parts[@]}")
    
    if [ ${#parts[@]} -eq 0 ]; then
        return 1
    fi
    
    if [ ${#parts[@]} -eq 1 ]; then
        # Top-level group (tenant)
        local group_name="${parts[0]}"
        local response=$(api_get "/admin/realms/${REALM}/groups?search=${group_name}")
        echo "$response" | jq -r ".[] | select(.path == \"${path}\") | .id" 2>/dev/null | head -1
    else
        # Nested group - traverse the hierarchy
        local parent_name="${parts[0]}"
        
        # Find top-level parent group
        local parent_path="/${parent_name}"
        local parent_response=$(api_get "/admin/realms/${REALM}/groups?search=${parent_name}")
        local parent_id=$(echo "$parent_response" | jq -r ".[] | select(.path == \"${parent_path}\") | .id" 2>/dev/null | head -1)
        
        if [ -z "$parent_id" ]; then
            return 1
        fi
        
        # Traverse through remaining levels
        local current_id="$parent_id"
        local current_path="/${parent_name}"
        
        for (( i=1; i<${#parts[@]}; i++ )); do
            local child_name="${parts[$i]}"
            local target_path="${current_path}/${child_name}"
            
            # Get children of current group
            local children=$(api_get "/admin/realms/${REALM}/groups/${current_id}/children")
            local child_id=$(echo "$children" | jq -r ".[] | select(.path == \"${target_path}\") | .id" 2>/dev/null | head -1)
            
            if [ -z "$child_id" ]; then
                return 1
            fi
            
            current_id="$child_id"
            current_path="$target_path"
        done
        
        echo "$current_id"
    fi
}

# Find user by email, username, or ID
find_user_by_email() {
    local search_term="$1"
    
    # Strategy 0: Check if it looks like a UUID (user ID) - try direct lookup
    if [[ "$search_term" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then
        # It's a UUID, try direct lookup
        local response=$(api_get "/admin/realms/${REALM}/users/${search_term}" 2>/dev/null)
        local user_id=$(echo "$response" | jq -r '.id // empty' 2>/dev/null)
        if [ -n "$user_id" ] && [ "$user_id" != "null" ]; then
            echo "$user_id"
            return
        fi
    fi
    
    # URL encode the search term (use printf to avoid trailing newline)
    local encoded_term=$(printf '%s' "$search_term" | jq -sRr @uri)
    
    # Strategy 1: Try exact match by email
    local response=$(api_get "/admin/realms/${REALM}/users?email=${encoded_term}&exact=true")
    local user_id=$(echo "$response" | jq -r '.[0].id // empty' 2>/dev/null)
    
    # Strategy 2: If not found, try exact match by username
    if [ -z "$user_id" ] || [ "$user_id" = "null" ]; then
        response=$(api_get "/admin/realms/${REALM}/users?username=${encoded_term}&exact=true")
        user_id=$(echo "$response" | jq -r '.[0].id // empty' 2>/dev/null)
    fi
    
    # Strategy 3: If still not found, do broad search and filter manually
    if [ -z "$user_id" ] || [ "$user_id" = "null" ]; then
        response=$(api_get "/admin/realms/${REALM}/users?search=${encoded_term}")
        user_id=$(echo "$response" | jq -r ".[] | select(.email == \"${search_term}\" or .username == \"${search_term}\") | .id" 2>/dev/null | head -1)
    fi
    
    echo "$user_id"
}

# Get group members count
get_group_member_count() {
    local group_id="$1"
    
    local response=$(api_get "/admin/realms/${REALM}/groups/${group_id}/members")
    echo "$response" | jq 'length' 2>/dev/null || echo "0"
}

# Get group children count
get_group_children_count() {
    local group_id="$1"
    
    local response=$(api_get "/admin/realms/${REALM}/groups/${group_id}/children")
    echo "$response" | jq 'length' 2>/dev/null || echo "0"
}

# Format timestamp
format_date() {
    local timestamp="$1"
    if [ -n "$timestamp" ] && [ "$timestamp" != "null" ]; then
        date -d "@$((timestamp / 1000))" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "$timestamp"
    else
        echo "N/A"
    fi
}

# Truncate ID for display
truncate_id() {
    local id="$1"
    if [ -n "$id" ] && [ "$id" != "null" ]; then
        echo "${id:0:20}..."
    else
        echo "N/A"
    fi
}

#############################################################################
# Main Menu
#############################################################################

show_main_menu() {
    clear_screen
    draw_header "Keycloak Admin - MaaS Tenants Realm"
    echo "  Realm: ${REALM}"
    echo "  $(show_token_status)"
    echo ""
    echo "  1. Manage Tenants"
    echo "  2. Manage Tenant Groups"
    echo "  3. Manage Tenant Users"
    echo ""
    echo "  0. Exit"
    echo ""
    echo -n "Select option: "
}

main_menu() {
    while true; do
        get_token || {
            show_error "Failed to authenticate"
            exit 1
        }
        
        show_main_menu
        read choice
        
        case $choice in
            1) manage_tenants_menu ;;
            2) manage_groups_menu ;;
            3) manage_users_menu ;;
            0) 
                clear_screen
                show_success "Goodbye!"
                exit 0
                ;;
            *)
                show_error "Invalid option"
                pause
                ;;
        esac
    done
}

#############################################################################
# Menu 1: Manage Tenants
#############################################################################

show_tenants_menu() {
    clear_screen
    draw_header "Manage Tenants"
    echo "  1. Create Tenant"
    echo "  2. List All Tenants"
    echo "  3. View Tenant Details"
    echo "  4. Update Tenant Attributes"
    echo "  5. Delete Tenant"
    echo ""
    echo "  0. Back to Main Menu"
    echo ""
    echo -n "Select option: "
}

manage_tenants_menu() {
    while true; do
        show_tenants_menu
        read choice
        
        case $choice in
            1) create_tenant ;;
            2) list_tenants ;;
            3) view_tenant_details ;;
            4) update_tenant_attributes ;;
            5) delete_tenant ;;
            0) return ;;
            *)
                show_error "Invalid option"
                pause
                ;;
        esac
    done
}

# 1.1 Create Tenant
create_tenant() {
    clear_screen
    draw_header "Create Tenant"
    
    tenant_name=$(get_input "Enter tenant name (e.g., acme-inc-2)")
    
    if [ -z "$tenant_name" ]; then
        show_error "Tenant name is required"
        pause
        return
    fi
    
    # Check if tenant already exists
    show_info "Checking if tenant exists..."
    local tenant_path="/${tenant_name}"
    local existing_id=$(find_group_by_path "$tenant_path")
    
    if [ -n "$existing_id" ] && [ "$existing_id" != "null" ]; then
        show_error "Tenant '${tenant_name}' already exists"
        pause
        return
    fi
    
    show_info "Creating tenant: ${tenant_name}..."
    
    # Create the top-level tenant group
    local tenant_payload=$(cat <<EOF
{
    "name": "${tenant_name}"
}
EOF
)
    
    local create_response=$(api_post "/admin/realms/${REALM}/groups" "$tenant_payload")
    
    if [ $? -ne 0 ]; then
        show_error "Failed to create tenant group"
        pause
        return
    fi
    
    # Get the ID of the newly created tenant group
    show_info "Retrieving tenant group ID..."
    local tenant_id=$(find_group_by_path "$tenant_path")
    
    if [ -z "$tenant_id" ] || [ "$tenant_id" = "null" ]; then
        show_error "Failed to retrieve tenant group ID"
        pause
        return
    fi
    
    # Create a subgroup with "-dedicated" suffix
    local subgroup_name="${tenant_name}-dedicated"
    show_info "Creating subgroup: ${subgroup_name}..."
    
    local subgroup_payload=$(cat <<EOF
{
    "name": "${subgroup_name}"
}
EOF
)
    
    local subgroup_response=$(api_post "/admin/realms/${REALM}/groups/${tenant_id}/children" "$subgroup_payload")
    
    if [ $? -ne 0 ]; then
        show_error "Failed to create subgroup"
        show_info "Tenant group was created, but subgroup creation failed"
        pause
        return
    fi
    
    # Set default attributes on the tenant group
    show_info "Setting default attributes..."
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local attributes_payload=$(jq -n \
        --arg name "$tenant_name" \
        --arg desc "Tenant: ${tenant_name}" \
        --arg created "$timestamp" \
        '{name: $name, attributes: {description: [$desc], created_at: [$created]}}')
    
    local attr_response=$(api_put "/admin/realms/${REALM}/groups/${tenant_id}" "$attributes_payload")
    
    if [ $? -ne 0 ]; then
        show_error "Failed to set default attributes"
        show_info "Tenant and subgroup were created, but attributes were not set"
    fi
    
    # Success
    echo ""
    show_success "Tenant '${tenant_name}' created successfully"
    echo "  - Tenant ID: ${tenant_id}"
    echo "  - Tenant Path: /${tenant_name}"
    echo "  - Subgroup Path: /${tenant_name}/${subgroup_name}"
    echo "  - Created at: ${timestamp}"
    echo ""
    
    pause
}

# 1.2 List All Tenants
list_tenants() {
    clear_screen
    draw_header "List All Tenants"
    
    show_info "Fetching tenant list..."
    
    # Get all groups
    local response=$(api_get "/admin/realms/${REALM}/groups")
    
    if [ $? -ne 0 ] || [ -z "$response" ]; then
        show_error "Failed to fetch tenants"
        pause
        return
    fi
    
    # Filter top-level groups (tenants) - groups with no parent (path has only one /)
    local tenants=$(echo "$response" | jq -r '.[] | select(.path | split("/") | length == 2)')
    
    local count=$(echo "$tenants" | jq -s 'length')
    
    if [ "$count" -eq 0 ]; then
        echo ""
        show_info "No tenants found"
        pause
        return
    fi
    
    echo ""
    echo "┌─────────────────────────┬──────────────────────────┬───────────┬──────────┐"
    echo "│ Tenant Name             │ Group ID                 │ Subgroups │ Members  │"
    echo "├─────────────────────────┼──────────────────────────┼───────────┼──────────┤"
    
    echo "$tenants" | jq -c '.' | while IFS= read -r tenant; do
        local name=$(echo "$tenant" | jq -r '.name')
        local id=$(echo "$tenant" | jq -r '.id')
        local id_short=$(truncate_id "$id")
        
        # Get counts
        local subgroups=$(get_group_children_count "$id")
        local members=$(get_group_member_count "$id")
        
        printf "│ %-23s │ %-24s │ %-9s │ %-8s │\n" "$name" "$id_short" "$subgroups" "$members"
    done
    
    echo "└─────────────────────────┴──────────────────────────┴───────────┴──────────┘"
    echo ""
    echo "Total tenants: $count"
    
    pause
}

# 1.3 View Tenant Details
view_tenant_details() {
    clear_screen
    draw_header "View Tenant Details"
    
    tenant_name=$(get_input "Enter tenant name")
    
    if [ -z "$tenant_name" ]; then
        show_error "Tenant name is required"
        pause
        return
    fi
    
    show_info "Fetching tenant details..."
    
    # Find the group
    local tenant_path="/${tenant_name}"
    local tenant_id=$(find_group_by_path "$tenant_path")
    
    if [ -z "$tenant_id" ]; then
        show_error "Tenant '${tenant_name}' not found"
        pause
        return
    fi
    
    # Get group details
    local group_details=$(api_get "/admin/realms/${REALM}/groups/${tenant_id}")
    
    # Get subgroups
    local subgroups=$(api_get "/admin/realms/${REALM}/groups/${tenant_id}/children")
    
    # Get members
    local members=$(api_get "/admin/realms/${REALM}/groups/${tenant_id}/members")
    
    # Extract details
    local group_id=$(echo "$group_details" | jq -r '.id')
    local path=$(echo "$group_details" | jq -r '.path')
    local attributes=$(echo "$group_details" | jq -r '.attributes // {}')
    local created_at=$(echo "$attributes" | jq -r '.created_at[0] // "N/A"')
    
    local member_count=$(echo "$members" | jq 'length')
    local subgroup_count=$(echo "$subgroups" | jq 'length')
    
    # Display
    echo ""
    echo "Tenant: ${tenant_name}"
    draw_separator
    echo "Group ID:     ${group_id}"
    echo "Path:         ${path}"
    echo "Created:      ${created_at}"
    
    # Display all attributes
    local all_attrs=$(echo "$attributes" | jq -r 'to_entries[] | select(.key != "created_at") | "\(.key): \(.value[0])"')
    if [ -n "$all_attrs" ]; then
        echo ""
        echo "Attributes:"
        echo "$all_attrs" | while IFS= read -r attr; do
            echo "  • $attr"
        done
    fi
    
    echo ""
    echo "Subgroups (${subgroup_count}):"
    
    if [ "$subgroup_count" -gt 0 ]; then
        echo "$subgroups" | jq -r '.[] | .name' | while read -r subgroup_name; do
            local subgroup_path="${path}/${subgroup_name}"
            local subgroup_id=$(find_group_by_path "$subgroup_path")
            local sub_members=$(get_group_member_count "$subgroup_id")
            echo "  • ${subgroup_path} (${sub_members} members)"
        done
    else
        echo "  (none)"
    fi
    
    echo ""
    echo "Direct Members (${member_count}):"
    
    if [ "$member_count" -gt 0 ]; then
        echo "$members" | jq -r '.[] | "  • \(.username) (\(.firstName) \(.lastName))"'
    else
        echo "  (none)"
    fi
    
    pause
}

# 1.4 Update Tenant Attributes
update_tenant_attributes() {
    clear_screen
    draw_header "Update Tenant Attributes"
    
    tenant_name=$(get_input "Enter tenant name")
    
    if [ -z "$tenant_name" ]; then
        show_error "Tenant name is required"
        pause
        return
    fi
    
    # Find the tenant group
    show_info "Fetching tenant details..."
    local tenant_path="/${tenant_name}"
    local tenant_id=$(find_group_by_path "$tenant_path")
    
    if [ -z "$tenant_id" ] || [ "$tenant_id" = "null" ]; then
        show_error "Tenant '${tenant_name}' not found"
        pause
        return
    fi
    
    # Get current group details
    local group_details=$(api_get "/admin/realms/${REALM}/groups/${tenant_id}")
    
    if [ $? -ne 0 ] || [ -z "$group_details" ]; then
        show_error "Failed to fetch tenant details"
        pause
        return
    fi
    
    # Extract current attributes
    local current_attrs=$(echo "$group_details" | jq -r '.attributes // {}')
    local current_description=$(echo "$current_attrs" | jq -r '.description[0] // ""')
    
    # Display current attributes
    echo ""
    echo "Current Attributes:"
    echo "─────────────────────"
    if [ -n "$current_description" ]; then
        echo "Description: ${current_description}"
    else
        echo "Description: (none)"
    fi
    
    # Show other custom attributes
    local other_attrs=$(echo "$current_attrs" | jq -r 'to_entries[] | select(.key != "description" and .key != "created_at") | "  \(.key): \(.value[0])"')
    if [ -n "$other_attrs" ]; then
        echo ""
        echo "Custom Attributes:"
        echo "$other_attrs"
    fi
    echo ""
    
    # Prompt for new description
    local new_description
    if [ -n "$current_description" ]; then
        new_description=$(get_input "Enter description (current: ${current_description})" "${current_description}")
    else
        new_description=$(get_input "Enter description" "Tenant: ${tenant_name}")
    fi
    
    # Build attributes object
    local attributes_json=$(echo "$current_attrs" | jq --arg desc "$new_description" '. + {description: [$desc]}')
    
    # Ask if user wants to add/update custom attributes
    echo ""
    echo -n "Add or update custom attribute? (y/n): " >&2
    read add_attr
    
    while [ "$add_attr" = "y" ] || [ "$add_attr" = "Y" ]; do
        local attr_key=$(get_input "Enter attribute key")
        if [ -z "$attr_key" ]; then
            show_error "Attribute key is required"
            continue
        fi
        
        local attr_value=$(get_input "Enter attribute value")
        if [ -z "$attr_value" ]; then
            show_error "Attribute value is required"
            continue
        fi
        
        # Add/update the attribute
        attributes_json=$(echo "$attributes_json" | jq --arg key "$attr_key" --arg val "$attr_value" '. + {($key): [$val]}')
        
        echo ""
        echo -n "Add another attribute? (y/n): " >&2
        read add_attr
    done
    
    # Build the update payload
    local group_name=$(echo "$group_details" | jq -r '.name')
    local update_payload=$(jq -n \
        --arg name "$group_name" \
        --argjson attrs "$attributes_json" \
        '{name: $name, attributes: $attrs}')
    
    show_info "Updating tenant attributes..."
    
    # Update the group
    local update_response=$(api_put "/admin/realms/${REALM}/groups/${tenant_id}" "$update_payload")
    
    if [ $? -ne 0 ]; then
        show_error "Failed to update tenant attributes"
        pause
        return
    fi
    
    # Success
    echo ""
    show_success "Tenant '${tenant_name}' updated successfully"
    echo ""
    
    pause
}

# 1.5 Delete Tenant
delete_tenant() {
    clear_screen
    draw_header "Delete Tenant"
    
    tenant_name=$(get_input "Enter tenant name")
    
    if [ -z "$tenant_name" ]; then
        show_error "Tenant name is required"
        pause
        return
    fi
    
    show_warning "This will delete ALL subgroups and remove users from groups (users NOT deleted)"
    
    if ! confirm_action "Are you sure you want to delete tenant '${tenant_name}'?" "$tenant_name"; then
        pause
        return
    fi
    
    # Find the tenant
    show_info "Fetching tenant details..."
    local tenant_path="/${tenant_name}"
    local tenant_id=$(find_group_by_path "$tenant_path")
    
    if [ -z "$tenant_id" ] || [ "$tenant_id" = "null" ]; then
        show_error "Tenant '${tenant_name}' not found"
        pause
        return
    fi
    
    # Get details - use children endpoint to get subgroups
    local subgroups=$(api_get "/admin/realms/${REALM}/groups/${tenant_id}/children")
    local subgroup_count=$(echo "$subgroups" | jq 'length')
    local members=$(api_get "/admin/realms/${REALM}/groups/${tenant_id}/members")
    local member_count=$(echo "$members" | jq 'length')
    
    # Second warning
    clear_screen
    echo ""
    echo "${RED}═══════════════════════════════════════════${NC}"
    echo "${RED}  ⚠️  FINAL WARNING - CANNOT BE UNDONE  ⚠️${NC}"
    echo "${RED}═══════════════════════════════════════════${NC}"
    echo ""
    echo "Deleting tenant: ${tenant_name}"
    echo "  • ${subgroup_count} subgroup(s) will be deleted"
    echo "  • ${member_count} user(s) will be removed from all groups"
    echo "  • Users will NOT be deleted from the realm"
    echo ""
    echo -n "Type 'DELETE' to confirm: " >&2
    read final_confirm
    
    if [ "$final_confirm" != "DELETE" ]; then
        show_info "Action cancelled"
        pause
        return
    fi
    
    # Delete
    show_info "Deleting tenant..."
    api_delete "/admin/realms/${REALM}/groups/${tenant_id}"
    
    if [ $? -ne 0 ]; then
        show_error "Failed to delete tenant"
        pause
        return
    fi
    
    # Success
    echo ""
    show_success "Tenant '${tenant_name}' deleted successfully"
    echo "  • Tenant group deleted: /${tenant_name}"
    echo "  • Subgroups deleted: ${subgroup_count}"
    echo "  • ${member_count} user(s) removed from groups"
    echo "  • Users remain in the realm (not deleted)"
    
    pause
}

#############################################################################
# Menu 2: Manage Tenant Groups
#############################################################################

show_groups_menu() {
    clear_screen
    draw_header "Manage Tenant Groups"
    echo "  1. Create Tenant Group"
    echo "  2. List Tenant Groups"
    echo "  3. View Group Details"
    echo "  4. Update Group Attributes"
    echo "  5. Delete Tenant Group"
    echo ""
    echo "  0. Back to Main Menu"
    echo ""
    echo -n "Select option: "
}

manage_groups_menu() {
    while true; do
        show_groups_menu
        read choice
        
        case $choice in
            1) create_group ;;
            2) list_groups ;;
            3) view_group_details ;;
            4) update_group_attributes ;;
            5) delete_group ;;
            0) return ;;
            *)
                show_error "Invalid option"
                pause
                ;;
        esac
    done
}

# 2.1 Create Tenant Group
create_group() {
    clear_screen
    draw_header "Create Tenant Group"
    
    tenant_name=$(get_input "Enter tenant name")
    
    if [ -z "$tenant_name" ]; then
        show_error "Tenant name is required"
        pause
        return
    fi
    
    # Verify tenant exists
    show_info "Verifying tenant exists..."
    local tenant_path="/${tenant_name}"
    local tenant_id=$(find_group_by_path "$tenant_path")
    
    if [ -z "$tenant_id" ] || [ "$tenant_id" = "null" ]; then
        show_error "Tenant '${tenant_name}' not found"
        pause
        return
    fi
    
    # Prompt for group path
    echo ""
    echo "Enter the group path to create under /${tenant_name}"
    echo "Examples:"
    echo "  /dedicated          -> /${tenant_name}/dedicated"
    echo "  /non-prod/baas      -> /${tenant_name}/non-prod/baas"
    echo "  /prod/ml/inference  -> /${tenant_name}/prod/ml/inference"
    echo ""
    
    group_path=$(get_input "Enter group path (starting with /)")
    
    if [ -z "$group_path" ]; then
        show_error "Group path is required"
        pause
        return
    fi
    
    # Ensure path starts with /
    if [[ ! "$group_path" =~ ^/ ]]; then
        group_path="/${group_path}"
    fi
    
    # Remove trailing slash if present
    group_path="${group_path%/}"
    
    # Split the path into parts
    IFS='/' read -ra path_parts <<< "$group_path"
    
    # Filter out empty parts
    local parts=()
    for part in "${path_parts[@]}"; do
        if [ -n "$part" ]; then
            parts+=("$part")
        fi
    done
    
    if [ ${#parts[@]} -eq 0 ]; then
        show_error "Invalid group path"
        pause
        return
    fi
    
    show_info "Creating group hierarchy..."
    
    # Build the path incrementally
    local current_parent_id="$tenant_id"
    local current_path="/${tenant_name}"
    
    for part in "${parts[@]}"; do
        local next_path="${current_path}/${part}"
        
        # Check if this level already exists
        local existing_id=$(find_group_by_path "$next_path")
        
        if [ -n "$existing_id" ] && [ "$existing_id" != "null" ]; then
            show_info "Group '${next_path}' already exists"
            current_parent_id="$existing_id"
            current_path="$next_path"
        else
            # Create this level
            show_info "Creating '${next_path}'..."
            
            local group_payload=$(cat <<EOF
{
    "name": "${part}"
}
EOF
)
            
            local create_response=$(api_post "/admin/realms/${REALM}/groups/${current_parent_id}/children" "$group_payload")
            
            if [ $? -ne 0 ]; then
                show_error "Failed to create group '${next_path}'"
                pause
                return
            fi
            
            # Get the ID of the newly created group
            sleep 1  # Brief pause to ensure group is created and indexed
            local new_id=$(find_group_by_path "$next_path")
            
            if [ -z "$new_id" ] || [ "$new_id" = "null" ]; then
                show_error "Failed to retrieve group ID for '${next_path}'"
                pause
                return
            fi
            
            current_parent_id="$new_id"
            current_path="$next_path"
        fi
    done
    
    # Success
    echo ""
    show_success "Group created: ${current_path}"
    echo "  - Group ID: ${current_parent_id}"
    echo "  - Members: 0"
    echo ""
    
    pause
}

# 2.2 List Tenant Groups
list_groups() {
    clear_screen
    draw_header "List Tenant Groups"
    
    tenant_name=$(get_input "Enter tenant name (or leave empty for all)")
    
    local groups_json
    
    if [ -n "$tenant_name" ]; then
        show_info "Fetching groups for tenant: ${tenant_name}..."
        
        # Find tenant
        local tenant_path="/${tenant_name}"
        local tenant_id=$(find_group_by_path "$tenant_path")
        
        if [ -z "$tenant_id" ]; then
            show_error "Tenant '${tenant_name}' not found"
            pause
            return
        fi
        
        # Get children of this tenant
        groups_json=$(api_get "/admin/realms/${REALM}/groups/${tenant_id}/children")
    else
        show_info "Fetching all groups..."
        
        # Get all top-level groups (tenants)
        local all_groups=$(api_get "/admin/realms/${REALM}/groups")
        
        # Collect all subgroups from all tenants
        groups_json="[]"
        
        while IFS= read -r tenant_id; do
            if [ -n "$tenant_id" ] && [ "$tenant_id" != "null" ]; then
                local subgroups=$(api_get "/admin/realms/${REALM}/groups/${tenant_id}/children")
                if [ -n "$subgroups" ] && [ "$subgroups" != "null" ]; then
                    groups_json=$(echo "$groups_json" | jq --argjson new "$subgroups" '. + $new')
                fi
            fi
        done < <(echo "$all_groups" | jq -r '.[].id')
    fi
    
    if [ $? -ne 0 ] || [ -z "$groups_json" ]; then
        show_error "Failed to fetch groups"
        pause
        return
    fi
    
    local count=$(echo "$groups_json" | jq 'length')
    
    if [ "$count" -eq 0 ]; then
        echo ""
        show_info "No groups found"
        pause
        return
    fi
    
    # Display
    echo ""
    if [ -n "$tenant_name" ]; then
        echo "Tenant: ${tenant_name}"
    else
        echo "All Groups:"
    fi
    echo ""
    echo "┌────────────────────────────────────┬──────────────────────────────────────────┬──────────────────────────┬──────────┐"
    echo "│ Group Name                         │ Full Path                                │ Group ID                 │ Members  │"
    echo "├────────────────────────────────────┼──────────────────────────────────────────┼──────────────────────────┼──────────┤"
    
    echo "$groups_json" | jq -c '.[]' | while IFS= read -r group; do
        local name=$(echo "$group" | jq -r '.name')
        local path=$(echo "$group" | jq -r '.path')
        local id=$(echo "$group" | jq -r '.id')
        local id_short=$(truncate_id "$id")
        local members=$(get_group_member_count "$id")
        
        # Truncate path if too long
        local path_display=$(printf "%-40s" "$path" | cut -c1-40)
        
        printf "│ %-34s │ %-40s │ %-24s │ %-8s │\n" "$name" "$path_display" "$id_short" "$members"
    done
    
    echo "└────────────────────────────────────┴──────────────────────────────────────────┴──────────────────────────┴──────────┘"
    echo ""
    echo "Total groups: $count"
    
    pause
}

# 2.3 View Group Details
view_group_details() {
    clear_screen
    draw_header "View Group Details"
    
    group_path=$(get_input "Enter full group path (e.g., /acme-inc-2/acme-inc-2-dedicated)")
    
    if [ -z "$group_path" ]; then
        show_error "Group path is required"
        pause
        return
    fi
    
    show_info "Fetching group details..."
    
    # Find the group
    local group_id=$(find_group_by_path "$group_path")
    
    if [ -z "$group_id" ]; then
        show_error "Group '${group_path}' not found"
        pause
        return
    fi
    
    # Get group details
    local group_details=$(api_get "/admin/realms/${REALM}/groups/${group_id}")
    
    # Get members
    local members=$(api_get "/admin/realms/${REALM}/groups/${group_id}/members")
    
    # Extract details
    local name=$(echo "$group_details" | jq -r '.name')
    local path=$(echo "$group_details" | jq -r '.path')
    local parent_path=$(dirname "$path")
    local attributes=$(echo "$group_details" | jq -r '.attributes // {}')
    
    local member_count=$(echo "$members" | jq 'length')
    
    # Display
    echo ""
    echo "Group: ${path}"
    draw_separator
    echo "Group ID:     ${group_id}"
    echo "Group Name:   ${name}"
    echo "Parent:       ${parent_path}"
    echo ""
    echo "Members (${member_count}):"
    
    if [ "$member_count" -gt 0 ]; then
        echo "$members" | jq -r '.[] | "  • \(.username) (\(.firstName) \(.lastName))"'
    else
        echo "  (none)"
    fi
    
    echo ""
    echo "Attributes:"
    
    local attr_count=$(echo "$attributes" | jq 'length')
    if [ "$attr_count" -gt 0 ]; then
        echo "$attributes" | jq -r 'to_entries[] | "  • \(.key): \(.value[0])"'
    else
        echo "  (none)"
    fi
    
    pause
}

# 2.4 Update Group Attributes
update_group_attributes() {
    clear_screen
    draw_header "Update Group Attributes"
    
    group_path=$(get_input "Enter group path (e.g., /acme-inc/dedicated)")
    
    if [ -z "$group_path" ]; then
        show_error "Group path is required"
        pause
        return
    fi
    
    # Ensure path starts with /
    if [[ ! "$group_path" =~ ^/ ]]; then
        group_path="/${group_path}"
    fi
    
    # Find the group
    show_info "Fetching group details..."
    local group_id=$(find_group_by_path "$group_path")
    
    if [ -z "$group_id" ] || [ "$group_id" = "null" ]; then
        show_error "Group '${group_path}' not found"
        pause
        return
    fi
    
    # Get current group details
    local group_details=$(api_get "/admin/realms/${REALM}/groups/${group_id}")
    
    if [ $? -ne 0 ] || [ -z "$group_details" ]; then
        show_error "Failed to fetch group details"
        pause
        return
    fi
    
    # Extract current attributes
    local current_attrs=$(echo "$group_details" | jq -r '.attributes // {}')
    local current_description=$(echo "$current_attrs" | jq -r '.description[0] // ""')
    
    # Display current attributes
    echo ""
    echo "Current Attributes:"
    echo "─────────────────────"
    if [ -n "$current_description" ]; then
        echo "Description: ${current_description}"
    else
        echo "Description: (none)"
    fi
    
    # Show other custom attributes
    local other_attrs=$(echo "$current_attrs" | jq -r 'to_entries[] | select(.key != "description" and .key != "created_at") | "  \(.key): \(.value[0])"')
    if [ -n "$other_attrs" ]; then
        echo ""
        echo "Custom Attributes:"
        echo "$other_attrs"
    fi
    echo ""
    
    # Prompt for new description
    local new_description
    if [ -n "$current_description" ]; then
        new_description=$(get_input "Enter description (current: ${current_description})" "${current_description}")
    else
        new_description=$(get_input "Enter description" "Group: ${group_path}")
    fi
    
    # Build attributes object
    local attributes_json=$(echo "$current_attrs" | jq --arg desc "$new_description" '. + {description: [$desc]}')
    
    # Ask if user wants to add/update custom attributes
    echo ""
    echo -n "Add or update custom attribute? (y/n): " >&2
    read add_attr
    
    while [ "$add_attr" = "y" ] || [ "$add_attr" = "Y" ]; do
        local attr_key=$(get_input "Enter attribute key")
        if [ -z "$attr_key" ]; then
            show_error "Attribute key is required"
            continue
        fi
        
        local attr_value=$(get_input "Enter attribute value")
        if [ -z "$attr_value" ]; then
            show_error "Attribute value is required"
            continue
        fi
        
        # Add/update the attribute
        attributes_json=$(echo "$attributes_json" | jq --arg key "$attr_key" --arg val "$attr_value" '. + {($key): [$val]}')
        
        echo ""
        echo -n "Add another attribute? (y/n): " >&2
        read add_attr
    done
    
    # Build the update payload
    local group_name=$(echo "$group_details" | jq -r '.name')
    local update_payload=$(jq -n \
        --arg name "$group_name" \
        --argjson attrs "$attributes_json" \
        '{name: $name, attributes: $attrs}')
    
    show_info "Updating group attributes..."
    
    # Update the group
    local update_response=$(api_put "/admin/realms/${REALM}/groups/${group_id}" "$update_payload")
    
    if [ $? -ne 0 ]; then
        show_error "Failed to update group attributes"
        pause
        return
    fi
    
    # Success
    echo ""
    show_success "Group '${group_path}' updated successfully"
    echo ""
    
    pause
}

# 2.5 Delete Tenant Group
delete_group() {
    clear_screen
    draw_header "Delete Tenant Group"
    
    group_path=$(get_input "Enter group path (e.g., /acme-inc/dedicated)")
    
    if [ -z "$group_path" ]; then
        show_error "Group path is required"
        pause
        return
    fi
    
    # Ensure path starts with /
    if [[ ! "$group_path" =~ ^/ ]]; then
        group_path="/${group_path}"
    fi
    
    # Find the group
    show_info "Fetching group details..."
    local group_id=$(find_group_by_path "$group_path")
    
    if [ -z "$group_id" ] || [ "$group_id" = "null" ]; then
        show_error "Group '${group_path}' not found"
        pause
        return
    fi
    
    # Get group details and members
    local group_details=$(api_get "/admin/realms/${REALM}/groups/${group_id}")
    local subgroups=$(echo "$group_details" | jq -r '.subGroups // []')
    local subgroup_count=$(echo "$subgroups" | jq 'length')
    local members=$(api_get "/admin/realms/${REALM}/groups/${group_id}/members")
    local member_count=$(echo "$members" | jq 'length')
    
    # Display warning and confirm
    echo ""
    show_warning "WARNING: This action will:"
    echo "  • Remove ALL user memberships from this group (${member_count} members)"
    if [ "$subgroup_count" -gt 0 ]; then
        echo "  • Delete ALL subgroups recursively (${subgroup_count} subgroups)"
    fi
    echo "  • Permanently delete the group"
    echo ""
    
    local group_name=$(basename "$group_path")
    if ! confirm_action "Are you sure you want to delete '${group_path}'?" "${group_name}"; then
        pause
        return
    fi
    
    # Delete the group
    show_info "Deleting group '${group_path}'..."
    local delete_response=$(api_delete "/admin/realms/${REALM}/groups/${group_id}")
    
    if [ $? -ne 0 ]; then
        show_error "Failed to delete group"
        pause
        return
    fi
    
    # Success
    echo ""
    show_success "Group '${group_path}' deleted successfully"
    echo "  • ${member_count} user memberships removed"
    if [ "$subgroup_count" -gt 0 ]; then
        echo "  • ${subgroup_count} subgroups deleted"
    fi
    
    pause
}

#############################################################################
# Menu 3: Manage Tenant Users
#############################################################################

show_users_menu() {
    clear_screen
    draw_header "Manage Tenant Users"
    echo "  1. Create User"
    echo "  2. List Users"
    echo "  3. View User by Email"
    echo "  4. View User by Username"
    echo "  5. Update User"
    echo "  6. Delete User"
    echo "  7. Add User to Group"
    echo "  8. Remove User from Group"
    echo ""
    echo "  0. Back to Main Menu"
    echo ""
    echo -n "Select option: "
}

manage_users_menu() {
    while true; do
        show_users_menu
        read choice
        
        case $choice in
            1) create_user ;;
            2) list_users ;;
            3) view_user_by_email ;;
            4) view_user_by_username ;;
            5) update_user ;;
            6) delete_user ;;
            7) add_user_to_group ;;
            8) remove_user_from_group ;;
            0) return ;;
            *)
                show_error "Invalid option"
                pause
                ;;
        esac
    done
}

# 3.1 Create User
create_user() {
    clear_screen
    draw_header "Create User"
    
    # Prompt for tenant first
    tenant_name=$(get_input "Enter tenant name")
    
    if [ -z "$tenant_name" ]; then
        show_error "Tenant name is required"
        pause
        return
    fi
    
    # Verify tenant exists
    show_info "Verifying tenant exists..."
    local tenant_path="/${tenant_name}"
    local tenant_id=$(find_group_by_path "$tenant_path")
    
    if [ -z "$tenant_id" ] || [ "$tenant_id" = "null" ]; then
        show_error "Tenant '${tenant_name}' not found"
        pause
        return
    fi
    
    echo ""
    
    # Collect user details
    email=$(get_input "Enter email (will be username)")
    
    if [ -z "$email" ]; then
        show_error "Email is required"
        pause
        return
    fi
    
    first_name=$(get_input "Enter first name")
    last_name=$(get_input "Enter last name")
    password=$(get_input "Enter password")
    
    if [ -z "$password" ]; then
        show_error "Password is required"
        pause
        return
    fi
    
    echo -n "Email verified? (y/n) [y]: " >&2
    read email_verified
    email_verified=${email_verified:-y}
    
    echo -n "Enabled? (y/n) [y]: " >&2
    read enabled
    enabled=${enabled:-y}
    
    # Convert y/n to boolean
    local email_verified_bool="true"
    [ "$email_verified" != "y" ] && [ "$email_verified" != "Y" ] && email_verified_bool="false"
    
    local enabled_bool="true"
    [ "$enabled" != "y" ] && [ "$enabled" != "Y" ] && enabled_bool="false"
    
    show_info "Creating user..."
    
    # Create user payload
    local user_payload=$(jq -n \
        --arg username "$email" \
        --arg email "$email" \
        --arg firstName "$first_name" \
        --arg lastName "$last_name" \
        --argjson emailVerified "$email_verified_bool" \
        --argjson enabled "$enabled_bool" \
        '{
            username: $username,
            email: $email,
            firstName: $firstName,
            lastName: $lastName,
            emailVerified: $emailVerified,
            enabled: $enabled
        }')
    
    # Create the user
    local create_response=$(api_post "/admin/realms/${REALM}/users" "$user_payload")
    
    if [ $? -ne 0 ]; then
        show_error "Failed to create user"
        echo "$create_response" >&2
        pause
        return
    fi
    
    # Find the newly created user
    sleep 1
    show_info "Retrieving user ID..."
    local user_id=$(find_user_by_email "$email")
    
    if [ -z "$user_id" ] || [ "$user_id" = "null" ]; then
        show_error "Failed to retrieve user ID"
        pause
        return
    fi
    
    # Set password
    show_info "Setting password..."
    local password_payload=$(jq -n \
        --arg password "$password" \
        '{
            type: "password",
            value: $password,
            temporary: false
        }')
    
    local password_response=$(api_put "/admin/realms/${REALM}/users/${user_id}/reset-password" "$password_payload")
    
    if [ $? -ne 0 ]; then
        show_error "User created but failed to set password"
        pause
        return
    fi
    
    # Add user to tenant group
    show_info "Adding user to tenant '${tenant_name}'..."
    local group_response=$(api_put "/admin/realms/${REALM}/users/${user_id}/groups/${tenant_id}" "")
    
    if [ $? -ne 0 ]; then
        show_error "User created but failed to add to tenant group"
        pause
        return
    fi
    
    # Success
    echo ""
    show_success "User created: ${email}"
    echo "  - User ID: ${user_id}"
    echo "  - Status: $([ "$enabled_bool" = "true" ] && echo "Enabled" || echo "Disabled")"
    echo "  - Email Verified: $([ "$email_verified_bool" = "true" ] && echo "Yes" || echo "No")"
    echo "  - Added to tenant: ${tenant_name}"
    echo ""
    
    echo -n "Add to additional groups now? (y/n): " >&2
    read add_groups
    
    if [ "$add_groups" = "y" ] || [ "$add_groups" = "Y" ]; then
        # Store email for next operation
        LAST_USER_EMAIL="$email"
        add_user_to_group
    else
        pause
    fi
}

# 3.2 List Users
list_users() {
    clear_screen
    draw_header "List Users"
    
    echo "Filter by:"
    echo "  1. All users"
    echo "  2. Users in specific tenant"
    echo "  3. Users in specific group"
    echo "  4. Search by email"
    echo "  5. Search by username"
    echo ""
    echo "  0. Cancel"
    echo ""
    echo -n "Enter choice: "
    read filter_choice
    
    local users_json
    
    case $filter_choice in
        0)
            return
            ;;
        1)
            show_info "Fetching all users..."
            users_json=$(api_get "/admin/realms/${REALM}/users?max=100")
            ;;
        2)
            tenant_name=$(get_input "Enter tenant name")
            show_info "Fetching users in tenant: ${tenant_name}..."
            
            # Find tenant group
            local tenant_path="/${tenant_name}"
            local tenant_id=$(find_group_by_path "$tenant_path")
            
            if [ -z "$tenant_id" ]; then
                show_error "Tenant '${tenant_name}' not found"
                pause
                return
            fi
            
            # Get all members of tenant and subgroups
            users_json=$(api_get "/admin/realms/${REALM}/groups/${tenant_id}/members?max=100")
            ;;
        3)
            group_path=$(get_input "Enter group path")
            show_info "Fetching group members: ${group_path}..."
            
            local group_id=$(find_group_by_path "$group_path")
            
            if [ -z "$group_id" ]; then
                show_error "Group '${group_path}' not found"
                pause
                return
            fi
            
            users_json=$(api_get "/admin/realms/${REALM}/groups/${group_id}/members?max=100")
            ;;
        4)
            email=$(get_input "Enter email")
            show_info "Searching by email: ${email}..."
            
            # URL encode the email
            local encoded_email=$(printf '%s' "$email" | jq -sRr @uri)
            users_json=$(api_get "/admin/realms/${REALM}/users?email=${encoded_email}&max=100")
            ;;
        5)
            username=$(get_input "Enter username")
            show_info "Searching by username: ${username}..."
            
            # URL encode the username
            local encoded_username=$(printf '%s' "$username" | jq -sRr @uri)
            users_json=$(api_get "/admin/realms/${REALM}/users?username=${encoded_username}&max=100")
            ;;
        *)
            show_error "Invalid choice"
            pause
            return
            ;;
    esac
    
    if [ $? -ne 0 ] || [ -z "$users_json" ]; then
        show_error "Failed to fetch users"
        pause
        return
    fi
    
    local count=$(echo "$users_json" | jq 'length')
    
    if [ "$count" -eq 0 ]; then
        echo ""
        show_info "No users found"
        pause
        return
    fi
    
    # Display
    echo ""
    echo "Users (${count} found):"
    echo ""
    echo "┌────────────────────────────────┬────────────────────────────────┬──────────────────────┬─────────┬────────┐"
    echo "│ Email                          │ Username                       │ Name                 │ Groups  │ Status │"
    echo "├────────────────────────────────┼────────────────────────────────┼──────────────────────┼─────────┼────────┤"
    
    echo "$users_json" | jq -c '.[]' | while IFS= read -r user; do
        local email=$(echo "$user" | jq -r '.email // ""')
        local username=$(echo "$user" | jq -r '.username // ""')
        local first=$(echo "$user" | jq -r '.firstName // ""')
        local last=$(echo "$user" | jq -r '.lastName // ""')
        local name="${first} ${last}"
        local enabled=$(echo "$user" | jq -r '.enabled')
        local user_id=$(echo "$user" | jq -r '.id')
        
        # Get user's groups
        local user_groups=$(api_get "/admin/realms/${REALM}/users/${user_id}/groups")
        local group_count=$(echo "$user_groups" | jq 'length')
        
        local status_icon="✗"
        [ "$enabled" = "true" ] && status_icon="✓"
        
        # Truncate fields if needed
        email=$(printf "%-30s" "$email" | cut -c1-30)
        username=$(printf "%-30s" "$username" | cut -c1-30)
        name=$(printf "%-20s" "$name" | cut -c1-20)
        
        printf "│ %-30s │ %-30s │ %-20s │ %-7s │ %-6s │\n" "$email" "$username" "$name" "$group_count" "$status_icon"
    done
    
    echo "└────────────────────────────────┴────────────────────────────────┴──────────────────────┴─────────┴────────┘"
    echo ""
    echo "Total users: $count"
    
    pause
}

# 3.3 View User by Email
view_user_by_email() {
    clear_screen
    draw_header "View User by Email"
    
    email=$(get_input "Enter user email" "${LAST_USER_EMAIL}")
    
    if [ -z "$email" ]; then
        show_error "User email is required"
        pause
        return
    fi
    
    LAST_USER_EMAIL="$email"
    
    show_info "Searching for user by email..."
    
    # Find user by email
    local user_id=$(find_user_by_email "$email")
    
    if [ -z "$user_id" ] || [ "$user_id" = "null" ]; then
        show_error "User with email '${email}' not found"
        pause
        return
    fi
    
    # Get user details
    local user_details=$(api_get "/admin/realms/${REALM}/users/${user_id}")
    
    # Get user's groups
    local user_groups=$(api_get "/admin/realms/${REALM}/users/${user_id}/groups")
    
    # Extract details
    local username=$(echo "$user_details" | jq -r '.username')
    local first_name=$(echo "$user_details" | jq -r '.firstName // "N/A"')
    local last_name=$(echo "$user_details" | jq -r '.lastName // "N/A"')
    local user_email=$(echo "$user_details" | jq -r '.email // "N/A"')
    local email_verified=$(echo "$user_details" | jq -r '.emailVerified')
    local enabled=$(echo "$user_details" | jq -r '.enabled')
    local created=$(echo "$user_details" | jq -r '.createdTimestamp')
    local attributes=$(echo "$user_details" | jq -r '.attributes // {}')
    
    local group_count=$(echo "$user_groups" | jq 'length')
    
    # Format display values
    local email_icon="✗"
    [ "$email_verified" = "true" ] && email_icon="✓"
    
    local enabled_icon="✗"
    [ "$enabled" = "true" ] && enabled_icon="✓"
    
    local created_date=$(format_date "$created")
    
    # Display
    echo ""
    echo "User: ${email}"
    draw_separator
    echo "User ID:       ${user_id}"
    echo "Username:      ${username}"
    echo "First Name:    ${first_name}"
    echo "Last Name:     ${last_name}"
    echo "Email:         ${user_email}"
    echo "Email Verified: ${email_icon}"
    echo "Enabled:       ${enabled_icon}"
    echo "Created:       ${created_date}"
    echo ""
    echo "Groups (${group_count}):"
    
    if [ "$group_count" -gt 0 ]; then
        echo "$user_groups" | jq -r '.[] | "  • \(.path)"'
    else
        echo "  (none)"
    fi
    
    echo ""
    echo "Attributes:"
    
    local attr_count=$(echo "$attributes" | jq 'length')
    if [ "$attr_count" -gt 0 ]; then
        echo "$attributes" | jq -r 'to_entries[] | "  • \(.key): \(.value[0])"'
    else
        echo "  (none)"
    fi
    
    echo ""
    pause
}

# 3.4 View User by Username
view_user_by_username() {
    clear_screen
    draw_header "View User by Username"
    
    username=$(get_input "Enter username" "${LAST_USERNAME}")
    
    if [ -z "$username" ]; then
        show_error "Username is required"
        pause
        return
    fi
    
    LAST_USERNAME="$username"
    
    show_info "Searching for user by username..."
    
    # Find user by username - using exact match
    local encoded_username=$(printf '%s' "$username" | jq -s -R -r @uri)
    local search_result=$(api_get "/admin/realms/${REALM}/users?username=${encoded_username}&exact=true")
    
    local user_count=$(echo "$search_result" | jq 'length')
    
    if [ "$user_count" -eq 0 ]; then
        show_error "User with username '${username}' not found"
        pause
        return
    elif [ "$user_count" -gt 1 ]; then
        show_error "Multiple users found with username '${username}'"
        pause
        return
    fi
    
    local user_id=$(echo "$search_result" | jq -r '.[0].id')
    
    # Get user details
    local user_details=$(api_get "/admin/realms/${REALM}/users/${user_id}")
    
    # Get user's groups
    local user_groups=$(api_get "/admin/realms/${REALM}/users/${user_id}/groups")
    
    # Extract details
    local username=$(echo "$user_details" | jq -r '.username')
    local first_name=$(echo "$user_details" | jq -r '.firstName // "N/A"')
    local last_name=$(echo "$user_details" | jq -r '.lastName // "N/A"')
    local user_email=$(echo "$user_details" | jq -r '.email // "N/A"')
    local email_verified=$(echo "$user_details" | jq -r '.emailVerified')
    local enabled=$(echo "$user_details" | jq -r '.enabled')
    local created=$(echo "$user_details" | jq -r '.createdTimestamp')
    local attributes=$(echo "$user_details" | jq -r '.attributes // {}')
    
    local group_count=$(echo "$user_groups" | jq 'length')
    
    # Format display values
    local email_icon="✗"
    [ "$email_verified" = "true" ] && email_icon="✓"
    
    local enabled_icon="✗"
    [ "$enabled" = "true" ] && enabled_icon="✓"
    
    local created_date=$(format_date "$created")
    
    # Display
    echo ""
    echo "User: ${username}"
    draw_separator
    echo "User ID:       ${user_id}"
    echo "Username:      ${username}"
    echo "First Name:    ${first_name}"
    echo "Last Name:     ${last_name}"
    echo "Email:         ${user_email}"
    echo "Email Verified: ${email_icon}"
    echo "Enabled:       ${enabled_icon}"
    echo "Created:       ${created_date}"
    echo ""
    echo "Groups (${group_count}):"
    
    if [ "$group_count" -gt 0 ]; then
        echo "$user_groups" | jq -r '.[] | "  • \(.path)"'
    else
        echo "  (none)"
    fi
    
    echo ""
    echo "Attributes:"
    
    local attr_count=$(echo "$attributes" | jq 'length')
    if [ "$attr_count" -gt 0 ]; then
        echo "$attributes" | jq -r 'to_entries[] | "  • \(.key): \(.value[0])"'
    else
        echo "  (none)"
    fi
    
    echo ""
    pause
}

# 3.5 Update User
update_user() {
    clear_screen
    draw_header "Update User"
    
    email=$(get_input "Enter user ID, email, or username" "${LAST_USER_EMAIL}")
    
    if [ -z "$email" ]; then
        show_error "Email is required"
        pause
        return
    fi
    
    LAST_USER_EMAIL="$email"
    
    # Find the user
    show_info "Finding user..."
    local user_id=$(find_user_by_email "$email")
    
    if [ -z "$user_id" ] || [ "$user_id" = "null" ]; then
        show_error "User '${email}' not found"
        pause
        return
    fi
    
    # Get current user details
    local user_details=$(api_get "/admin/realms/${REALM}/users/${user_id}")
    
    if [ $? -ne 0 ] || [ -z "$user_details" ]; then
        show_error "Failed to fetch user details"
        pause
        return
    fi
    
    echo ""
    echo "Update options:"
    echo "  1. Update user"
    echo "  2. Enable/Disable"
    echo "  0. Return"
    echo ""
    echo -n "Select option: "
    read update_choice
    
    case $update_choice in
        1)
            # Update user - prompt for all fields except username and email
            local username=$(echo "$user_details" | jq -r '.username')
            local user_email=$(echo "$user_details" | jq -r '.email')
            local current_first=$(echo "$user_details" | jq -r '.firstName // ""')
            local current_last=$(echo "$user_details" | jq -r '.lastName // ""')
            
            echo ""
            echo "Username: ${username} (cannot be changed)"
            echo "Email: ${user_email} (cannot be changed)"
            echo ""
            
            # Prompt for first and last name
            echo "Current name: ${current_first} ${current_last}"
            first_name=$(get_input "Enter first name" "${current_first}")
            last_name=$(get_input "Enter last name" "${current_last}")
            
            # Ask if they want to update password
            echo ""
            echo -n "Update password? (y/n) [n]: " >&2
            read update_pwd
            update_pwd=${update_pwd:-n}
            
            local new_password=""
            local temporary_bool="false"
            if [ "$update_pwd" = "y" ] || [ "$update_pwd" = "Y" ]; then
                new_password=$(get_input "Enter new password")
                
                if [ -n "$new_password" ]; then
                    echo -n "Set as temporary (require password change on login)? (y/n) [n]: " >&2
                    read is_temp
                    is_temp=${is_temp:-n}
                    
                    [ "$is_temp" = "y" ] || [ "$is_temp" = "Y" ] && temporary_bool="true"
                fi
            fi
            
            # Update user details
            show_info "Updating user..."
            local update_payload=$(jq -n \
                --arg username "$username" \
                --arg email "$user_email" \
                --arg firstName "$first_name" \
                --arg lastName "$last_name" \
                '{username: $username, email: $email, firstName: $firstName, lastName: $lastName}')
            
            local response=$(api_put "/admin/realms/${REALM}/users/${user_id}" "$update_payload")
            if [ $? -ne 0 ]; then
                show_error "Failed to update user"
                pause
                return
            fi
            
            # Update password if provided
            if [ -n "$new_password" ]; then
                show_info "Updating password..."
                local password_payload=$(jq -n \
                    --arg password "$new_password" \
                    --argjson temporary "$temporary_bool" \
                    '{type: "password", value: $password, temporary: $temporary}')
                
                local pwd_response=$(api_put "/admin/realms/${REALM}/users/${user_id}/reset-password" "$password_payload")
                if [ $? -ne 0 ]; then
                    show_error "User updated but failed to set password"
                fi
            fi
            ;;
        2)
            # Enable/Disable user
            local current_enabled=$(echo "$user_details" | jq -r '.enabled')
            local current_status="Disabled"
            [ "$current_enabled" = "true" ] && current_status="Enabled"
            
            echo ""
            echo "Current status: ${current_status}"
            echo -n "Enable user? (y/n): " >&2
            read enable_user
            
            local enabled_bool="false"
            [ "$enable_user" = "y" ] || [ "$enable_user" = "Y" ] && enabled_bool="true"
            
            show_info "Updating user status..."
            local username=$(echo "$user_details" | jq -r '.username')
            local user_email=$(echo "$user_details" | jq -r '.email')
            
            local update_payload=$(jq -n \
                --arg username "$username" \
                --arg email "$user_email" \
                --argjson enabled "$enabled_bool" \
                '{username: $username, email: $email, enabled: $enabled}')
            
            local response=$(api_put "/admin/realms/${REALM}/users/${user_id}" "$update_payload")
            if [ $? -ne 0 ]; then
                show_error "Failed to update user status"
                pause
                return
            fi
            
            local new_status="Disabled"
            [ "$enabled_bool" = "true" ] && new_status="Enabled"
            echo ""
            show_success "User status changed: ${current_status} → ${new_status}"
            ;;
        0)
            return
            ;;
        *)
            show_error "Invalid option"
            pause
            return
            ;;
    esac
    
    # Success
    echo ""
    show_success "User '${email}' updated successfully"
    
    pause
}

# 3.6 Delete User
delete_user() {
    clear_screen
    draw_header "Delete User"
    
    email=$(get_input "Enter user email or username" "${LAST_USER_EMAIL}")
    
    if [ -z "$email" ]; then
        show_error "Email/username is required"
        pause
        return
    fi
    
    # Find the user
    show_info "Finding user..."
    local user_id=$(find_user_by_email "$email")
    
    if [ -z "$user_id" ] || [ "$user_id" = "null" ]; then
        show_error "User '${email}' not found"
        pause
        return
    fi
    
    # Get user details and groups
    local user_details=$(api_get "/admin/realms/${REALM}/users/${user_id}")
    local user_groups=$(api_get "/admin/realms/${REALM}/users/${user_id}/groups")
    local group_count=$(echo "$user_groups" | jq 'length')
    
    local username=$(echo "$user_details" | jq -r '.username')
    local user_email=$(echo "$user_details" | jq -r '.email')
    
    # Display warning
    echo ""
    show_warning "WARNING: This will permanently delete the user:"
    echo "  • Username: ${username}"
    echo "  • Email: ${user_email}"
    echo "  • Will be removed from ${group_count} group(s)"
    echo ""
    
    # Confirm action
    if ! confirm_action "Are you sure you want to delete user '${email}'?" "${username}"; then
        pause
        return
    fi
    
    # Delete the user
    show_info "Deleting user..."
    local delete_response=$(api_delete "/admin/realms/${REALM}/users/${user_id}")
    
    if [ $? -ne 0 ]; then
        show_error "Failed to delete user"
        pause
        return
    fi
    
    # Success
    echo ""
    show_success "User '${email}' deleted successfully"
    echo "  • Removed from ${group_count} group(s)"
    echo ""
    
    LAST_USER_EMAIL=""
    
    pause
}

# 3.7 Add User to Group
add_user_to_group() {
    clear_screen
    draw_header "Add User to Group"
    
    email=$(get_input "Enter user email or username" "${LAST_USER_EMAIL}")
    
    if [ -z "$email" ]; then
        show_error "Email/username is required"
        pause
        return
    fi
    
    LAST_USER_EMAIL="$email"
    
    # Find the user
    show_info "Finding user..."
    local user_id=$(find_user_by_email "$email")
    
    if [ -z "$user_id" ] || [ "$user_id" = "null" ]; then
        show_error "User '${email}' not found"
        pause
        return
    fi
    
    # Get user's current groups
    local user_groups=$(api_get "/admin/realms/${REALM}/users/${user_id}/groups")
    local group_count=$(echo "$user_groups" | jq 'length')
    
    echo ""
    echo "Current groups (${group_count}):"
    if [ "$group_count" -gt 0 ]; then
        echo "$user_groups" | jq -r '.[] | "  • \(.path)"'
    else
        echo "  (none)"
    fi
    echo ""
    
    # Prompt for full group path
    local full_group_path=$(get_input "Enter full group path (e.g., /acme-inc/dedicated)")
    
    if [ -z "$full_group_path" ]; then
        show_error "Group path is required"
        pause
        return
    fi
    
    # Ensure path starts with /
    if [[ ! "$full_group_path" =~ ^/ ]]; then
        full_group_path="/${full_group_path}"
    fi
    
    # Find the group
    show_info "Finding group..."
    local group_id=$(find_group_by_path "$full_group_path")
    
    if [ -z "$group_id" ] || [ "$group_id" = "null" ]; then
        show_error "Group '${full_group_path}' not found"
        pause
        return
    fi
    
    # Check if user is already in the group
    local is_member=$(echo "$user_groups" | jq -r --arg path "$full_group_path" '.[] | select(.path == $path) | .id')
    if [ -n "$is_member" ]; then
        show_error "User is already a member of '${full_group_path}'"
        pause
        return
    fi
    
    # Add user to group
    show_info "Adding user to group..."
    local add_response=$(api_put "/admin/realms/${REALM}/users/${user_id}/groups/${group_id}" "")
    
    if [ $? -ne 0 ]; then
        show_error "Failed to add user to group"
        pause
        return
    fi
    
    # Success
    echo ""
    show_success "Added '${email}' to '${full_group_path}'"
    echo ""
    
    echo -n "Add to another group? (y/n): " >&2
    read add_another
    
    if [ "$add_another" = "y" ] || [ "$add_another" = "Y" ]; then
        add_user_to_group
    else
        pause
    fi
}

# 3.8 Remove User from Group
remove_user_from_group() {
    clear_screen
    draw_header "Remove User from Group"
    
    email=$(get_input "Enter user email or username" "${LAST_USER_EMAIL}")
    
    if [ -z "$email" ]; then
        show_error "Email/username is required"
        pause
        return
    fi
    
    LAST_USER_EMAIL="$email"
    
    # Find the user
    show_info "Finding user..."
    local user_id=$(find_user_by_email "$email")
    
    if [ -z "$user_id" ] || [ "$user_id" = "null" ]; then
        show_error "User '${email}' not found"
        pause
        return
    fi
    
    # Get user's current groups
    local user_groups=$(api_get "/admin/realms/${REALM}/users/${user_id}/groups")
    local group_count=$(echo "$user_groups" | jq 'length')
    
    echo ""
    echo "Current groups (${group_count}):"
    if [ "$group_count" -gt 0 ]; then
        echo "$user_groups" | jq -r '.[] | "  • \(.path)"'
    else
        echo "  (none)"
        echo ""
        show_info "User is not a member of any groups"
        pause
        return
    fi
    echo ""
    
    # Prompt for full group path
    local full_group_path=$(get_input "Enter full group path (e.g., /red-hat/red-hat-dedicated)")
    
    if [ -z "$full_group_path" ]; then
        show_error "Group path is required"
        pause
        return
    fi
    
    # Ensure path starts with /
    if [[ ! "$full_group_path" =~ ^/ ]]; then
        full_group_path="/${full_group_path}"
    fi
    
    # Find the group
    show_info "Finding group..."
    local group_id=$(find_group_by_path "$full_group_path")
    
    if [ -z "$group_id" ] || [ "$group_id" = "null" ]; then
        show_error "Group '${full_group_path}' not found"
        pause
        return
    fi
    
    # Check if user is actually in the group
    local is_member=$(echo "$user_groups" | jq -r --arg path "$full_group_path" '.[] | select(.path == $path) | .id')
    if [ -z "$is_member" ]; then
        show_error "User is not a member of '${full_group_path}'"
        pause
        return
    fi
    
    # Remove user from group
    show_info "Removing user from group..."
    local remove_response=$(api_delete "/admin/realms/${REALM}/users/${user_id}/groups/${group_id}")
    
    if [ $? -ne 0 ]; then
        show_error "Failed to remove user from group"
        pause
        return
    fi
    
    # Success
    echo ""
    show_success "Removed '${email}' from '${full_group_path}'"
    echo ""
    
    echo -n "Remove from another group? (y/n): " >&2
    read remove_another
    
    if [ "$remove_another" = "y" ] || [ "$remove_another" = "Y" ]; then
        remove_user_from_group
    else
        pause
    fi
}

#############################################################################
# Main Entry Point
#############################################################################

# Check if client secret is set
if [ -z "$CLIENT_SECRET" ]; then
    show_error "KEYCLOAK_ADMIN_SECRET environment variable is not set"
    echo ""
    echo "Please set it with:"
    echo "  export KEYCLOAK_ADMIN_SECRET='your-client-secret'"
    exit 1
fi

# Start main menu
main_menu

