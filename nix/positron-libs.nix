# FHS-ish lib dir for Positron Remote SSH: the REH launcher patchelfs its
# bundled node against /opt/positron-libs (glibc + libstdc++ + libgcc_s
# symlinked flat).
#
# (Do not edit — generic.) This file replaces the version globs that lived in
# the Dockerfile (*-glibc-2.44-25, *-gcc-16.2.0-lib, ...), which broke on every
# pin bump. The paths now come from the pin itself, so changing the date in
# nix/pkgs.nix updates them automatically.
{ pkgs ? import ./pkgs.nix }:
pkgs.runCommand "positron-libs" { } ''
  mkdir -p $out
  for f in ld-linux-x86-64.so.2 libc.so.6 libm.so.6 libdl.so.2 \
           libpthread.so.0 librt.so.1 libutil.so.1 libresolv.so.2; do
    ln -s ${pkgs.glibc}/lib/$f $out/
  done
  ln -s ${pkgs.stdenv.cc.cc.lib}/lib/libstdc++.so.6 $out/
  ln -s ${pkgs.stdenv.cc.cc.libgcc}/lib/libgcc_s.so.1 $out/
''
