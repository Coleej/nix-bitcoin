# Standalone build of the vendored RTL package, used to resolve the
# node_modules fixed-output hash when bumping the version.
#
#   nix build -f pkgs/standalone-rtl.nix
#
# The first build of a new version fails with a mismatch that names the
# expected hash; paste it into pkgs/rtl.nix and rebuild.
#
# Note: <nixpkgs> here is whatever NIX_PATH resolves to, which may be newer
# than the nixos-26.05 this flake pins. Re-check the src hash if they diverge
# (the tarball is the same either way).
{pkgs ? import <nixpkgs> {}}:
pkgs.callPackage ./rtl.nix {
  fetchNodeModules = pkgs.callPackage ./fetch-node-modules.nix {};
}
