# =============================================================================
#  TO EDIT — here you choose LANGUAGES and tools. When done, rename:
#           nix/ToEdit_system.nix -> nix/system.nix
#  ---------------------------------------------------------------------------
#  WHAT TO CHANGE:
#    * Add a package (R, Python...) -> it does NOT go here: declare it in
#      nix/packages.nix, the single packages file for every language.
#    * Add a language (Julia, Rust...) -> add it to `inherit (pkgs) ...` at
#      the bottom, e.g. julia, rustup.
#    * Drop R -> remove `R` and the overlay in pkgs.nix (and r-slim.nix /
#      slim-r-overlay.nix); leave `rPackages` empty in nix/packages.nix.
# =============================================================================
# System layer: the slim R interpreter, locales, fonts and the tools a
# project needs (git, openssh for the dev sshd, quarto + pandoc to render,
# python + jupyter for python decks). Project PACKAGES (R and Python) live in
# nix/packages.nix, imported here for the Python ones.
# `pkgs` is a parameter so callers can pin it; the default keeps
# `nix-build nix/system.nix` (Dockerfile build stage) working unchanged.
{ pkgs ? import ./pkgs.nix }:
let
  # NOT built here: the pin already slims R via slim-r-overlay.nix (r-slim.nix),
  # so building another slim R would put two Rs in the image.
  inherit (pkgs) R;
  # All of the project's package declarations (R + Python), single file.
  packages = import ./packages.nix { inherit pkgs; };
  # The three packages quarto's jupyter engine actually runs (the `jupyter`
  # dispatcher, the kernel and the executor): machinery required regardless
  # of the project, which is why they live here. The project's own Python
  # packages come from nix/packages.nix (`pythonPackages`, a `ps: [...]`
  # function) and are appended below — never list them here, and never list
  # them against another Python version (that fails at import, not at build).
  python = pkgs.python312.withPackages (ps: [
    ps.ipykernel
    ps."jupyter-core"
    ps.nbconvert
    # quarto's jupyter engine (share/jupyter/jupyter.py) does `import yaml`;
    # without it a jupyter-engine qmd dies with ModuleNotFoundError: yaml.
    ps.pyyaml
  ] ++ packages.pythonPackages ps);
  # quarto.override, not quarto: nixpkgs' default wrapper bakes its OWN
  # rWrapper (a full, unstripped R + rmarkdown) and its OWN python with the
  # whole `jupyter` metapackage. Both are set to null so quarto uses the slim
  # R and the python above from PATH instead.
  # The overrideAttrs patches a nixpkgs packaging bug (nixpkgs#519484):
  # quarto 1.9.37 emits pandoc 3.8+'s `syntax-highlighting` option, but
  # nixpkgs bundles it against pandoc 3.7.0.2, which does not know it, so
  # `quarto render` of revealjs (and anything with highlighting) dies with
  # "Unknown option syntax-highlighting". Point the constant back at the 3.7
  # name until nixpkgs ships a matching pandoc.
  quarto = (pkgs.quarto.override { rWrapper = null; python3 = null; }).overrideAttrs (old: {
    postPatch = (old.postPatch or "") + ''
      substituteInPlace bin/quarto.js \
        --replace-fail 'kSyntaxHighlighting = "syntax-highlighting"' 'kSyntaxHighlighting = "highlight-style"'
    '';
  });
  # gitMinimal, not git.override: both drop perl, python, man pages and
  # pcre2 (~225 MB of runtime closure) that an ssh-only dev container does
  # not need, but a custom `git.override` changes the derivation hash, so it
  # is NOT on cache.nixos.org and git compiles from source (running its own
  # test suite). gitMinimal is a first-class package with the same flags, so
  # it is pre-built and downloads instead of compiling.
  git = pkgs.gitMinimal;
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
        # client's serverSetup script; procps gives the REH ps/kill for its
        # process management.
        patchelf
        gnused
        gawk
        gnugrep
        procps;
      # TO EDIT — main languages and tools. Add other languages here
      # (julia, rustup, ...) when you need them.
      inherit R python quarto git;
    };
  }
