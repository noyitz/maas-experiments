#!/bin/bash

# OpenShift API Curl Cheatsheet
# This tool demonstrates curl commands for OpenShift API operations
# Based on the golang-client example

# Colors for better output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Auto-detect values from oc command or use environment variables
get_oc_token() {
    if command -v oc &> /dev/null; then
        oc whoami -t 2>/dev/null || echo ""
    else
        echo ""
    fi
}

get_oc_server() {
    if command -v oc &> /dev/null; then
        oc whoami --show-server 2>/dev/null || echo "https://api.cluster.example.com:6443"
    else
        echo "https://api.cluster.example.com:6443"
    fi
}

get_oc_username() {
    if command -v oc &> /dev/null; then
        oc whoami 2>/dev/null || echo "your-username"
    else
        echo "your-username"
    fi
}

# Use auto-detected values or environment variables as fallback
OPENSHIFT_SERVER=${OPENSHIFT_SERVER:-$(get_oc_server)}
USERNAME=${USERNAME:-$(get_oc_username)}
TOKEN=${TOKEN:-$(get_oc_token)}

print_header() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${CYAN}     OpenShift API Curl Cheatsheet     ${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
    echo -e "${YELLOW}Server:${NC} $OPENSHIFT_SERVER"
    echo -e "${YELLOW}Username:${NC} $USERNAME"
    echo -e "${YELLOW}Token:${NC} ${TOKEN:0:20}..."
    echo ""
}

print_menu() {
    echo -e "${GREEN}Available Operations:${NC}"
    echo "1. Create User"
    echo "2. Create Group"
    echo "3. Add User to Group"
    echo "4. Deploy Model (LLMInferenceService)"
    echo "5. Get MaaS Authentication Token"
    echo "6. List Models (MaaS API)"
    echo "7. Query Model Inference Endpoint"
    echo "8. Deploy Group Rate Limit Policies"
    echo "X. Exit"
    echo ""
    echo -e "${BLUE}========================================${NC}"
}

get_user_input() {
    local prompt="$1"
    local default="$2"
    local input
    
    echo -e "${YELLOW}$prompt${NC}"
    if [ ! -z "$default" ]; then
        echo -n "(default: $default): "
    else
        echo -n ": "
    fi
    read -r input
    if [ -z "$input" ] && [ ! -z "$default" ]; then
        input="$default"
    fi
    echo "$input"
}

