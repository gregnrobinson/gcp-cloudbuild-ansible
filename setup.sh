#!/bin/bash
set -o errexit
set -o pipefail

export PROJECT_ID="<PROJECT_ID>"
export IMG_DEST="gcr.io/${PROJECT_ID}/ansible"

echo "Setting up inventory files..."
yq eval '.projects[0] |= ''"'$PROJECT_ID'"' -i ./config/inventory/gcp.yaml
yq eval '.gcp_project |= ''"'$PROJECT_ID'"' -i ./config/inventory/group_vars/all.yaml

echo "Setting up builder pipeline files..."
yq eval '.substitutions._IMG_DEST |= ''"'$IMG_DEST'"' -i ./pipeline/builder/cloudbuild-local.yaml
yq eval '.substitutions._IMG_DEST |= ''"'$IMG_DEST'"' -i ./pipeline/builder/cloudbuild.yaml

echo "Setting up runner pipeline files..."
yq eval '.substitutions._PROJECT_ID |= ''"'$PROJECT_ID'"' -i ./pipeline/runner/cloudbuild.yaml
yq eval '.substitutions._BASE_IMG |= ''"'$IMG_DEST'"' -i ./pipeline/runner/cloudbuild.yaml