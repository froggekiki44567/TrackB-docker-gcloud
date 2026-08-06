#!/bin/bash
set -e

ENV=$1
[ -z "$ENV" ] && { echo "Usage: ./teardown.sh dev|prod"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config/${ENV}.env"

gcloud compute instances delete "${PROJECT_PREFIX}-vm" --zone="$ZONE" --project="$PROJECT_ID" --quiet 2>/dev/null || echo "VM not found"
gcloud compute firewall-rules delete "${PROJECT_PREFIX}-allow-http" --project="$PROJECT_ID" --quiet 2>/dev/null || echo "HTTP rule not found"
gcloud compute firewall-rules delete "${PROJECT_PREFIX}-allow-ssh" --project="$PROJECT_ID" --quiet 2>/dev/null || echo "SSH rule not found"
gcloud compute networks subnets delete "${PROJECT_PREFIX}-subnet" --region="$REGION" --project="$PROJECT_ID" --quiet 2>/dev/null || echo "Subnet not found"
gcloud compute networks delete "${PROJECT_PREFIX}-vpc" --project="$PROJECT_ID" --quiet 2>/dev/null || echo "Network not found"

echo "Teardown done for $ENV"