print_curl_command() {
    local title="$1"
    local description="$2"
    local curl_command="$3"
    
    echo ""
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}$title${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${YELLOW}Description:${NC}"
    echo "$description"
    echo ""
    echo -e "${YELLOW}Curl Command:${NC}"
    # Use printf with literal escape sequences that work reliably
    printf "${CYAN}%s${NC}\n" "$curl_command" | sed "s|<\([^>]*\)>|$(printf "\033[0m\033[1;33m")<\1>$(printf "\033[0m\033[0;36m")|g"
    echo ""
    echo -e "${YELLOW}To use this command:${NC}"
    echo -e "1. Replace the placeholders in ${YELLOW}<>${NC} with your actual values"
    echo "2. Copy and paste the command into your terminal"
    echo ""
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

create_user_demo() {
    local curl_cmd="curl -X POST \\
  -H \"Authorization: Bearer \$(oc whoami -t)\" \\
  -H \"Content-Type: application/json\" \\
  -H \"Accept: application/json\" \\
  -k \\
  \"\$OPENSHIFT_SERVER/apis/user.openshift.io/v1/users\" \\
  -d '{
    \"apiVersion\": \"user.openshift.io/v1\",
    \"kind\": \"User\",
    \"metadata\": {
      \"name\": \"<USER_NAME>\"
    }
  }'"

    print_curl_command \
        "CREATE USER" \
        "Creates a new user in OpenShift using the user.openshift.io/v1 API" \
        "$curl_cmd"
}

add_user_to_group_demo() {
    echo ""
    echo -e "${YELLOW}⚠️  IMPORTANT: No direct 'add user' API - OpenShift Groups use declarative model${NC}"
    echo -e "${YELLOW}The users field represents the complete desired state, not an append operation${NC}"
    echo ""
    
    local get_cmd="curl -X GET \\
  -H \"Authorization: Bearer \$(oc whoami -t)\" \\
  -H \"Accept: application/json\" \\
  -k \\
  \"\$OPENSHIFT_SERVER/apis/user.openshift.io/v1/groups/<GROUP_NAME>\""

    print_curl_command \
        "STEP 1: GET EXISTING GROUP" \
        "First, get the current group to see existing users" \
        "$get_cmd"
    
    local patch_cmd="curl -X PATCH \\
  -H \"Authorization: Bearer \$(oc whoami -t)\" \\
  -H \"Content-Type: application/merge-patch+json\" \\
  -H \"Accept: application/json\" \\
  -k \\
  \"\$OPENSHIFT_SERVER/apis/user.openshift.io/v1/groups/<GROUP_NAME>\" \\
  -d '{
    \"users\": [\"<EXISTING_USER1>\", \"<EXISTING_USER2>\", \"<NEW_USER>\"]
  }'"

    print_curl_command \
        "STEP 2: PATCH WITH ALL USERS" \
        "Update the group with ALL users (existing + new) to avoid deleting existing users" \
        "$patch_cmd"
    
    echo -e "${RED}⚠️  WARNING: Using PATCH with just [\"$username\"] will REPLACE all existing users!${NC}"
    echo -e "${YELLOW}Safe approach:${NC} Always include existing users + the new user in the users array"
    echo ""
    echo -e "${CYAN}Alternative: Use 'oc' command for safer group management:${NC}"
    echo -e "${CYAN}   oc adm groups add-users <_Group_Name> <_User_Name>${NC}"
    echo ""
    echo -e "${YELLOW}Note:${NC} This assumes the group already exists. To create a group first, use option 2."
    echo ""
}

deploy_model_demo() {
    local curl_cmd="curl -X POST \\
  -H \"Authorization: Bearer \$(oc whoami -t)\" \\
  -H \"Content-Type: application/json\" \\
  -H \"Accept: application/json\" \\
  -k \\
  \"\$OPENSHIFT_SERVER/apis/serving.kserve.io/v1alpha1/namespaces/<NAMESPACE>/llminferenceservices\" \\
  -d '{
    \"apiVersion\": \"serving.kserve.io/v1alpha1\",
    \"kind\": \"LLMInferenceService\",
    \"metadata\": {
      \"annotations\": {
        \"alpha.maas.opendatahub.io/tiers\": \"[\\\"redhat-users-tier\\\"]\"
      },
      \"name\": \"<MODEL_NAME>\",
      \"namespace\": \"<NAMESPACE>\"
    },
    \"spec\": {
      \"model\": {
        \"name\": \"facebook/opt-125m\",
        \"uri\": \"hf://facebook/opt-125m\"
      },
      \"replicas\": 1,
      \"router\": {
        \"gateway\": {
          \"refs\": [
            {
              \"name\": \"maas-default-gateway\",
              \"namespace\": \"openshift-ingress\"
            }
          ]
        },
        \"route\": {}
      },
      \"template\": {
        \"containers\": [
          {
            \"args\": [
              \"--port\", \"8000\",
              \"--model\", \"facebook/opt-125m\",
              \"--mode\", \"random\",
              \"--ssl-certfile\", \"/var/run/kserve/tls/tls.crt\",
              \"--ssl-keyfile\", \"/var/run/kserve/tls/tls.key\"
            ],
            \"command\": [\"/app/llm-d-inference-sim\"],
            \"env\": [
              {
                \"name\": \"POD_NAME\",
                \"valueFrom\": {
                  \"fieldRef\": {
                    \"apiVersion\": \"v1\",
                    \"fieldPath\": \"metadata.name\"
                  }
                }
              },
              {
                \"name\": \"POD_NAMESPACE\",
                \"valueFrom\": {
                  \"fieldRef\": {
                    \"apiVersion\": \"v1\",
                    \"fieldPath\": \"metadata.namespace\"
                  }
                }
              }
            ],
            \"image\": \"ghcr.io/llm-d/llm-d-inference-sim:v0.5.1\",
            \"imagePullPolicy\": \"Always\",
            \"livenessProbe\": {
              \"httpGet\": {
                \"path\": \"/health\",
                \"port\": \"https\",
                \"scheme\": \"HTTPS\"
              }
            },
            \"name\": \"main\",
            \"ports\": [
              {
                \"containerPort\": 8000,
                \"name\": \"https\",
                \"protocol\": \"TCP\"
              }
            ],
            \"readinessProbe\": {
              \"httpGet\": {
                \"path\": \"/ready\",
                \"port\": \"https\",
                \"scheme\": \"HTTPS\"
              }
            }
          }
        ]
      }
    }
  }'"

    print_curl_command \
        "DEPLOY MODEL (LLMInferenceService)" \
        "Deploys an LLMInferenceService model using the KServe API (serving.kserve.io/v1alpha1)" \
        "$curl_cmd"
    
    echo -e "${YELLOW}Notes:${NC}"
    echo "• This deploys the facebook/opt-125m model as configured in the Go client example"
    echo "• The namespace must exist before deploying"
    echo "• Model will be accessible via the maas-default-gateway route"
    echo "• You can modify the model name/uri, replicas, and other parameters as needed"
    echo ""
}

