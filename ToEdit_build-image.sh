#!/bin/bash
# =============================================================================
#  TO EDIT — customize for each project. When done, rename:
#           ToEdit_build-image.sh -> build-image.sh
#  ---------------------------------------------------------------------------
#  WHAT TO CHANGE:
#    1. The IMAGE default below (replace `myproject` with your project). You
#       can also pass it as a variable: IMAGE=... ./build-image.sh
#    2. VOLUME: SHARED by all your projects on purpose (see below) — do not
#       personalize it. Only override it if you ever want a project-private
#       store: VOLUME=myproject-nix-store ./build-image.sh
# =============================================================================
# Builds the private dev image in two steps:
#
#   1. the Nix closures are built INSIDE a container whose /nix is a
#      persistent docker volume, so R and friends are compiled once and
#      adding a package later only compiles what is missing;
#   2. the runtime image is built from the resulting tarball (Dockerfile).
#
#   ./build-image.sh          # everything
set -euo pipefail

# Fail fast: the pin must be consistent BEFORE anything compiles (the same
# ./check also runs in CI, see .github/workflows/check.yml).
./check

IMAGE="${IMAGE:-myproject-dev:latest}"
# ONE store volume shared by every project on this machine: the Nix store is
# content-addressed, so projects with the same pin share the same built paths
# — R compiles once, not once per project. Only the BUILD cache is shared;
# each project still gets its own runtime image. Removing this volume
# (README: Housekeeping) makes every project recompile once.
VOLUME="${VOLUME:-dev-nix-store}"
NIX_IMAGE="${NIX_IMAGE:-nixos/nix:2.35.2}"

docker volume create "$VOLUME" >/dev/null

# Seed the volume once: nix lives in the store, so an empty volume would
# have no nix to run. Only the BASE image is a valid seed: our runtime image
# carries the closure as plain files, but its nix db never registered them,
# so seeding from it would make nix recompile everything (R included).
if ! docker run --rm -v "$VOLUME:/target" "$NIX_IMAGE" \
       sh -c '[ -n "$(ls -A /target/store 2>/dev/null)" ]' >/dev/null 2>&1; then
    echo "seeding $VOLUME from $NIX_IMAGE ..."
    docker run --rm -v "$VOLUME:/target" "$NIX_IMAGE" \
        sh -c 'tar -C /nix -cf - store var 2>/dev/null | tar -C /target -xf -'
fi

mkdir -p dist
# The Dockerfile reads the same nix.conf (single source) from dist/.
cp nix/nix.conf dist/nix.conf
echo "building the Nix closures (incremental: only what changed compiles)..."
docker run --rm \
    -v "$VOLUME:/nix" \
    -v "$PWD:/build" \
    -w /build \
    "$NIX_IMAGE" \
    sh -c "
        set -e
        mkdir -p /etc/nix
        cat nix/nix.conf >> /etc/nix/nix.conf
        nix-build -E '(let pkgs = import ./nix/pkgs.nix; in import ./nix/system.nix { inherit pkgs; })' \
            -o /build/dist/out-system
        nix-build nix/packages.nix -A rEnv -o /build/dist/out-r-env
        nix-build nix/positron-libs.nix -o /build/dist/out-positron
        readlink -f /build/dist/out-system > /build/dist/out-system.path
        readlink -f /build/dist/out-r-env  > /build/dist/out-r-env.path
        readlink -f /build/dist/out-positron > /build/dist/out-positron.path
        nix-store -qR /build/dist/out-system /build/dist/out-r-env /build/dist/out-positron | sort -u \
            > /build/dist/closure
        # Raw db dump, trimmed on the host to the closure below: the full
        # dump carries historical .drv entries whose files are not in the
        # tarball, and nix-store --load-db refuses those.
        nix-store --dump-db > /build/dist/db.raw
        tar -C / -czf /build/dist/closure.tar.gz -T /build/dist/closure
    "

# db entry = path, nar hash, refcount, deriver, #refs, refs...; keep only
# the entries of the closure and drop the deriver (its .drv is not shipped).
awk '
    NR == FNR { keep[$0] = 1; next }
    {
        path = $0; getline hash; getline refc; getline der; getline n
        refs = ""
        for (i = 0; i < n; i++) { getline r; refs = refs r ORS }
        if (path in keep) { print path; print hash; print refc; print ""; print n; printf "%s", refs }
    }
' dist/closure dist/db.raw > dist/db.dump
rm -f dist/db.raw

# The container wrote dist/ as root; hand it back to the invoking user.
docker run --rm -v "$PWD/dist:/d" alpine \
    chown -R "$(id -u):$(id -g)" /d

echo "building the runtime image $IMAGE ..."
docker build -t "$IMAGE" .
echo "done: $IMAGE"
# Cheap safety net: if the R strip (nix/r-slim.nix) regresses, the image
# grows suddenly (openjdk ~573 MB). Print the size to see it at a glance.
# (check-r-slim.sh does the exact per-store-path check.)
SIZE=$(docker image inspect --format '{{.Size}}' "$IMAGE")
echo "image size: $((SIZE / 1024 / 1024)) MB"
