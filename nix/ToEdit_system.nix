# =============================================================================
#  TO EDIT — here you choose LANGUAGES and tools. When done, rename:
#           nix/ToEdit_system.nix -> nix/system.nix
#  ---------------------------------------------------------------------------
#  WHAT TO CHANGE:
#    * Add a Python package -> add it to the `withPackages` list (below),
#      e.g. ps.numpy, ps.pandas.
#    * Add a language (Julia, Rust...) -> add it to `inherit (pkgs) ...` at
#      the bottom, e.g. julia, rustup.
#    * Drop R -> remove `R` and the overlay in pkgs.nix (and r-slim.nix /
#      slim-r-overlay.nix / r-book.nix).
# =============================================================================
# System layer: the slim R interpreter, locales, fonts and the tools a
# project needs (git, openssh for the dev sshd, quarto + pandoc to render,
# python + jupyter for python decks).
# `pkgs` is a parameter so callers can pin it; the default keeps
# `nix-build nix/system.nix` (Dockerfile build stage) working unchanged.
{ pkgs ? import ./pkgs.nix }:
let
  # NOT built here: the pin already slims R via slim-r-overlay.nix (r-slim.nix),
  # so building another slim R would put two Rs in the image.
  inherit (pkgs) R;
  # What quarto's jupyter engine actually runs: the `jupyter` dispatcher
  # (jupyter_core), the kernel (ipykernel) and the executor (nbconvert).
  #
  # TO EDIT — add your Python packages here, e.g.:
  #   ps.numpy
  #   ps.pandas
  python = pkgs.python312.withPackages (ps: [
    ps.ipykernel
    ps."jupyter-core"
    ps.nbconvert
  ]);
  # quarto.override, not quarto: nixpkgs' default wrapper bakes its OWN
  # rWrapper (a full, unstripped R + rmarkdown) and its OWN python with the
  # whole `jupyter` metapackage. Both are set to null so quarto uses the slim
  # R and the python above from PATH instead.
  quarto = pkgs.quarto.override { rWrapper = null; python3 = null; };
  # git.override, not git: the defaults carry perl, python and man pages
  # (~225 MB of runtime closure) an ssh-only dev container does not need.
  git = pkgs.git.override {
    perlSupport = false;
    pythonSupport = false;
    withManual = false;
  };
  # The same tarball nix/pkgs.nix fetchTarball's, shipped in the store so
  # the first `nix-shell` on a fresh container is instant instead of a
  # ~80 MB download. Same URL + sha256 => same store path => fetchTarball
  # finds it.
  # TO EDIT — if you change the pin date in nix/pkgs.nix, also change the
  # URL and sha256 below to match.
  nixpkgsSrc = builtins.fetchTarball {
    url = "https://github.com/rstats-on-nix/nixpkgs/archive/2026-10-13.tar.gz";
    sha256 = "0z41sx0as5b547gkzksaknpjxhkxc49xxyff94afkxy9hr43xrwy";
  };
  nixpkgsSource = pkgs.runCommand "nixpkgs-source" { } ''
    ln -s ${nixpkgsSrc} $out
  '';
in
  pkgs.buildEnv {
    name = "system-packages";
    paths = builtins.attrValues {
      inherit (pkgs)
        # glibcLocalesUtf8, not glibcLocales: the full archive holds every
        # locale glibc supports (223 MB) and nothing here can select one --
        # LANG/LC_ALL are pinned to en_US.UTF-8, which is the single entry
        # allLocales=false builds.
        glibcLocalesUtf8
        which
        curl
        openssh
        fontconfig
        dejavu_fonts
        freefont_ttf
        pandoc
        # zoneinfo for /etc/localtime: without it timechange (via lubridate,
        # loaded by tidymodels) warns "Your system is mis-configured" and
        # Sys.timezone() is NA.
        tzdata
        # Positron remote: the REH launcher patchelfs its bundled node with
        # these (VSCODE_SERVER_CUSTOM_GLIBC_* env). sed/awk are for the
        # client's serverSetup script.
        patchelf
        gnused
        gawk
        gnugrep;
      # TO EDIT — main languages and tools. Add other languages here
      # (julia, rustup, ...) when you need them.
      inherit R python quarto git nixpkgsSource;
    };
  }
