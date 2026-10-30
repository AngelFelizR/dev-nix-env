# =============================================================================
#  TO EDIT — the environment's R packages. When done, rename:
#           nix/ToEdit_r-book.nix -> nix/r-book.nix
#  ---------------------------------------------------------------------------
#  WHAT TO CHANGE:
#    * Replace the examples with the packages your project uses. Each entry is
#      a `pkgs.rPackages` name.
#  IMPORTANT: `install.packages()` does NOT work in this image (the "slim" R
#  ships no compiler on PATH). The only way is to list the package here and
#  rebuild with ./build-image.sh.
# =============================================================================
{ pkgs ? import ./pkgs.nix }:
  pkgs.buildEnv {
    name = "r-project-pkgs";
    paths = builtins.attrValues {
      inherit (pkgs.rPackages)
        # Quarto's engine for .qmd files with R chunks:
        rmarkdown
        knitr
        # TO EDIT — add your packages here, e.g.:
        # dplyr
        # tidymodels;
        ;
    };
  }
