# =============================================================================
#  TO EDIT — the project's PACKAGES, every language in one file. When done,
#           rename: nix/ToEdit_packages.nix -> nix/packages.nix
#  ---------------------------------------------------------------------------
#  WHAT TO CHANGE:
#    * R package     -> add a `pkgs.rPackages` name to `rPackages` below.
#    * Python package -> add a `python312Packages` name to `pythonPackages`
#      below (a `ps: [...]` function: `ps` is the package set of the
#      interpreter chosen in nix/system.nix, so the two can never point at
#      different Python versions).
#    * Another language (Julia, Rust...) -> add its section here once the
#      language itself is in nix/system.nix.
#  Then rebuild: ./build-image.sh  (or try it first with `nix-shell`, see
#  README: "Try a package without rebuilding the image").
#  IMPORTANT: install.packages()/pip install do NOT work in this image (the
#  "slim" R ships no compiler). Every package is declared here and built by
#  Nix — that is what keeps the environment reproducible.
# =============================================================================
{ pkgs ? import ./pkgs.nix }:
let
  # R packages of the project. Each entry is a `pkgs.rPackages` attribute.
  # R and this list always come from the same pin (nix/pkgs.nix), so unlike
  # Python there is no interpreter to keep in sync by hand.
  rPackages = with pkgs.rPackages; [
    # Quarto's engine for .qmd files with R chunks:
    rmarkdown
    knitr
    # TO EDIT — add your packages here, e.g.:
    # dplyr
    # tidymodels
  ];
in
{
  inherit rPackages;

  # Python packages of the project. `ps: with ps; [...]` (the nixpkgs idiom)
  # rather than a plain list of `pkgs.python312Packages`: with `ps` the set
  # is always the interpreter's own, so a python version change in
  # nix/system.nix can never leave stale packages here (that mismatch does
  # NOT fail at build time — it fails later as ModuleNotFoundError).
  # Attribute names containing a dash need quotes: "jupyter-core".
  pythonPackages = ps: with ps; [
    # TO EDIT — add your packages here, e.g.:
    # numpy
    # pandas
  ];

  # The R library environment built from `rPackages`: the image mounts it at
  # /opt/r (R_LIBS_SITE=/opt/r/library) and default.nix exposes it to
  # nix-shell the same way. Built with `nix-build nix/packages.nix -A rEnv`.
  rEnv = pkgs.buildEnv {
    name = "r-packages";
    paths = rPackages;
  };
}
