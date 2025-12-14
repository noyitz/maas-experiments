#!/bin/bash

# Test script for Tier-to-Group Admin API
# Tests all CRUD operations and displays results
#
# Usage:
#   ./test-api.sh [BASE_URL]
#   ./test-api.sh https://tier-to-group-admin-maas-dev.apps.sno.bakerapps.net
#   BASE_URL=https://example.com ./test-api.sh

# Get base URL from command line argument or environment variable, default to localhost
if [ -n "$1" ]; then
    BASE_URL="$1"
elif [ -n "$BASE_URL" ]; then
    BASE_URL="$BASE_URL"
else
    BASE_URL="http://localhost:8080"
fi

# Remove trailing slash if present
BASE_URL="${BASE_URL%/}"

API_BASE="${BASE_URL}/api/v1"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test counters
PASSED=0
FAILED=0
TOTAL=0

# Function to print test header
print_header() {
    echo -e "\n${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}\n"
}

# Function to run a test and check result
run_test() {
    local test_name="$1"
    local expected_status="$2"
    local method="$3"
    local endpoint="$4"
    local data="$5"
    
    TOTAL=$((TOTAL + 1))
    
    echo -n "Testing: $test_name ... "
    
    if [ -n "$data" ]; then
        response=$(curl -s -k -w "\n%{http_code}" -X "$method" \
            -H "Content-Type: application/json" \
            -d "$data" \
            "${API_BASE}${endpoint}")
    else
        response=$(curl -s -k -w "\n%{http_code}" -X "$method" \
            "${API_BASE}${endpoint}")
    fi
    
    http_code=$(echo "$response" | tail -n1)
    body=$(echo "$response" | sed '$d')
    
    if [ "$http_code" -eq "$expected_status" ]; then
        echo -e "${GREEN}PASS${NC} (HTTP $http_code)"
        PASSED=$((PASSED + 1))
        if [ -n "$body" ] && [ "$body" != "null" ]; then
            echo "  Response: $body" | head -c 200
            echo ""
        fi
        return 0
    else
        echo -e "${RED}FAIL${NC} (Expected HTTP $expected_status, got HTTP $http_code)"
        FAILED=$((FAILED + 1))
        echo "  Response: $body"
        return 1
    fi
}

# Check if server is running
echo -e "${YELLOW}Testing API at: ${BASE_URL}${NC}"
echo -e "${YELLOW}API Base URL: ${API_BASE}${NC}\n"

if ! curl -s -f -k "${BASE_URL}/health" > /dev/null 2>&1; then
    echo -e "${RED}Error: Server is not accessible at $BASE_URL${NC}"
    echo "Please check:"
    echo "  - The server is running"
    echo "  - The URL is correct"
    echo "  - Network connectivity"
    echo ""
    echo "Usage:"
    echo "  ./test-api.sh [BASE_URL]"
    echo "  ./test-api.sh https://tier-to-group-admin-maas-dev.apps.sno.bakerapps.net"
    echo "  BASE_URL=https://example.com ./test-api.sh"
    exit 1
fi
echo -e "${GREEN}Server is accessible!${NC}\n"

# ============================================
# TEST 1: CREATE TIERS
# ============================================
print_header "TEST 1: Create Tiers"

run_test "Create acme-inc-1 tier" 201 POST "/tiers" \
    '{"name":"acme-inc-1","description":"Acme Inc Tier 1","level":1,"groups":["system:authenticated"]}'

run_test "Create acme-inc-2 tier" 201 POST "/tiers" \
    '{"name":"acme-inc-2","description":"Acme Inc Tier 2","level":5,"groups":["premium-users"]}'

run_test "Create acme-inc-3 tier" 201 POST "/tiers" \
    '{"name":"acme-inc-3","description":"Acme Inc Tier 3","level":10,"groups":["enterprise-users","vip-users"]}'

# Test duplicate tier creation (should fail)
run_test "Try to create duplicate tier (acme-inc-1)" 409 POST "/tiers" \
    '{"name":"acme-inc-1","description":"Duplicate","level":1,"groups":[]}'

# Test invalid tier (empty name)
run_test "Try to create tier with empty name" 400 POST "/tiers" \
    '{"name":"","description":"Invalid","level":1,"groups":[]}'