get_maas_token_demo() {
    echo ""
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}GET MAAS AUTHENTICATION TOKEN${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${YELLOW}Prerequisites:${NC}"
    echo "1. Login to the OpenShift web console"
    echo "2. Click on your username in the top-right corner"
    echo "3. Select 'Copy login command'"
    echo "4. Click 'Display Token' and copy the 'oc login' command"
    echo "5. Paste and run the 'oc login' command in your terminal"
    echo "6. Confirm you're logged in: oc whoami"
    echo "7. Requires jq for parsing JSON: brew install jq (or apt install jq)"
    echo ""
    echo -e "${YELLOW}Step 1: Get cluster domain and set HOST${NC}"
    echo -e "${CYAN}CLUSTER_DOMAIN=\$(kubectl get ingresses.config.openshift.io cluster -o jsonpath='{.spec.domain}')${NC}"
    echo -e "${CYAN}HOST=\"https://maas.\${CLUSTER_DOMAIN}\"${NC}"
    echo ""
    echo -e "${YELLOW}Step 2: Get MaaS authentication token${NC}"
    echo -e "${CYAN}TOKEN_RESPONSE=\$(curl -sSk \\\\${NC}"
    echo -e "${CYAN}  -H \"Authorization: Bearer \$(oc whoami -t)\" \\\\${NC}"
    echo -e "${CYAN}  -H \"Content-Type: application/json\" \\\\${NC}"
    echo -e "${CYAN}  -X POST \\\\${NC}"
    echo -e "${CYAN}  -d '{\"expiration\": \"10m\"}' \\\\${NC}"
    echo -e "${CYAN}  \"\${HOST}/maas-api/v1/tokens\")${NC}"
    echo ""
    echo -e "${YELLOW}Step 3: Check response and extract token${NC}"
    echo -e "${CYAN}echo \"Response: \$TOKEN_RESPONSE\"${NC}  # Debug: check what was returned"
    echo -e "${CYAN}export TOKEN=\$(echo \$TOKEN_RESPONSE | jq -r .token)${NC}"
    echo ""
    echo -e "${YELLOW}Troubleshooting:${NC}"
    echo "• If you get 'Internal Server Error': MaaS may not be installed or configured"
    echo "• If jq parse error: The API returned HTML/text instead of JSON"
    echo "• Check if MaaS is deployed: kubectl get pods -n maas-system"
    echo "• Verify endpoint: curl -k \${HOST}/maas-api/v1/health"
    echo ""
    echo -e "${YELLOW}Notes:${NC}"
    echo "• Token expires in 10 minutes by default"
    echo "• Use this token for subsequent MaaS API calls"
    echo ""
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

list_models_demo() {
    echo ""
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}LIST MODELS (MaaS API)${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${YELLOW}Description:${NC}"
    echo "Lists all available models using the MaaS API with authentication token"
    echo ""
    echo -e "${YELLOW}Prerequisites:${NC}"
    echo "1. Get MaaS authentication token (option 5)"
    echo "2. Set environment variables:"
    echo "   • HOST: MaaS cluster domain"
    echo "   • TOKEN: MaaS authentication token"
    echo ""
    echo -e "${YELLOW}Setup Steps:${NC}"
    echo -e "${CYAN}CLUSTER_DOMAIN=\$(kubectl get ingresses.config.openshift.io cluster -o jsonpath='{.spec.domain}')${NC}"
    echo -e "${CYAN}HOST=\"https://maas.\${CLUSTER_DOMAIN}\"${NC}"
    echo ""
    echo -e "${YELLOW}Curl Command:${NC}"
    echo -e "${CYAN}curl -X GET \\\\${NC}"
    echo -e "${CYAN}  -H \"Authorization: Bearer \$TOKEN\" \\\\${NC}"
    echo -e "${CYAN}  -H \"Accept: application/json\" \\\\${NC}"
    echo -e "${CYAN}  -k \\\\${NC}"
    echo -e "${CYAN}  \"\${HOST}/maas-api/v1/models\"${NC}"
    echo ""
    echo -e "${YELLOW}Troubleshooting:${NC}"
    echo "• If 'Internal Server Error': MaaS may not be installed"
    echo "• Check MaaS deployment: kubectl get pods -n maas-system"
    echo "• Verify MaaS health: curl -k \${HOST}/maas-api/v1/health"
    echo "• Ensure valid token: echo \$TOKEN"
    echo ""
    echo -e "${YELLOW}Notes:${NC}"
    echo "• MaaS token expires in 10 minutes"
    echo "• This lists all models available through the MaaS API"
    echo "• Save the model name and URL from response for option 7"
    echo ""
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

query_model_inference_demo() {
    echo ""
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}QUERY MODEL INFERENCE ENDPOINT${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${YELLOW}Description:${NC}"
    echo "Sends an inference request to a deployed model using the MaaS API"
    echo ""
    echo -e "${YELLOW}Prerequisites:${NC}"
    echo "1. Get MaaS authentication token (option 5)"
    echo "2. List models to get MODEL_NAME and MODEL_URL (option 6)"
    echo "3. Set environment variables:"
    echo "   • TOKEN: MaaS authentication token"
    echo "   • MODEL_URL: Model inference endpoint URL"
    echo "   • MODEL_NAME: Model name (both from option 6 response)"
    echo ""
    echo -e "${YELLOW}Setup Steps:${NC}"
    echo -e "${CYAN}export TOKEN=\$(echo \$TOKEN_RESPONSE | jq -r .token)${NC}"  # From option 5
    echo -e "${CYAN}export MODEL_URL=\"<url-from-models-response>\"${NC}"     # From option 6
    echo -e "${CYAN}export MODEL_NAME=\"<name-from-models-response>\"${NC}"   # From option 6
    echo ""
    echo -e "${YELLOW}Curl Command:${NC}"
    echo -e "${CYAN}curl -sSk \\\\${NC}"
    echo -e "${CYAN}  -H \"Authorization: Bearer \$TOKEN\" \\\\${NC}"
    echo -e "${CYAN}  -H \"Content-Type: application/json\" \\\\${NC}"
    echo -e "${CYAN}  -d '{\"model\": \"<MODEL_NAME>\", \"prompt\": \"Hello\", \"max_tokens\": 50}' \\\\${NC}"
    echo -e "${CYAN}  \"\${MODEL_URL}/v1/completions\"${NC}"
    echo ""
    echo -e "${YELLOW}Request Parameters:${NC}"
    echo "• model: Name of the model to query (from option 6)"
    echo "• prompt: Text prompt to send to the model"
    echo "• max_tokens: Maximum number of tokens in the response"
    echo ""
    echo -e "${YELLOW}Troubleshooting:${NC}"
    echo "• If 401 Unauthorized: Check your MaaS token is valid"
    echo "• If 404 Not Found: Verify the MODEL_URL is correct"
    echo "• If 500 Internal Error: Model may not be ready or available"
    echo "• Expected response: 200 OK with JSON completion data"
    echo ""
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

deploy_group_rate_limit_policies_demo() {
    echo ""
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}DEPLOY GROUP RATE LIMIT POLICIES${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${YELLOW}Description:${NC}"
    echo "Deploys a complete group rate limiting setup including:"
    echo "• Tier-to-group mapping (ConfigMap)"
    echo "• Request rate limit policy (RateLimitPolicy)"
    echo "• Token rate limit policy (TokenRateLimitPolicy)"
    echo ""
    echo -e "${YELLOW}Prerequisites:${NC}"
    echo "1. OpenShift cluster with Kuadrant installed"
    echo "2. maas-default-gateway deployed in openshift-ingress namespace"
    echo "3. Cluster admin permissions"
    echo ""
    echo ""
    
    # Step 1: Tier-to-Group Mapping
    local tier_mapping_cmd="curl -X POST \\\\
  -H \"Authorization: Bearer \$(oc whoami -t)\" \\\\
  -H \"Content-Type: application/json\" \\\\
  -H \"Accept: application/json\" \\\\
  -k \\\\
  \"\$OPENSHIFT_SERVER/api/v1/namespaces/maas-api/configmaps\" \\\\
  -d '{
    \"apiVersion\": \"v1\",
    \"kind\": \"ConfigMap\",
    \"metadata\": {
      \"name\": \"tier-to-group-mapping\",
      \"namespace\": \"maas-api\",
      \"labels\": {
        \"app\": \"maas-api\",
        \"app.kubernetes.io/component\": \"api\",
        \"app.kubernetes.io/name\": \"maas-api\",
        \"app.kubernetes.io/part-of\": \"model-as-a-service\",
        \"component\": \"tier-mapping\"
      }
    },
    \"data\": {
      \"tiers\": \"# Group tier configuration\\\\n- name: <GROUP_NAME>-<TIER_LEVEL>-tier\\\\n  description: Tier for <GROUP_NAME> <TIER_LEVEL> users\\\\n  level: <TIER_PRIORITY>\\\\n  groups:\\\\n  - tier-<GROUP_NAME>-<TIER_LEVEL>\\\\n\"
    }
  }'"
  
    print_curl_command \
        "STEP 1: CREATE TIER-TO-GROUP MAPPING" \
        "Creates a ConfigMap that maps group tiers to user groups. Replace placeholders with actual values." \
        "$tier_mapping_cmd"
    
    echo -e "${YELLOW}Required placeholders:${NC}"
    echo "• <GROUP_NAME>: Group identifier (e.g., 'acme', 'redhat')"
    echo "• <TIER_LEVEL>: Tier level (e.g., 'dev', 'prod', 'enterprise')"
    echo "• <TIER_PRIORITY>: Numeric priority (10=dev, 20=prod, 30=enterprise)"
    echo ""
    
    # Step 2: Request Rate Limit Policy
    local rate_limit_cmd="curl -X POST \\\\
  -H \"Authorization: Bearer \$(oc whoami -t)\" \\\\
  -H \"Content-Type: application/json\" \\\\
  -H \"Accept: application/json\" \\\\
  -k \\\\
  \"\$OPENSHIFT_SERVER/apis/kuadrant.io/v1/namespaces/openshift-ingress/ratelimitpolicies\" \\\\
  -d '{
    \"apiVersion\": \"kuadrant.io/v1\",
    \"kind\": \"RateLimitPolicy\",
    \"metadata\": {
      \"name\": \"<GROUP_NAME>-rate-limits\",
      \"namespace\": \"openshift-ingress\"
    },
    \"spec\": {
      \"targetRef\": {
        \"group\": \"gateway.networking.k8s.io\",
        \"kind\": \"Gateway\",
        \"name\": \"maas-default-gateway\"
      },
      \"limits\": {
        \"<GROUP_NAME>-<TIER_LEVEL>\": {
          \"rates\": [
            {
              \"limit\": <REQUESTS_PER_WINDOW>,
              \"window\": \"<TIME_WINDOW>\"
            }
          ],
          \"when\": [
            {
              \"predicate\": \"auth.identity.tier == \\\\\"<GROUP_NAME>-<TIER_LEVEL>-tier\\\\\"\"
            }
          ],
          \"counters\": [
            {
              \"expression\": \"auth.identity.userid\"
            }
          ]
        }
      }
    }
  }'"
    
    print_curl_command \
        "STEP 2: CREATE REQUEST RATE LIMIT POLICY" \
        "Creates a RateLimitPolicy that limits requests per time window for the group tier" \
        "$rate_limit_cmd"
    
    echo -e "${YELLOW}Additional placeholders:${NC}"
    echo "• <REQUESTS_PER_WINDOW>: Number of requests allowed (e.g., 5, 20, 50)"
    echo "• <TIME_WINDOW>: Time window (e.g., '1m', '2m', '5m')"
    echo ""
    
    # Step 3: Token Rate Limit Policy
    local token_rate_limit_cmd="curl -X POST \\\\
  -H \"Authorization: Bearer \$(oc whoami -t)\" \\\\
  -H \"Content-Type: application/json\" \\\\
  -H \"Accept: application/json\" \\\\
  -k \\\\
  \"\$OPENSHIFT_SERVER/apis/kuadrant.io/v1alpha1/namespaces/openshift-ingress/tokenratelimitpolicies\" \\\\
  -d '{
    \"apiVersion\": \"kuadrant.io/v1alpha1\",
    \"kind\": \"TokenRateLimitPolicy\",
    \"metadata\": {
      \"name\": \"<GROUP_NAME>-token-rate-limits\",
      \"namespace\": \"openshift-ingress\"
    },
    \"spec\": {
      \"targetRef\": {
        \"group\": \"gateway.networking.k8s.io\",
        \"kind\": \"Gateway\",
        \"name\": \"maas-default-gateway\"
      },
      \"limits\": {
        \"<GROUP_NAME>-<TIER_LEVEL>-user-tokens\": {
          \"counters\": [
            {
              \"expression\": \"auth.identity.userid\"
            }
          ],
          \"rates\": [
            {
              \"limit\": <TOKENS_PER_WINDOW>,
              \"window\": \"<TOKEN_TIME_WINDOW>\"
            }
          ],
          \"when\": [
            {
              \"predicate\": \"auth.identity.tier == \\\\\"<GROUP_NAME>-<TIER_LEVEL>-tier\\\\\"\"
            }
          ]
        }
      }
    }
  }'"
    
    print_curl_command \
        "STEP 3: CREATE TOKEN RATE LIMIT POLICY" \
        "Creates a TokenRateLimitPolicy that limits AI tokens consumed per time window for the group tier" \
        "$token_rate_limit_cmd"
    
    echo -e "${YELLOW}Token-specific placeholders:${NC}"
    echo "• <TOKENS_PER_WINDOW>: Number of AI tokens allowed (e.g., 100, 5000, 100000)"
    echo "• <TOKEN_TIME_WINDOW>: Time window for tokens (e.g., '1m', '5m', '1h')"
    echo ""
    
    # Step 4: Restart MaaS API
    local restart_cmd="curl -X PATCH \\\\
  -H \"Authorization: Bearer \$(oc whoami -t)\" \\\\
  -H \"Content-Type: application/strategic-merge-patch+json\" \\\\
  -k \\\\
  \"\$OPENSHIFT_SERVER/apis/apps/v1/namespaces/maas-api/deployments/maas-api\" \\\\
  -d '{
    \"spec\": {
      \"template\": {
        \"metadata\": {
          \"annotations\": {
            \"kubectl.kubernetes.io/restartedAt\": \"'$(date -u +%Y-%m-%dT%H:%M:%SZ)'\"
          }
        }
      }
    }
  }'"
    
    print_curl_command \
        "STEP 4: RESTART MAAS API (REQUIRED)" \
        "Restarts the MaaS API deployment to reload the new tier-to-group mapping configuration" \
        "$restart_cmd"
    
    echo -e "${YELLOW}Example Values:${NC}"
    echo "For a group 'acme' with 'dev' tier allowing 10 requests/2min and 1000 tokens/1min:"
    echo "• GROUP_NAME: acme"
    echo "• TIER_LEVEL: dev"
    echo "• TIER_PRIORITY: 10"
    echo "• REQUESTS_PER_WINDOW: 10"
    echo "• TIME_WINDOW: 2m"
    echo "• TOKENS_PER_WINDOW: 1000"
    echo "• TOKEN_TIME_WINDOW: 1m"
    echo ""
    echo -e "${YELLOW}Post-deployment Steps:${NC}"
    echo "1. Create the user group: oc adm groups new tier-acme-dev"
    echo "2. Add users to the group: oc adm groups add-users tier-acme-dev user1 user2"
    echo "3. Verify policies are applied: oc get ratelimitpolicies,tokenratelimitpolicies -n openshift-ingress"
    echo "4. Monitor rate limiting: Check Kuadrant logs and metrics"
    echo ""
    echo -e "${RED}⚠️  IMPORTANT NOTES:${NC}"
    echo "• Tier names must match exactly between all three resources"
    echo "• MaaS API restart is required after tier mapping changes"
    echo "• Users must be in the correct OpenShift group to get tier access"
    echo "• Policies apply at the gateway level for all routes"
    echo ""
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

