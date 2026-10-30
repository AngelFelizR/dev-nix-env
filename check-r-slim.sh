#!/usr/bin/env bash
# Verifies that the "slim" R strip (nix/r-slim.nix) did not silently regress.
# Run it after ./build-image.sh (or after a pin bump):
#
#   ./check-r-slim.sh
#   IMAGE=my-project-dev:latest ./check-r-slim.sh
#
# Checks, against the built image, that the closure of R and /opt/r does NOT
# contain openjdk, gcc-wrapper, glib/cairo/pango .dev, graphviz or python3
# (what r-slim.nix must have removed), and that gfortran IS still present.
# The paths are computed from the pin (nix/pkgs.nix), so they do not depend on
# version numbers.
#
# NOTE: the *unwrapped* gcc (gcc-<ver>) stays in the closure on purpose,
# dragged in by gfortran (which r-slim.nix keeps). It is not a regression.
#
# Definitive check that gfortran still compiles Fortran (once after a bump,
# inside the build container):
#   nix-build --impure -E 'let pkgs = import ./nix/pkgs.nix; in pkgs.rPackages.KernSmooth'
set -euo pipefail

IMAGE="${IMAGE:-myproject-dev:latest}"

docker run --rm --entrypoint sh \
  -e NIX_CONFIG='experimental-features = nix-command' \
  -v "$PWD:/repo:ro" -w /repo \
  "$IMAGE" -c '
    set -e
    e() { nix eval --impure --raw --expr "let pkgs = import ./nix/pkgs.nix; in builtins.toString $1" 2>/dev/null; }
    R=$(e "pkgs.R")
    r_closure=$(nix-store -qR "$R")
    rbook_closure=$(nix-store -qR /opt/r)
    fail=0

    # What r-slim.nix must have removed.
    for a in openjdk stdenv.cc glib.dev cairo.dev pango.dev graphviz python3; do
      p=$(e "pkgs.$a")
      if echo "$r_closure" | grep -qF "$p"; then
        echo "REGRESSION: $a is still in R's closure ($p)" >&2
        fail=1
      fi
      if echo "$rbook_closure" | grep -qF "$p"; then
        echo "REGRESSION: $a is still in /opt/r's closure ($p)" >&2
        fail=1
      fi
    done

    # What r-slim.nix keeps on purpose.
    gf=$(e "pkgs.gfortran")
    if ! echo "$r_closure" | grep -qF "$gf"; then
      echo "REGRESSION: gfortran is no longer in R's closure" >&2
      fail=1
    fi

    if [ "$fail" = 0 ]; then
      echo "ok: R and /opt/r without toolchain; gfortran present"
    fi
    exit $fail
  '