# Test invalid tier (missing description)
run_test "Try to create tier without description" 400 POST "/tiers" \
    '{"name":"invalid-tier","level":1,"groups":[]}'

# Test invalid tier (negative level)
run_test "Try to create tier with negative level" 400 POST "/tiers" \
    '{"name":"invalid-level","description":"Test","level":-1,"groups":[]}'

# Test invalid group name (uppercase)
run_test "Try to create tier with invalid group name (uppercase)" 400 POST "/tiers" \
    '{"name":"invalid-group","description":"Test","level":1,"groups":["InvalidGroup"]}'

# Test invalid group name (starts with hyphen)
run_test "Try to create tier with invalid group name (starts with -)" 400 POST "/tiers" \
    '{"name":"invalid-group2","description":"Test","level":1,"groups":["-invalid"]}'

# ============================================
# TEST 2: LIST ALL TIERS
# ============================================
print_header "TEST 2: List All Tiers"

run_test "Get all tiers" 200 GET "/tiers" ""

# ============================================
# TEST 3: GET SPECIFIC TIER
# ============================================
print_header "TEST 3: Get Specific Tier"

run_test "Get acme-inc-1 tier" 200 GET "/tiers/acme-inc-1" ""

run_test "Get acme-inc-2 tier" 200 GET "/tiers/acme-inc-2" ""

run_test "Get acme-inc-3 tier" 200 GET "/tiers/acme-inc-3" ""

# Test getting non-existent tier
run_test "Get non-existent tier" 404 GET "/tiers/non-existent" ""

# ============================================
# TEST 4: UPDATE TIERS
# ============================================
print_header "TEST 4: Update Tiers"

# Update description and level
run_test "Update acme-inc-1 description and level" 200 PUT "/tiers/acme-inc-1" \
    '{"description":"Updated Acme Inc Tier 1","level":2}'

# Update groups
run_test "Update acme-inc-2 groups" 200 PUT "/tiers/acme-inc-2" \
    '{"description":"Acme Inc Tier 2","level":5,"groups":["premium-users","trial-users"]}'

# Try to update tier name (should fail)
run_test "Try to update tier name (immutable)" 400 PUT "/tiers/acme-inc-1" \
    '{"name":"new-name","description":"Test","level":1}'

# Update non-existent tier
run_test "Update non-existent tier" 404 PUT "/tiers/non-existent" \
    '{"description":"Test","level":1}'

# ============================================
# TEST 5: ADD GROUPS TO TIERS
# ============================================
print_header "TEST 5: Add Groups to Tiers"

run_test "Add group to acme-inc-1" 200 POST "/tiers/acme-inc-1/groups" \
    '{"group":"free-users"}'

run_test "Add group to acme-inc-2" 200 POST "/tiers/acme-inc-2/groups" \
    '{"group":"beta-users"}'

run_test "Add group to acme-inc-3" 200 POST "/tiers/acme-inc-3/groups" \
    '{"group":"alpha-users"}'

# Try to add duplicate group
run_test "Try to add duplicate group" 409 POST "/tiers/acme-inc-1/groups" \
    '{"group":"free-users"}'

# Try to add group to non-existent tier
run_test "Add group to non-existent tier" 404 POST "/tiers/non-existent/groups" \
    '{"group":"test-group"}'

# Try to add invalid group name (empty)
run_test "Try to add empty group name" 400 POST "/tiers/acme-inc-1/groups" \
    '{"group":""}'

# Try to add invalid group name (uppercase)
run_test "Try to add invalid group name (uppercase)" 400 POST "/tiers/acme-inc-1/groups" \
    '{"group":"InvalidGroup"}'

# ============================================
# TEST 6: REMOVE GROUPS FROM TIERS
# ============================================
print_header "TEST 6: Remove Groups from Tiers"

run_test "Remove group from acme-inc-1" 200 DELETE "/tiers/acme-inc-1/groups/free-users" ""

run_test "Remove group from acme-inc-2" 200 DELETE "/tiers/acme-inc-2/groups/beta-users" ""