list_users_demo() {
    local curl_cmd="curl -X GET \\
  -H \"Authorization: Bearer \$(oc whoami -t)\" \\
  -H \"Accept: application/json\" \\
  -k \\
  \"\$OPENSHIFT_SERVER/apis/user.openshift.io/v1/users\""

    print_curl_command \
        "LIST USERS" \
        "Retrieves a list of all users in the OpenShift cluster" \
        "$curl_cmd"
}

get_user_demo() {
    local curl_cmd="curl -X GET \\
  -H \"Authorization: Bearer \$(oc whoami -t)\" \\
  -H \"Accept: application/json\" \\
  -k \\
  \"\$OPENSHIFT_SERVER/apis/user.openshift.io/v1/users/<USER_NAME>\""

    print_curl_command \
        "GET USER DETAILS" \
        "Retrieves detailed information about a specific user" \
        "$curl_cmd"
}

delete_user_demo() {
    local curl_cmd="curl -X DELETE \\
  -H \"Authorization: Bearer \$(oc whoami -t)\" \\
  -H \"Accept: application/json\" \\
  -k \\
  \"\$OPENSHIFT_SERVER/apis/user.openshift.io/v1/users/<USER_NAME>\""

    print_curl_command \
        "DELETE USER" \
        "Deletes a user from the OpenShift cluster (WARNING: This action cannot be undone!)" \
        "$curl_cmd"
    
    echo -e "${RED}⚠️  WARNING: This will permanently delete the user!${NC}"
    echo ""
}

