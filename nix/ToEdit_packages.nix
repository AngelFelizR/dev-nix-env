# =============================================================================
#  TO EDIT — the project's PACKAGES, every language in one file. When done,
#           rename: nix/ToEdit_packages.nix -> nix/packages.nix
#  ---------------------------------------------------------------------------
#  WHAT TO CHANGE:
#    * R package (in the pin)     -> add a `pkgs.rPackages` name to `rPackages`.
#    * R package (only on GitHub) -> add an `(rFromGitHub { ... })` entry to
#      `rPackages` (helper below; fill owner/repo/rev/sha256/deps).
#    * Python package (in the pin) -> add a `python312Packages` name to
#      `pythonPackages` (a `ps: [...]` function: `ps` is the package set of
#      the interpreter chosen in nix/system.nix, so the two can never point
#      at different Python versions).
#    * Python package (only on GitHub) -> add a `(pythonFromGitHub ps { ... })`
#      entry to `pythonPackages` (helper below).
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
  # --- GitHub source packages (R and Python) --------------------------------
  # For a package the pin does not carry (or a specific GitHub revision of
  # one): build it from the source GitHub serves. Same rule as everything
  # else — declared in a versioned file, nothing installed inside the
  # container. Two things to know:
  #   * rev: prefer a TAG (reproducible); a branch or "latest" is not.
  #   * sha256: nix-prefetch-github <owner> <repo>
  #     (or: nix-prefetch-url --unpack https://github.com/<owner>/<repo>/archive/<rev>.tar.gz)
  # Nothing caches these builds: the FIRST build compiles them, later builds
  # are incremental like the rest of the environment.

  # R: compiled inside the Nix build, where the sandbox supplies the
  # toolchain (the runtime image itself has no compiler on PATH — see
  # nix/r-slim.nix), so C/C++/Fortran source packages work.
  #   pname defaults to the repo name (the R package name, what library()
  #   expects — pass pname = "pkgName" if the repo name differs). pname +
  #   version are what this nixpkgs' builder requires (`name` alone fails
  #   in stripDebugList); version defaults to rev (fine for tags "v1.2.3").
  #   deps: every dependency the package needs at load time that is NOT
  #   already in `rPackages` below (same names as CRAN, same pin).
  rFromGitHub = { owner, repo, rev, sha256, pname ? repo, version ? rev, deps ? [ ] }:
    pkgs.rPackages.buildRPackage {
      inherit pname version;
      src = pkgs.fetchFromGitHub { inherit owner repo rev sha256; };
      propagatedBuildInputs = deps;
    };

  # Python: buildPythonPackage wheels the source (no compiler needed for
  # pure-Python; C extensions build inside the sandbox like R's do).
  #   pyproject = true + setuptools/wheel is the modern path and also covers
  #   setup.py-only repos through setuptools' shim. A repo that insists on a
  #   bare setup.py build: pyproject = false.
  #   buildSystem: whatever the repo's pyproject [build-system] table demands
  #   (hatchling, setuptools-scm, ...). The build names the missing piece
  #   ("Unmet dependencies ... not installed") when it is absent.
  #   version defaults to rev (fine for tags like "v1.2.3").
  #   deps: runtime dependencies from the SAME `ps` package set.
  pythonFromGitHub =
    ps:
    { owner, repo, rev, sha256, version ? rev, deps ? [ ], pyproject ? true
    , buildSystem ? [ ps.setuptools ps.wheel ] }:
    ps.buildPythonPackage {
      pname = repo;
      inherit version pyproject;
      src = pkgs.fetchFromGitHub { inherit owner repo rev sha256; };
      build-system = buildSystem;
      propagatedBuildInputs = deps;
    };

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
    # TO EDIT — a package that only exists on GitHub (uncomment + fill in):
    # (rFromGitHub {
    #   owner = "OWNER";
    #   repo = "REPO";
    #   pname = "pkgName";     # R package name (library() name); defaults
    #                           # to the repo name
    #   rev = "v1.2.3";
    #   sha256 = "...";         # nix-prefetch-github OWNER REPO
    #   deps = [ dplyr ];       # deps not already in this list
    # })
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
    # TO EDIT — a package that only exists on GitHub (uncomment + fill in):
    # (pythonFromGitHub ps {
    #   owner = "OWNER";
    #   repo = "REPO";
    #   rev = "v1.2.3";
    #   sha256 = "...";         # nix-prefetch-github OWNER REPO
    #   deps = [ numpy ];       # runtime deps, same `ps` set
    # })
  ];

  # The R library environment built from `rPackages`: the image mounts it at
  # /opt/r (R_LIBS_SITE=/opt/r/library) and default.nix exposes it to
  # nix-shell the same way. Built with `nix-build nix/packages.nix -A rEnv`.
  rEnv = pkgs.buildEnv {
    name = "r-packages";
    paths = rPackages;
  };
}
