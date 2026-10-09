# AGENTS.md — Nix-bitcoin Flake Configuration

## Overview

Flake-based NixOS system configuration using [nix-bitcoin](https://github.com/fort-nix/nix-bitcoin) for running a Bitcoin Core + LND node.

> **nix-bitcoin is archived and unmaintained as of 2026-08-13.** v0.0.139 is the
> final release; there will be no further updates or security fixes from that
> project. This flake pins the tag `github:fort-nix/nix-bitcoin/v0.0.139`
> (commit `37931e52881956c7d6ace2f56415f54b012000a1`).
>
> Note: GitHub's REST API still reports `archived: false` for that repo (the
> Archive button was never pressed). The README warning is the authoritative
> signal, so do not use the API field to judge maintenance status.
>
> Because upstream is frozen, `inputs.nixpkgs` deliberately does **not** follow
> nix-bitcoin's nixpkgs. See the Flakes-first note in Code Style Guidelines.

**Repository structure:**
```
nix-bitcoin-flake/
├── flake.nix                  # Flake inputs + nixosSystem output builder
├── configuration.nix         # User NixOS config ( imports hardware-configuration.nix)
├── hardware-configuration.nix # Auto-generated hardware config (do not edit)
├── flake.lock               # Locked dependencies
├── docs/dev/                 # Implementation plans
└── .gitignore               # `result` and friends (build symlinks)
```

**Active services:** bitcoind, lnd, electrs, mempool (backend + frontend), rtl,
mysql, tor, tailscale, albyhub (hand-written unit). clightning and liquidd are
disabled.

**Known-broken intent:** `services.bitcoind.rpc.address` is left at its default
`127.0.0.1`, so the Bitcoin Core RPC port 8332 is not reachable over Tailscale.
Setting `rpcbind` in `extraConfig` does *not* work: `rpcbind` is a scalar option
and the first value in `bitcoin.conf` wins, which is nix-bitcoin's.

## Build / Eval Commands

### Evaluate the configuration
```bash
# Evaluate system config (check for errors)
nix eval .#nixosConfigurations.nixbit.config.system.build.toplevel

# Evaluate a specific option
nix eval .#nixosConfigurations.nixbit.config.services.bitcoind --json

# Package versions actually shipped by each service: bitcoin/lnd/electrs/rtl/
# mempool come from config.nix-bitcoin.pkgs (nix-bitcoin pins some of them),
# everything else from pkgs.
nix eval --impure --json --expr '
let c = builtins.getFlake (toString ./.);
    nbp = c.nixosConfigurations.nixbit.config.nix-bitcoin.pkgs;
in { lnd = nbp.lnd.version; bitcoin = nbp.bitcoin.version; rtl = nbp.rtl.version;
     nginx = c.nixosConfigurations.nixbit.pkgs.nginx.version; }'
```

### Build and apply
```bash
# Dry-run / type-check (always run this first!)
sudo nixos-rebuild dry-activate --flake .#nixbit

# Apply (build and activate - use this!)
sudo nixos-rebuild switch --flake .#nixbit

# Build only (no switch)
nixos-rebuild build --flake .#nixbit

# Check formatting (alejandra, wired up as flake.formatter)
nix fmt --check
```

### Remote deployment (build locally, push to nixbit)
`cody` is a nix trusted-user on nixbit, so closures can be pushed without root.
Resolve the store path explicitly rather than relying on the `./result`
symlink, so a stale build output cannot be pushed by accident:

```bash
# Build (--no-link skips creating ./result; --print-out-paths gives us the
# closure path, so a stale build output cannot be pushed by accident)
Toplevel=$(nix build --no-link --print-out-paths \
  .#nixosConfigurations.nixbit.config.system.build.toplevel)

# Push closure to nixbit
nix copy --to ssh://cody@nixbit "$Toplevel"

# Activate on nixbit (sudo over ssh)
ssh -t cody@nixbit "sudo $Toplevel/bin/switch-to-configuration switch"
```

Do not pass a bare store path to `nix build`: `nix build /nix/store/...` fails
with a dont-know-how-to-build error. Build the flake attribute, as above.

A new kernel only takes effect after a reboot:
`ssh -t cody@nixbit 'sudo reboot'`, then verify with
`ssh cody@nixbit 'nixos-version; uname -r; systemctl --failed'`.

### Build a single test (if available in upstream nix-bitcoin)
```bash
# Run tests from nix-bitcoin project (not this flake)
cd /path/to/nix-bitcoin
nix build .#checks.x86_64-linux.default

# Or run a specific test
nix build .#checks.x86_64-linux.testClightning --show-trace
```

