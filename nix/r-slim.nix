# R with the build toolchain stripped out of its output.
#
# (DO NOT TOUCH — advanced logic: it stops R from dragging JDK/compilers into
# the image. You only need to know it exists and is applied via the overlay in
# slim-r-overlay.nix.)
#
# Why this file exists: R's derivation is built WITH openjdk, gcc, gfortran
# and the glib development headers, and it writes absolute store paths to them
# into the files it ships. Nix therefore considers them part of every closure
# that contains R -- 1,340 MB of JDK and compilers travelling inside a runtime
# image (measured: openjdk 573, gfortran 339, gcc 284, glib-dev -> python3
# 144). None of them is needed to RUN R, and nothing in this repository
# compiles an R package: the two packages that exist are pure R, and
# Rprofile.site (shipped as R_PROFILE) blocks install.packages() by design.
#
# WHAT IS DONE TO WHICH REFERENCE, AND WHY THEY ARE NOT ALL TREATED THE SAME
#
#   openjdk, glib-dev, cairo-dev, pango-dev, graphviz
#       blanked with remove-references-to. Nothing needs them at run time and
#       nothing can need them at build time: glib-dev/cairo-dev/pango-dev are
#       the path that used to drag python3 into the closure, and openjdk is the
#       single largest item of all (573 MB). The same tool removes their
#       references from the four text files listed below, and etc/javaconf is
#       deleted outright.
#
#   gcc-wrapper
#       REWRITTEN to the bare command name, not blanked. `CC` becomes `cc`,
#       `CXX` becomes `c++`. That is what keeps `R CMD INSTALL` working inside
#       a Nix build -- stdenv puts `cc` on PATH -- while the reference to the
#       store path disappears. Verified: with the blanked form
#       (`/nix/store/eeee...-gcc-wrapper/bin/cc`) `R CMD SHLIB` dies with
#       "No such file or directory"; with the bare name the same command
#       produces a 16 KB .so. gcc (the unwrapped output, 284 MB) goes with it.
#
#   gfortran
#       deliberately NOT rewritten: `FC` and `F77` keep the full store path,
#       so gfortran (339 MB) stays in every image that contains R. Not for
#       want of trying. nixpkgs' builder is
#       `buildRPackage = pkgs.callPackage ./generic-builder.nix { inherit R; }`
#       and generic-builder.nix puts `[ R ]` in nativeBuildInputs but declares
#       no gfortran, so the only reason `FC = gfortran` ever resolved was that
#       the store path in Makeconf put gfortran in R's closure -- and hence in
#       every sandbox that depended on R. Rewriting FC to the bare name was
#       measured to break every Fortran package (`rPackages.KernSmooth` fails
#       with "gfortran: command not found" while `rPackages.glue`, pure C,
#       builds). Three ways of re-supplying it were tried and measured:
#       `propagatedNativeBuildInputs` on R does not reach the packages; a list
#       of Fortran packages in an overlay only fixes direct references, so
#       `classInt` still built its own unpatched `KernSmooth` and failed; and
#       `rPackages.overrideScope` does not exist in this nixpkgs at all
#       (`rPackages` is `recurseIntoAttrsWith (callPackage ...)`, not a scope).
#       Paying 339 MB is cheaper than owning a patched nixpkgs.
#
#   openjdk, glib-dev, cairo-dev, pango-dev, graphviz
#       blanked with remove-references-to. Nothing needs them at run time and
#       nothing can need them at build time: glib-dev/cairo-dev/pango-dev are
#       the path that used to drag python3 into the closure, and openjdk is the
#       single largest item of all (573 MB). The same tool removes their
#       references from the four text files listed below, and etc/javaconf is
#       deleted outright.
#
# The consequence to know about: `R CMD INSTALL` can no longer compile outside
# a Nix build, because there is no compiler on PATH. That is acceptable here
# and is recorded in ADR-0011/ADR-0016: our packages are pure R and
# `Rprofile.site` refuses install.packages() anyway. INSIDE a Nix build it still
# compiles, which is what nixpkgs' own rPackages need.
#
# `remove-references-to -t <store-path> <file>...` rewrites the 32-character
# store id inside exactly the files named, so no shared object or binary is
# rewritten by accident.
#
# `pkgs` is REQUIRED and must be the unoverlaid set: this reads `pkgs.R`, so
# an already-slimmed set would recurse. nix/slim-r-overlay.nix is the only
# caller that matters, and it passes `prev`.
{ pkgs }:
let
  # Store paths of the compiler pieces this strip must remove, regex-escaped
  # so they can be injected into sed as literal patterns. Computing them from
  # the pin (instead of regex-matching version numbers like
  # "gcc-wrapper-[0-9]" / "gcc-[0-9]+(\.[0-9]+)*") means a pin bump can no
  # longer silently break the strip.
  esc = s: builtins.replaceStrings [ "." "+" ] [ "\\." "\\+" ] s;
  ccWrapper = esc (builtins.toString pkgs.stdenv.cc);   # gcc-wrapper
  gccOut = esc (builtins.toString pkgs.stdenv.cc.cc);   # gcc unwrapped
in
  pkgs.R.overrideAttrs (old: {
    nativeBuildInputs = (old.nativeBuildInputs or []) ++ [ pkgs.removeReferencesTo ];
    postFixup = (old.postFixup or "") + ''
      chmod -R u+w $out
      makeconf=$out/lib/R/etc/Makeconf
      ldpaths=$out/lib/R/etc/ldpaths
      libtool=$out/lib/R/bin/libtool

      # 1. The gcc wrapper becomes a bare command (CC = .../bin/cc -> CC = cc).
      #    [^[:space:]"]+ takes the tool name and stops at the space before any
      #    flags (`CXX = .../bin/c++ -std=gnu++20`) or at the closing quote
      #    libtool puts around its assignments. The gfortran wrapper is NOT
      #    here -- see the note at the top. ${ccWrapper} is the literal
      #    gcc-wrapper store path from the pin (escaped), so no version is
      #    guessed.
      for f in "$makeconf" "$ldpaths" "$libtool"; do
        sed -E -i "s|${ccWrapper}/bin/([^[:space:]\"]+)|\1|g" "$f"
      done

      # 2. gcc unwrapped only ever appears as an -L search path. Because the
      #    pattern is the literal ${gccOut} path, it can never match
      #    `...-gcc-<ver>-lib` / `...-libgcc`, which must survive -- libgcc_s.so
      #    / libstdc++ live there. `#` is the sed delimiter because the pattern
      #    contains `/`.
      sed -E -i "s#-L${gccOut}/[^[:space:]\"]*##g" "$makeconf"
      sed -E -i "s#${gccOut}/[^:[:space:]\"]+:?##g" "$ldpaths"
      sed -E -i "s#${gccOut}/[^[:space:]\"]*##g" "$libtool"

      remove-references-to \
        -t ${pkgs.openjdk} \
        -t ${pkgs.glib.dev} \
        -t ${pkgs.cairo.dev} \
        -t ${pkgs.pango.dev} \
        -t ${pkgs.graphviz} \
        "$makeconf" "$ldpaths" "$libtool" \
        $out/lib/R/etc/javaconf
      rm -f $out/lib/R/etc/javaconf
    '';
  })