list_groups_demo() {
    local curl_cmd="curl -X GET \\
  -H \"Authorization: Bearer \$(oc whoami -t)\" \\
  -H \"Accept: application/json\" \\
  -k \\
  \"\$OPENSHIFT_SERVER/apis/user.openshift.io/v1/groups\""

    print_curl_command \
        "LIST GROUPS" \
        "Retrieves a list of all groups in the OpenShift cluster" \
        "$curl_cmd"
}

create_group_demo() {
    local curl_cmd="curl -X POST \\
  -H \"Authorization: Bearer \$(oc whoami -t)\" \\
  -H \"Content-Type: application/json\" \\
  -H \"Accept: application/json\" \\
  -k \\
  \"\$OPENSHIFT_SERVER/apis/user.openshift.io/v1/groups\" \\
  -d '{
    \"apiVersion\": \"user.openshift.io/v1\",
    \"kind\": \"Group\",
    \"metadata\": {
      \"name\": \"<GROUP_NAME>\"
    },
    \"users\": []
  }'"

    print_curl_command \
        "CREATE GROUP" \
        "Creates a new group in OpenShift using the user.openshift.io/v1 API" \
        "$curl_cmd"
}

show_token_info() {
    echo ""
    echo -e "${YELLOW}📝 Getting Your Bearer Token:${NC}"
    echo ""
    echo "To get your bearer token, follow these steps:"
    echo ""
    echo "1. Login to the OpenShift web console:"
    echo -e "${CYAN}   https://console-openshift-console.apps.ocpai3.sandbox544.opentlc.com${NC}"
    echo ""
    echo "2. Click on your username in the top-right corner"
    echo ""
    echo "3. Select 'Copy login command'"
    echo ""
    echo "4. Click 'Display Token' and copy the 'oc login' command"
    echo ""
    echo "5. Paste and run the 'oc login' command in your terminal"
    echo ""
    echo "6. Confirm you're logged in:"
    echo -e "${CYAN}   oc whoami${NC}"
    echo ""
    echo "7. Set the server environment variable:"
    echo -e "${CYAN}   export OPENSHIFT_SERVER=\"https://api.ocpai3.sandbox544.opentlc.com:6443\"${NC}"
    echo ""
    echo "8. Run this script again - it will auto-detect your credentials"
    echo ""
    
    if [ -z "$TOKEN" ] || [ "$TOKEN" = "" ]; then
        echo -e "${YELLOW}⚠️  No authentication detected! Please follow the steps above.${NC}"
        echo ""
    else
        echo -e "${GREEN}✅ Authentication auto-detected from 'oc' command${NC}"
        echo ""
    fi
}

main() {
    while true; do
        clear
        print_header
        show_token_info
        print_menu
        
        echo -n -e "${YELLOW}Select an option: ${NC}"
        read -r choice
        
        case $choice in
            1)
                create_user_demo
                ;;
            2)
                create_group_demo
                ;;
            3)
                add_user_to_group_demo
                ;;
            4)
                deploy_model_demo
                ;;
            5)
                get_maas_token_demo
                ;;
            6)
                list_models_demo
                ;;
            7)
                query_model_inference_demo
                ;;
            8)
                deploy_group_rate_limit_policies_demo
                ;;
            [Xx])
                echo -e "${GREEN}Thanks for using the OpenShift API Curl Cheatsheet!${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}Invalid option. Please try again.${NC}"
                sleep 2
                continue
                ;;
        esac
        
        echo ""
        echo -e "${BLUE}Press Enter to continue...${NC}"
        read -r
    done
}

# Check if script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi