# =============================================================================
#  TO EDIT — customize for each project. When done, rename:
#           ToEdit_prod.sh -> prod.sh
#  ---------------------------------------------------------------------------
#  WHAT TO CHANGE: replace `myproject` with your project name.
# =============================================================================
# Builds the production image (static site) from the dev image + the repo.
#
#   ./prod.sh                                  # builds myproject:prod
#   docker run --rm -p 8080:80 myproject:prod  # serve it
#
# The render stage bases on the dev image (it already carries the Nix closure:
# R, Quarto, pandoc and every package, plus the R_LIBS_SITE / PATH env). The
# prod image itself is tiny — only nginx + the rendered _site/.
set -euo pipefail

DEV_IMAGE="${DEV_IMAGE:-myproject-dev:latest}"
PROD_IMAGE="${PROD_IMAGE:-myproject:prod}"

if [ -z "$(docker images -q "$DEV_IMAGE" 2>/dev/null)" ]; then
    echo "dev image $DEV_IMAGE not found — building it first..."
    ./build-image.sh
fi

# The prod context is the repo SOURCE (not the dev closure in dist/), so it
# needs a different .dockerignore than the dev build. Swap it in for the
# duration, then restore.
if [ -f .dockerignore.prod ]; then
    if [ -f .dockerignore ]; then mv .dockerignore .dockerignore.dev; fi
    cp .dockerignore.prod .dockerignore
    trap 'rm -f .dockerignore; [ -f .dockerignore.dev ] && mv .dockerignore.dev .dockerignore' EXIT
fi

docker build -f prod.Dockerfile -t "$PROD_IMAGE" .
echo "done: $PROD_IMAGE"
echo "serve it with: docker run --rm -p 8080:80 $PROD_IMAGE"
