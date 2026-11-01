# =============================================================================
#  TO EDIT — the environment PIN. When done, rename:
#           nix/ToEdit_pkgs.nix -> nix/pkgs.nix
#  ---------------------------------------------------------------------------
#  WHAT TO CHANGE:
#    1. The DATE below pins the version of EVERYTHING (R, Python, Quarto...).
#       Changing it = updating every version at once. Valid dates (and their
#       sha256) are in rix's CSV:
#         https://github.com/ropensci/rix/.../inst/extdata/available_df.csv
#       When bumping, change the date and the sha256 below (and the same ones
#       in nix/system.nix -> nixpkgsSrc).
#    2. We use the rstats-on-nix nixpkgs fork (dated snapshot + cachix cache)
#       so R packages download as binaries.
#       If your project does NOT use R, switch the URL to official nixpkgs
#       (stable release; use the latest tag, e.g.):
#         https://github.com/NixOS/nixpkgs/archive/refs/tags/26.05.tar.gz
#       and remove the `overlays = [...]` below (and r-slim.nix/slim-r-overlay.nix).
# =============================================================================
let
  base = fetchTarball {
    url = "https://github.com/rstats-on-nix/nixpkgs/archive/2026-09-28.tar.gz";
    sha256 = "1bn5kv5vn78lcwdymaz8ggb7s5ywk6d3y5fkdaya9b1bwp8vz8s4";
  };
in
  import base { overlays = [ (import ./slim-r-overlay.nix) ]; }
