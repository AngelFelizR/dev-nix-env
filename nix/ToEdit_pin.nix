# =============================================================================
#  TO EDIT — THE pin: single source of truth for the nixpkgs snapshot.
#  When done, rename: nix/ToEdit_pin.nix -> nix/pin.nix
#  ---------------------------------------------------------------------------
#  WHAT TO CHANGE: the DATE and the sha256, together, every time you bump.
#  That is all — nix/pkgs.nix and nix/system.nix both import this file, so no
#  other file carries a URL or a hash (./check fails if one reappears, and it
#  runs automatically at the start of ./build-image.sh and in CI).
#
#  Valid dates + sha256 come from rix's snapshot table (each date is an
#  rstats-on-nix snapshot of R + CRAN/Bioconductor):
#    https://raw.githubusercontent.com/ropensci/rix/refs/heads/main/inst/extdata/available_df.csv
#  If a build dies with `NAR hash mismatch`, that row's hash is stale —
#  recompute it with:  nix-prefetch-url --unpack <URL>  and put it below.
# =============================================================================
{
  # rstats-on-nix: a dated nixpkgs fork with a binary cachix cache for R
  # packages (see README: "What is actually cached").
  # Python-only project? Use an official nixpkgs release tag instead, e.g.:
  #   url = "https://github.com/NixOS/nixpkgs/archive/refs/tags/26.05.tar.gz";
  # and drop the overlay in nix/pkgs.nix (README: "Python only (drop R)").
  url = "https://github.com/rstats-on-nix/nixpkgs/archive/2026-09-28.tar.gz";
  sha256 = "1bn5kv5vn78lcwdymaz8ggb7s5ywk6d3y5fkdaya9b1bwp8vz8s4";
}
