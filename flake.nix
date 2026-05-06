{
  description = "nix-bitcoin node — nixbit VM";

  # Track the nix-bitcoin release branch; nixpkgs follows nix-bitcoin's pinned version
  # to ensure all bitcoin services use tested package versions.
  inputs.nix-bitcoin.url = "github:fort-nix/nix-bitcoin/release";
  inputs.nixpkgs.follows = "nix-bitcoin/nixpkgs";
  inputs.nixpkgs-unstable.follows = "nix-bitcoin/nixpkgs-unstable";

  outputs =
    {
      self,
      nixpkgs,
      nix-bitcoin,
      ...
    }:
    {
      nixosConfigurations.mynode = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          # nix-bitcoin service definitions and secret management
          nix-bitcoin.nixosModules.default

          # Optional: uncomment to apply the secure-node preset (tor, hardened SSH, etc.)
          # (nix-bitcoin + "/modules/presets/secure-node.nix")

          # Hardware + base system (unchanged from the running VM)
          ./hardware-configuration.nix
          ./configuration.nix

          # nix-bitcoin overlay — kept in a separate inline module so it is
          # clearly separated from the general system config.
          {
            # ---------------------------------------------------------------------------
            # nix-bitcoin secrets
            # ---------------------------------------------------------------------------
            # Auto-generate all secrets required by enabled services.
            # Secrets land in /etc/nix-bitcoin-secrets (root:root, mode 0400).
            nix-bitcoin.generateSecrets = true;

            # ---------------------------------------------------------------------------
            # Bitcoin services
            # ---------------------------------------------------------------------------
            services.bitcoind = {
              enable = true;
              # Store chain data on the dedicated disk mounted in hardware-configuration.nix
              dataDir = "/mnt/bitcoind-chain";
            };

            services.clightning.enable = true;

            # ---------------------------------------------------------------------------
            # Operator — gives `cody` access to bitcoin-cli, lightning-cli, etc.
            # without needing sudo.
            # ---------------------------------------------------------------------------
            nix-bitcoin.operator = {
              enable = true;
              name = "cody";
            };
          }
        ];
      };
    };
}