### Nixel commands (removed — upstream gone, not in nixpkgs)
`nixel` was nix-bitcoin's service-enabling wrapper. Upstream is gone and it is
not in nixpkgs, so these commands no longer work. Enable services with the
module options directly, e.g. `services.bitcoind.enable = true;`.

## Formatting / Linting

### Format all .nix files
```bash
# Using alejandra (idempotent, no-conflict formatting)
nix fmt

# Or directly
alejandra .
```

### Check formatting
```bash
alejandra --check *.nix
```

### Lint with statix
```bash
# Fix issues (preview first)
nix run nixpkgs#statix -- check .

# Apply fixes
nix run nixpkgs#statix -- fix --mode=clippy .
```

### Validate flake schema
```bash
nix flake metadata .
```

## Code Style Guidelines

### General Conventions

- **Flakes-first**: Always use flakes. No channels or niv.
- **Do not re-pin nixpkgs to nix-bitcoin.** `inputs.nixpkgs.url` intentionally
  points at `github:NixOS/nixpkgs/nixos-26.05` instead of following
  `nix-bitcoin/nixpkgs`, because nix-bitcoin is archived and its pin is frozen
  at a 2026-08-09 revision. Following it would silently stop this machine from
  receiving kernel, nginx, tor, tailscale and mariadb security backports.
  nix-bitcoin's overlay still pins the bitcoin-stack packages it owns and pulls
  lnd from its own frozen `nixpkgs-unstable`, so nothing else changes. Bump the
  explicit branch when `nixos-26.11` is cut.
- **Template structure**: Edit `flake.nix` for flake settings, `configuration.nix` for system config.
- **Hardware config**: Never edit `hardware-configuration.nix` manually — regenerate with `nixos-generate-config`.
- **State version**: Set `stateVersion` to the NixOS release (e.g., `"25.11"`).

### Nix Language Style

- **Formatter**: `alejandra` (idempotent, no-conflict). Run `nix fmt` before committing.
- **Indentation**: 2 spaces.
- **Attribute ordering**: Logical — imports first, then options, then values.
- **Imports**: Single `imports = []` block at top of module.
- **Package references**: Use `with pkgs;` for lists, prefer `pkgs.<package>` for single references.
- **Quotes**: Double quotes for strings; single quotes only for paths/needs evaluation.
- **Error handling**: No `|| true` or silent failures. Nix is declarative — fail loudly with clear errors.
- **Assertions**: Use `lib.asserts` for validation, not `|| abort`.

### Naming Conventions

- **Option names**: `lowerCamelCase` (NixOS standard).
- **File names**: `kebab-case.nix` for modules.
- **Host names**: `nixbit` (as defined in flake.nix). Change if desired.
- **Service names**: Follow nix-bitcoin conventions (e.g., `services.bitcoind`, `services.clightning`).

### Nixpkgs Usage

- **Package sets**: Always reference via `pkgs.<name>`.
- **Unfree packages**: If needed, set `nixpkgs.config.allowUnfree = true` in configuration.nix.
- **Overlays**: Define in `flake.nix` if custom packages required.

### Module System

- **Module args**: Use `{ config, lib, pkgs, ... }` as function signature.
- **Enable toggles**: Services have their own `.enable` option (e.g., `services.bitcoind.enable`).
- **Secrets**: Use `nix-bitcoin.generateSecrets = true` for auto-generating secrets, or manage manually in `/etc/nix-bitcoin-secrets`.

### nix-bitcoin Specific

- **Standard services**: `services.bitcoind`, `services.clightning`, `services.lnd`, `services.electrs`, `services.mempool`, `services.rtl`.
- **Operator**: Set `nix-bitcoin.operator` to enable bitcoin-cli access for user.
- **Presets**: Optionally use `nix-bitcoin modules/presets/secure-node.nix` for enhanced security.
- **Testing**: Run `nixos-rebuild test` in a VM before production deployments.

### Packages frozen at nix-bitcoin's last release

These cannot be updated by `nix flake update` — nix-bitcoin builds or pins them
itself and is archived. Verified on 2026-10-08:

