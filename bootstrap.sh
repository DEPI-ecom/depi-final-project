#!/usr/bin/env bash
set -euo pipefail
ORG=DEPI-ecom
REPOS="ecom-web ecom-api-gateway ecom-user ecom-catalog ecom-search ecom-cart ecom-order ecom-payment ecom-deploy ecom-infra"
for r in $REPOS; do
  [ -d "$r/.git" ] || git clone "https://github.com/$ORG/$r.git"
done
echo "Workspace ready."