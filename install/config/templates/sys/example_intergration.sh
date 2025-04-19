#!/bin/bash

# Load env and generate configs
set -o allexport
source .env
set +o allexport

envsubst < templates/config.template.yaml > $DATA_PATH/headscale/config.yaml
envsubst < templates/derpmap.template.json > $DATA_PATH/headscale/derpmap.json
envsubst < templates/Corefile.template > $DATA_PATH/coredns/Corefile
envsubst < templates/Caddyfile.template.json > $DATA_PATH/caddy/Caddyfile.json

# Start everything
docker-compose up -d
