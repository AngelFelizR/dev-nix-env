#!/bin/bash
# =============================================================================
#  TO EDIT — customize for each project. When done, rename:
#           ToEdit_setup.sh -> setup.sh
#  ---------------------------------------------------------------------------
#  WHAT TO CHANGE:
#    1. Replace `myproject` / `myproject-dev` with your project (below and in
#       the ~/.ssh/config block in the comment).
#    2. Port 2222 -> the one you put in docker-compose.yml.
#    3. IdentityFile -> your key (usually ~/.ssh/id_ed25519).
# =============================================================================
# Starts the private dev container and installs your SSH public key. Add once
# to ~/.ssh/config:
#
#   Host MyProject
#       HostName 127.0.0.1
#       User dev
#       Port 2222
#       IdentityFile ~/.ssh/id_ed25519
set -euo pipefail

# The Positron REH volume is external (seeded by hand once); create the
# empty one if it is not there yet -- the client downloads into it.
docker volume create myproject-positron-server >/dev/null

# Build if the image is not there yet (first run), then start.
if [ "$(docker images -q myproject-dev:latest 2>/dev/null)" = "" ]; then
    echo "Building myproject-dev:latest (first run, ~30-60 min)..."
    ./build-image.sh
fi
docker compose up -d

echo "Waiting for SSH service to be ready..."
sleep 5

if [ "$(docker inspect -f '{{.State.Running}}' myproject-dev 2>/dev/null)" = "true" ]; then
    docker compose cp ~/.ssh/id_ed25519.pub myproject-dev:/home/dev/.ssh/authorized_keys
    docker compose exec myproject-dev chown dev:dev /home/dev/.ssh/authorized_keys
    docker compose exec myproject-dev chmod 600 /home/dev/.ssh/authorized_keys
    echo "Ready! Connect with: ssh MyProject"
else
    echo "ERROR: The container myproject-dev stopped unexpectedly."
    echo "Check the reasons by running: docker logs myproject-dev"
    exit 1
fi
