#!/bin/bash
set -e

ENV=$1
MODE=$2

if [ -z "$ENV" ]; then
  echo "Usage: ./provision.sh dev|prod [--apply]"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config/${ENV}.env"

APPLY=false
[ "$MODE" == "--apply" ] && APPLY=true

echo "env=$ENVIRONMENT vpc=${PROJECT_PREFIX}-vpc vm=${PROJECT_PREFIX}-vm machine=$MACHINE_TYPE public=$PUBLIC_ACCESS mode=$([ "$APPLY" == true ] && echo APPLY || echo DRY-RUN)"

if [ "$APPLY" == false ]; then
  echo "Dry-run — nothing created. Use --apply to run for real."
  exit 0
fi

gcloud compute networks create "${PROJECT_PREFIX}-vpc" \
  --project="$PROJECT_ID" --subnet-mode=custom 2>/dev/null || echo "VPC exists, skipping"

gcloud compute networks subnets create "${PROJECT_PREFIX}-subnet" \
  --project="$PROJECT_ID" --network="${PROJECT_PREFIX}-vpc" \
  --range=10.10.0.0/24 --region="$REGION" 2>/dev/null || echo "Subnet exists, skipping"

gcloud compute firewall-rules create "${PROJECT_PREFIX}-allow-ssh" \
  --project="$PROJECT_ID" --network="${PROJECT_PREFIX}-vpc" \
  --allow=tcp:22 --source-ranges=0.0.0.0/0 --target-tags=http-server 2>/dev/null || echo "SSH rule exists, skipping"

if [ "$PUBLIC_ACCESS" = true ]; then
  gcloud compute firewall-rules create "${PROJECT_PREFIX}-allow-http" \
    --project="$PROJECT_ID" --network="${PROJECT_PREFIX}-vpc" \
    --allow=tcp:80 --source-ranges=0.0.0.0/0 --target-tags=http-server 2>/dev/null || echo "HTTP rule exists, skipping"
else
  echo "PUBLIC_ACCESS=false — no HTTP firewall rule created"
fi

gcloud compute instances create "${PROJECT_PREFIX}-vm" \
  --project="$PROJECT_ID" --zone="$ZONE" --machine-type="$MACHINE_TYPE" \
  --subnet="${PROJECT_PREFIX}-subnet" --tags=http-server \
  --image-family=debian-12 --image-project=debian-cloud \
  --metadata=environment="$ENVIRONMENT" \
  --metadata-from-file=startup-script="${SCRIPT_DIR}/deploy.sh" \
  $([ "$PUBLIC_ACCESS" != true ] && echo --no-address) \
  2>/dev/null || echo "VM exists, skipping"

echo "Done. Wait ~2 min, then: gcloud compute instances list --project=$PROJECT_ID"