#! /bin/bash

# Get a token from Key Cloak to access the OpenShift cluster
export KK_JWT=$(curl -d 'client_id=maas' -d 'client_secret=<client_secret>' -d 'username=<username>' -d 'password=password' -d 'grant_type=password' '<keycloak_url>/realms/red-hat/protocol/openid-connect/token' | jq -r '.access_token')
echo "Keycloak JWT: $KK_JWT"

# Get cluster details
CLUSTER_DOMAIN=$(kubectl get ingresses.config.openshift.io cluster -o jsonpath='{.spec.domain}')
echo "Cluster domain: $CLUSTER_DOMAIN"

# http:// until the bug is pushed to main branch
HOST="http://maas.${CLUSTER_DOMAIN}"
echo "MaaS Host url: $HOST"

# Get a MaaS Token from the maas-api, using your Key Cloak identity
TOKEN_RESPONSE=$(curl -sSk \
  -H "Authorization: Bearer ${KK_JWT}" \
  -H "Content-Type: application/json" \
  -X POST \
  -d '{"expiration": "10m"}' \
  "${HOST}/maas-api/v1/tokens")

echo $TOKEN_RESPONSE

TOKEN=$(echo $TOKEN_RESPONSE | jq -r .token)

# List all available models
MODELS=$(curl -sSk ${HOST}/maas-api/v1/models \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $TOKEN" | jq -r .)

echo $MODELS | jq .

MODEL_NAME=$(echo $MODELS | jq -r '.data[0].id')
MODEL_URL=$(echo $MODELS | jq -r '.data[0].url')
echo "Model URL: $MODEL_URL"

# Inference against the model.
curl -sSk -H "Authorization: Bearer $TOKEN"   -H "Content-Type: application/json"   -d "{\"model\": \"${MODEL_NAME}\", \"prompt\": \"Hello\", \"max_tokens\": 50}"   "${MODEL_URL}/v1/completions" | jq