| Service | Version | Latest upstream | Updatable? |
|---|---|---|---|
| rtl | 0.15.8 | 0.15.13 | No `package` option; needs a vendored build. Missing GHSA-wj92-jhwh-85j5 (fixed in 0.15.12) |
| mempool | 3.2.1 | 3.3.1 | No — NAPI/rust-gbt build, not vendorable |
| electrs | 0.11.0 | 0.12.0 | No `package` option |
| lnd | 0.21.1-beta | 0.21.4-beta | `services.lnd.package` exists, but only nixpkgs-unstable has a newer build |

`bitcoind`, `albyhub`, `nginx`, `tor`, `mariadb`, `tailscale` and the base OS all
come from our own `nixpkgs` input and track `nixos-26.05` normally.

### Alby Hub (no upstream module)

Alby Hub is a hand-written `systemd.services.albyhub` unit in `flake.nix`, because
nix-bitcoin PR #794 proposed a module and was closed unmerged, and the project is
now archived. Points to watch when editing it:

- It runs as `cody` (not a system user) because it reads the LND macaroon from
  that user's data dir.
- `ProtectSystem = "strict"` requires `ReadWritePaths = ["/mnt/data/albyhub"]`,
  otherwise Alby Hub cannot write its SQLite DB. nix-bitcoin pairs these the same
  way (`modules/lnd.nix:263`, `modules/rtl.nix:222`).
- The service reaches LND over gRPC on `127.0.0.1:10009` and needs outbound
  network access, so do not add `IPAddressDeny` or a loopback-only
  `RestrictAddressFamilies`.

### Known issue: Alby Hub holds LND's admin macaroon

`LND_MACAROON_FILE` points at `admin.macaroon`, whose baked permissions are
unrestricted:

```
address:read/write  info:read/write  invoices:read/write  message:read/write
macaroon:read/write  macaroon:generate  offchain:read/write  onchain:read/write
peers:read/write  signer:generate  signer:read
```

That means anyone who compromises Alby Hub gets the whole node: send payments,
open/close channels, sign arbitrary messages, and — because of
`macaroon:generate` — mint themselves a *fresh* admin macaroon that survives
rotating this file. Alby Hub binds `0.0.0.0:8082` with the port open on every
interface, so it is reachable from the LAN and the tailnet. Alby Hub's own
authentication is irrelevant past that point: every action it performs runs with
admin rights.

Scope: Alby Hub's LND backend needs `invoices:read/write`, `offchain:read/write`
and `info:read`; it should not need `macaroon:generate`, `message:write`,
`peers:write` or `address:write`. A scoped macaroon can be baked with
`lncli bakemacaroon --macaroonperm ...`. Purpose-scoped macaroons already exist
on disk next to it (`invoice.macaroon`, `readonly.macaroon`).

Not yet done, deliberately: the exact permission set Alby Hub needs is inferred,
not tested, and switching macaroons means Alby's stored credentials change and
the NWC clients may need re-pairing. Treat it as its own change with a backup of
`/mnt/data/albyhub` and a close eye on `journalctl -u albyhub`.

## Adding Services

### Enable a new service

1. Add to the modules list in `flake.nix`:
   ```nix
   nix-bitcoin.nixosModules.<module-name>
   ```

2. Configure in the config block:
   ```nix
   services.<service>.enable = true;
   ```

3. Run `nix fmt` and `sudo nixos-rebuild dry-activate --flake .#nixbit`

### Common services

```nix
services.bitcoind.enable = true;
services.clightning.enable = true;
services.lnd.enable = true;
services.electrs.enable = true;
services.btcpayserver.enable = true;
```

Do **not** enable `services.joinmarket`: JoinMarket is archived upstream and was
removed from nix-bitcoin (issue #839, PR #850). Alby Hub is enabled the other
way round — via a hand-written `systemd.services.albyhub` unit in `flake.nix`,
because no upstream module exists (nix-bitcoin PR #794 was closed unmerged).

## Workflow Tips

- **Before committing**: Run `nix fmt`
- **Debugging**: Use `nix eval .#nixosConfigurations.nixbit.config.services.bitcoind.settings`
- **flake.lock**: Commit for reproducible builds. Update with `nix flake update`
- **Testing changes**: Always use `nixos-rebuild dry-activate` first
- **VM testing**: Use `nixos-rebuild test --flake .#nixbit` or test in a VM before production

## Security Notes

- **Secrets**: Never commit secrets. Use `nix-bitcoin.generateSecrets` or external secret management.
- **SSH**: Disable password auth in production. Use keys only.
- **Firewall**: Only open necessary ports (22 for SSH, 8333 for Bitcoin P2P).
- **Backups**: Backup seeds and keys externally. Don't rely solely on disk encryption.