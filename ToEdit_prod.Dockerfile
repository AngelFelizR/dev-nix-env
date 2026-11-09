# =============================================================================
#  TO EDIT — customize for each project. When done, rename:
#           ToEdit_prod.Dockerfile -> prod.Dockerfile
#  ---------------------------------------------------------------------------
#  WHAT TO CHANGE: replace `myproject` with your project name (the dev image
#  tag below). You normally do not need to change anything else: the final
#  image is a static nginx server.
# =============================================================================
# Production packaging: renders the project with the SAME Nix closure the dev
# image carries, then ships only the static output in a tiny nginx image.
#
#   ./prod.sh                                  # build myproject:prod
#   docker run --rm -p 8080:80 myproject:prod  # serve it
#
# Two stages:
#   1. render — the full dev image (R + Quarto + packages) renders the site;
#      everything heavy stays here and is thrown away.
#   2. serve  — nginx serves the _site/ produced above (~tens of MB).

ARG DEV_IMAGE=myproject-dev:latest

FROM ${DEV_IMAGE} AS render
WORKDIR /repo
COPY . .
RUN quarto render

FROM nginx:alpine
COPY --from=render /repo/_site /usr/share/nginx/html
