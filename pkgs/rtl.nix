# RTL (Ride The Lightning) 0.15.13
#
# Adapted from nix-bitcoin (MIT, fort-nix/nix-bitcoin v0.0.139,
# pkgs/rtl/default.nix), which is frozen at 0.15.8 because that project is
# archived. 0.15.13 includes the fix for GHSA-wj92-jhwh-85j5 and the wider
# authentication-guard hardening shipped in 0.15.12:
#
#   "Every state-changing route now carries the authentication guard, enforced
#    by a test that walks the route tree (#1688)"
#
# Upstream: https://github.com/Ride-The-Lightning/RTL (MIT)
#
# Once this builds cleanly, the upgrade procedure for future releases is:
#   1. bump `version` below
#   2. nix-prefetch-url --unpack \
#        https://github.com/Ride-The-Lightning/RTL/archive/refs/tags/v<VERSION>.tar.gz
#   3. nix build -f default.nix rtl    -> read the expected node_modules hash
#      out of the error and paste it in
# See docs/dev/upgrade-plan-nix-bitcoin-archive.md
{
  lib,
  stdenvNoCC,
  nodejs_22,
  nodejs-slim_22,
  fetchNodeModules,
  fetchurl,
  makeWrapper,
}: let
  self = stdenvNoCC.mkDerivation {
    pname = "rtl";
    version = "0.15.13";

    src = fetchurl {
      url = "https://github.com/Ride-The-Lightning/RTL/archive/refs/tags/v${self.version}.tar.gz";
      hash = "sha256-3buB9owSQOYlNH42w6jPbu5uEgCO1ikBQHOBVHgK3Qk=";
    };

    passthru = {
      nodejs = nodejs_22;
      nodejsRuntime = nodejs-slim_22;

      nodeModules = fetchNodeModules {
        inherit (self) src nodejs;
        # Still required at 0.15.13: plain `npm ci` fails with ERESOLVE.
        # nix-bitcoin's original file carries a TODO-EXTERNAL to drop this,
        # and upstream issue 1182 is the reference.
        npmFlags = "--legacy-peer-deps";
        hash = "sha256-dFnOTtpSzz9CXvs7I50CTi6p5HS/cbxBSJHJh2pqcLc=";
      };
    };

    nativeBuildInputs = [makeWrapper];

    phases = "unpackPhase patchPhase installPhase";

    # `src` already contains the precompiled frontend and backend.
    # Copy all files required for packaging, like in
    # https://github.com/Ride-The-Lightning/RTL/blob/master/dockerfiles/Dockerfile
    installPhase = ''
      dest=$out/lib/node_modules/rtl
      mkdir -p $dest
      cp -r \
        rtl.js \
        package.json \
        frontend \
        backend \
        ${self.nodeModules}/lib/node_modules \
        $dest

      makeWrapper ${self.nodejsRuntime}/bin/node "$out/bin/rtl" \
        --add-flags "$dest/rtl.js"

      runHook postInstall
    '';

    meta = with lib; {
      description = "A web interface for LND, c-lightning and Eclair";
      homepage = "https://github.com/Ride-The-Lightning/RTL";
      license = licenses.mit;
      platforms = platforms.unix;
    };
  };
in
  self
