# AGENTS.md — Nix-bitcoin Flake Configuration

## Overview

Flake-based NixOS system configuration using [nix-bitcoin](https://github.com/fort-nix/nix-bitcoin) for running Bitcoin Core and c-lightning nodes.

**Repository structure:**
```
nix-bitcoin-flake/
├── flake.nix                  # Flake inputs + nixosSystem output builder
├── configuration.nix         # User NixOS configuration ( imports hardware-configuration.nix)
├── hardware-configuration.nix # Auto-generated hardware config (do not edit)
└── flake.lock               # Locked dependencies
```

## Build / Eval Commands

### Evaluate the configuration
```bash
# Evaluate system config (check for errors)
nix eval .#nixosConfigurations.mynode.config.system.build.toplevel --json

# Evaluate a specific option
nix eval .#nixosConfigurations.mynode.config.services.bitcoind --json
```

### Build and apply
```bash
# Dry-run / type-check (always run this first!)
sudo nixos-rebuild dry-activate --flake .#mynode

# Apply (build and activate - use this!)
sudo nixos-rebuild switch --flake .#mynode

# Build only (no switch)
nixos-rebuild build --flake .#mynode

# Test configuration syntax without building
nix fmt --check .
```

### Build a single test (if available in upstream nix-bitcoin)
```bash
# Run tests from nix-bitcoin project (not this flake)
cd /path/to/nix-bitcoin
nix build .#checks.x86_64-linux.default

# Or run a specific test
nix build .#checks.x86_64-linux.testClightning --show-trace
```

### Nixel commands (optional wrapper)
```bash
# If nixel is installed
nixel list
nixel search bitcoind
nixel enable bitcoind
```

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
- **Host names**: `mynode` (as defined in flake.nix). Change if desired.
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

- **Standard services**: `services.bitcoind`, `services.clightning`, `services.lnd`, `services.electrs`.
- **Operator**: Set `nix-bitcoin.operator` to enable bitcoin-cli access for user.
- **Presets**: Optionally use `nix-bitcoin modules/presets/secure-node.nix` for enhanced security.
- **Testing**: Run `nixos-rebuild test` in a VM before production deployments.

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

3. Run `nix fmt` and `sudo nixos-rebuild dry-activate --flake .#mynode`

### Common services

```nix
services.bitcoind.enable = true;
services.clightning.enable = true;
services.lnd.enable = true;
services.electrs.enable = true;
services.btcpayserver.enable = true;
services.joinmarket.enable = true;
```

## Workflow Tips

- **Before committing**: Run `nix fmt`
- **Debugging**: Use `nix eval .#nixosConfigurations.mynode.config.services.bitcoind.settings`
- **flake.lock**: Commit for reproducible builds. Update with `nix flake update`
- **Testing changes**: Always use `nixos-rebuild dry-activate` first
- **VM testing**: Use `nixos-rebuild test --flake .#mynode` or test in a VM before production

## Security Notes

- **Secrets**: Never commit secrets. Use `nix-bitcoin.generateSecrets` or external secret management.
- **SSH**: Disable password auth in production. Use keys only.
- **Firewall**: Only open necessary ports (22 for SSH, 8333 for Bitcoin P2P).
- **Backups**: Backup seeds and keys externally. Don't rely solely on disk encryption.