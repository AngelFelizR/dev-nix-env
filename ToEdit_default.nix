# Private dev shell, runnable inside the container against the mounted repo:
#   nix-shell --run "quarto render"
# Baked as the Docker image's system + r-book closures, so this shell is
# instant; its real use is adding packages later: edit nix/r-book.nix and
# `nix-shell` builds only what is missing.
#
# TO EDIT — only if you change the language scope:
#   - if your project does not use R, remove the `rBook` line and the two that
#     use it.
# When done, rename: ToEdit_default.nix -> default.nix
let
  pkgs = import ./nix/pkgs.nix;
  systemPackages = import ./nix/system.nix { inherit pkgs; };
  rBook = import ./nix/r-book.nix { inherit pkgs; };
in {
  shell = pkgs.mkShell {
    R_LIBS_SITE = "${rBook}/library";
    R_PROFILE = "${./Rprofile.site}";
    buildInputs = [ systemPackages rBook ];
    LOCALE_ARCHIVE =
      if pkgs.stdenv.hostPlatform.system == "x86_64-linux"
      then "${pkgs.glibcLocales}/lib/locale/locale-archive"
      else "";
    LANG = "en_US.UTF-8";
    LC_ALL = "en_US.UTF-8";
    LC_TIME = "en_US.UTF-8";
    LC_MONETARY = "en_US.UTF-8";
    LC_PAPER = "en_US.UTF-8";
    LC_MEASUREMENT = "en_US.UTF-8";
    FONTCONFIG_FILE = "${pkgs.fontconfig.out}/etc/fonts/fonts.conf";
    FONTCONFIG_PATH = "${pkgs.fontconfig.out}/etc/fonts/";
    shellHook = ''
      export XDG_DATA_DIRS="${pkgs.dejavu_fonts}/share:${pkgs.freefont_ttf}/share:$XDG_DATA_DIRS"
      fc-cache -f 2>/dev/null || true
    '';
  };
}
