# The pkgs set: the pin's nixpkgs + this template's overlays.
#
# (Generic — NOT edited in the normal flow.) The pin (date + sha256) lives in
# nix/pin.nix; this file only applies it here plus the slim-R overlay. The ONE
# edit — for a Python-only project (README: "Python only (drop R)") — is
# removing the `overlays = [...]` line below and deleting nix/r-slim.nix +
# nix/slim-r-overlay.nix.

let
  pin = import ./pin.nix;
in
  # Single source: url + sha256 come straight from nix/pin.nix, the same file
  # nix/system.nix imports. Nothing here can drift from the pin; ./check
  # enforces that no other nix file carries a copy of the URL.
  import (fetchTarball { inherit (pin) url sha256; }) {
    overlays = [ (import ./slim-r-overlay.nix) ];
  }
