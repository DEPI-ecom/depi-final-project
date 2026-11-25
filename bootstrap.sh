#!/usr/bin/env bash
set -euo pipefail
ORG=DEPI-ecom
for r in ecom-web ecom-catalog ecom-search ecom-payment ecom-infra ecom-deploy; do
  [ -d "$r/.git" ] || git clone "git@github.com:$ORG/$r.git"
done
echo "Workspace ready."