run_test "Remove group from acme-inc-3" 200 DELETE "/tiers/acme-inc-3/groups/alpha-users" ""

# Try to remove non-existent group
run_test "Remove non-existent group" 404 DELETE "/tiers/acme-inc-1/groups/non-existent-group" ""

# Try to remove group from non-existent tier
run_test "Remove group from non-existent tier" 404 DELETE "/tiers/non-existent/groups/test-group" ""

# ============================================
# TEST 7: VERIFY UPDATES
# ============================================
print_header "TEST 7: Verify Updates"

run_test "Verify acme-inc-1 after updates" 200 GET "/tiers/acme-inc-1" ""

run_test "Verify acme-inc-2 after updates" 200 GET "/tiers/acme-inc-2" ""

run_test "Verify acme-inc-3 after updates" 200 GET "/tiers/acme-inc-3" ""

# ============================================
# TEST 8: DELETE TIERS
# ============================================
print_header "TEST 8: Delete Tiers"

# Delete acme-inc-3 first
run_test "Delete acme-inc-3 tier" 204 DELETE "/tiers/acme-inc-3" ""

# Verify it's deleted
run_test "Verify acme-inc-3 is deleted" 404 GET "/tiers/acme-inc-3" ""

# Try to delete non-existent tier
run_test "Delete non-existent tier" 404 DELETE "/tiers/non-existent" ""

# Delete remaining tiers
run_test "Delete acme-inc-2 tier" 204 DELETE "/tiers/acme-inc-2" ""

run_test "Delete acme-inc-1 tier" 204 DELETE "/tiers/acme-inc-1" ""

# ============================================
# TEST 9: VERIFY ALL DELETED
# ============================================
print_header "TEST 9: Verify All Tiers Deleted"

run_test "Verify all tiers are deleted" 200 GET "/tiers" ""

# ============================================
# TEST 10: EDGE CASES
# ============================================
print_header "TEST 10: Edge Cases"

# Create tier without groups field (should default to empty list)
run_test "Create tier without groups field" 201 POST "/tiers" \
    '{"name":"acme-no-groups","description":"Test without groups field","level":1}'

# Verify the tier was created with empty groups
run_test "Verify tier has empty groups" 200 GET "/tiers/acme-no-groups" ""
# Check response contains empty groups array
RESPONSE=$(curl -s -k "${BASE_URL}/api/v1/tiers/acme-no-groups")
if echo "$RESPONSE" | grep -q '"groups":\[\]'; then
    echo -e "${GREEN}✓ Tier has empty groups array${NC}"
    PASSED=$((PASSED + 1))
else
    echo -e "${RED}✗ Tier does not have empty groups array${NC}"
    echo "Response: $RESPONSE"
    FAILED=$((FAILED + 1))
fi
TOTAL=$((TOTAL + 1))

# Create tier with empty groups array
run_test "Create tier with empty groups" 201 POST "/tiers" \
    '{"name":"acme-inc-1","description":"Test with empty groups","level":1,"groups":[]}'

# Update tier to empty groups
run_test "Update tier to empty groups" 200 PUT "/tiers/acme-inc-1" \
    '{"description":"Test with empty groups","level":1,"groups":[]}'

# Add group to tier with empty groups
run_test "Add group to tier with empty groups" 200 POST "/tiers/acme-inc-1/groups" \
    '{"group":"test-group"}'

# Remove the group
run_test "Remove group from tier" 200 DELETE "/tiers/acme-inc-1/groups/test-group" ""

# Clean up
run_test "Delete test tier (acme-inc-1)" 204 DELETE "/tiers/acme-inc-1" ""
run_test "Delete test tier (acme-no-groups)" 204 DELETE "/tiers/acme-no-groups" ""

# ============================================
# SUMMARY
# ============================================
print_header "TEST SUMMARY"

echo -e "Total Tests: ${TOTAL}"
echo -e "${GREEN}Passed: ${PASSED}${NC}"
echo -e "${RED}Failed: ${FAILED}${NC}"

if [ $FAILED -eq 0 ]; then
    echo -e "\n${GREEN}All tests passed!${NC}"
    exit 0
else
    echo -e "\n${RED}Some tests failed!${NC}"
    exit 1
fi

