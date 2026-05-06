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
            # LND — Lightning Network Daemon
            # Must be enabled before charge-lnd can work
            # Changed port to avoid conflict with clightning
            # Changed REST port to avoid conflict with mempool
            # ---------------------------------------------------------------------------
            services.lnd = {
              enable = true;
              port = 9736;
              restPort = 8081;
            };

            # ---------------------------------------------------------------------------
            # Electrum indexer — required by mempool explorer
            # ---------------------------------------------------------------------------
            services.electrs.enable = true;

            # ---------------------------------------------------------------------------
            # Web explorers and management interfaces
            # ---------------------------------------------------------------------------
            services.mempool = {
              enable = true;
              electrumServer = "electrs";
              # Bind to all interfaces
              address = "0.0.0.0";
              # Frontend nginx config
              frontend = {
                enable = true;
                address = "0.0.0.0";
                port = 8080;
              };
            };

            services.rtl = {
              enable = true;
              nodes.lnd.enable = true;
            };

            services.btcpayserver = {
              enable = true;
              # Lightning backend: "clightning" or "lnd"
              lightningBackend = "lnd";
            };

            # ---------------------------------------------------------------------------
            # Automated fee management for LND
            # ---------------------------------------------------------------------------
            services.charge-lnd.enable = true;

            # ---------------------------------------------------------------------------
            # Liquid sidechain
            # ---------------------------------------------------------------------------
            services.liquidd.enable = true;

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
