#!/bin/bash
source /opt/cloud-init-scripts/00-env-setter.sh
set -e # Exit immediately if a command exits with a non-zero status.

# --- Configuration and Validation ---
# Use environment variables from 00-env-setter.sh
CF_API_TOKEN="$CF_DNS_API_KEY"
TARGET_DOMAIN="$HOST_DOMAIN"
ROOT_DOMAIN="$DOMAIN"

# Validate required variables
if [ -z "$TARGET_DOMAIN" ]; then
  echo "ERROR: HOST_DOMAIN is not set. Aborting."
  exit 1
fi
if [ -z "$ROOT_DOMAIN" ]; then
  echo "ERROR: DOMAIN is not set. Aborting."
  exit 1
fi
if [ -z "$CF_API_TOKEN" ]; then
  echo "ERROR: Cloudflare API Key (CF_DNS_API_KEY) is not set. Aborting."
  exit 1
fi

echo "--- Starting Cloudflare DNS Update Script (Domain: $TARGET_DOMAIN) ---"

# Check for required commands
command -v curl > /dev/null || { echo "ERROR: curl command not found."; exit 1; }
command -v jq > /dev/null || { echo "ERROR: jq command not found."; exit 1; }

# --- Get Public IP ---
# Retry getting public IP up to 3 times with different services
PUBLIC_IP=""
for i in 1 2 3; do
  PUBLIC_IP=$(curl -s --max-time 10 ifconfig.me)
  [ -n "$PUBLIC_IP" ] && break
  PUBLIC_IP=$(curl -s --max-time 10 api.ipify.org)
  [ -n "$PUBLIC_IP" ] && break
  PUBLIC_IP=$(curl -s --max-time 10 checkip.amazonaws.com)
  [ -n "$PUBLIC_IP" ] && break
  echo "Attempt $i to get public IP failed. Retrying in 5s..."
  sleep 5
done
if [[ -z "$PUBLIC_IP" ]]; then echo "Error: Could not retrieve public IP address after multiple attempts."; exit 1; fi
echo "Public IP detected: $PUBLIC_IP"
echo "Determined root domain: $ROOT_DOMAIN"

# --- Cloudflare API Interaction ---
CF_API_BASE="https://api.cloudflare.com/client/v4"
AUTH_HEADER="Authorization: Bearer $CF_API_TOKEN"
CONTENT_HEADER="Content-Type: application/json"

# Get Zone ID
ZONE_RESPONSE=$(curl --globoff -s -X GET "$CF_API_BASE/zones?name=$ROOT_DOMAIN" -H "$AUTH_HEADER" -H "$CONTENT_HEADER")
ZONE_ID=$(echo "$ZONE_RESPONSE" | jq -r '.result[0].id // empty')
if [[ -z "$ZONE_ID" ]]; then echo "Error: Could not find Zone ID for domain '$ROOT_DOMAIN'. Response: $(echo "$ZONE_RESPONSE" | head -c 200)"; exit 1; fi
echo "Zone ID found: $ZONE_ID"

# Check for existing DNS record
RECORD_RESPONSE=$(curl --globoff -s -X GET "$CF_API_BASE/zones/$ZONE_ID/dns_records?type=A&name=$TARGET_DOMAIN" -H "$AUTH_HEADER" -H "$CONTENT_HEADER")
RECORD_ID=$(echo "$RECORD_RESPONSE" | jq -r '.result[0].id // empty')
EXISTING_IP=$(echo "$RECORD_RESPONSE" | jq -r '.result[0].content // empty')

# Prepare DNS data for update/create
# Set TTL to 1 (auto) and proxied to false for ACME challenges
DNS_DATA=$(jq -n --arg name "$TARGET_DOMAIN" --arg content "$PUBLIC_IP" '{type: "A", name: $name, content: $content, ttl: 1, proxied: false}')

if [[ -n "$RECORD_ID" ]]; then
  # Record exists, check if update is needed
  RECORD_IS_PROXIED=$(echo "$RECORD_RESPONSE" | jq -r '.result[0].proxied // "false"')
  if [[ "$EXISTING_IP" == "$PUBLIC_IP" && "$RECORD_IS_PROXIED" == "false" ]]; then
    echo "IP address ($PUBLIC_IP) and proxy status are already up-to-date for $TARGET_DOMAIN."
  else
    echo "Updating existing A record ($RECORD_ID) for $TARGET_DOMAIN. New IP: $PUBLIC_IP, Proxied: false."
    UPDATE_RESPONSE=$(curl -s -X PUT "$CF_API_BASE/zones/$ZONE_ID/dns_records/$RECORD_ID" -H "$AUTH_HEADER" -H "$CONTENT_HEADER" --data "$DNS_DATA")
    SUCCESS=$(echo "$UPDATE_RESPONSE" | jq -r '.success')
    if [[ "$SUCCESS" != "true" ]]; then echo "Error updating DNS record. Response: $UPDATE_RESPONSE"; exit 1; fi
    echo "Successfully updated DNS record for $TARGET_DOMAIN."
  fi
else
  # Record does not exist, create it
  echo "No existing A record found for $TARGET_DOMAIN. Creating new record..."
  CREATE_RESPONSE=$(curl -s -X POST "$CF_API_BASE/zones/$ZONE_ID/dns_records" -H "$AUTH_HEADER" -H "$CONTENT_HEADER" --data "$DNS_DATA")
  SUCCESS=$(echo "$CREATE_RESPONSE" | jq -r '.success')
  if [[ "$SUCCESS" != "true" ]]; then echo "Error creating DNS record. Response: $CREATE_RESPONSE"; exit 1; fi
  echo "Successfully created new DNS record for $TARGET_DOMAIN."
fi

echo "--- Cloudflare DNS Update Script Completed Successfully for $TARGET_DOMAIN ---"
