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
      nixosConfigurations.nixbit = nixpkgs.lib.nixosSystem {
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
          (
            { pkgs, ... }:
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
                # Was outbound-only (listen=false is the nix-bitcoin default) —
                # accept inbound peer connections too, announced via the Tor
                # onion service below.
                listen = true;
                extraConfig = ''
                  dbcache=450
                  maxmempool=300
                  maxconnections=40
                '';
              };

              services.clightning = {
                enable = false;
                dataDir = "/mnt/data/clightning";
              };

              # ---------------------------------------------------------------------------
              # LND — Lightning Network Daemon
              # Must be enabled before charge-lnd can work
              # Changed port to avoid conflict with clightning
              # Changed REST port to avoid conflict with mempool
              # ---------------------------------------------------------------------------
              services.lnd = {
                enable = true;
                dataDir = "/mnt/data/lnd";
                port = 9735;
                restPort = 8081;
              };

              # ---------------------------------------------------------------------------
              # Tor — gives bitcoind and LND a stable external address to
              # announce to peers. The node sits behind NAT on a dynamic
              # residential IP, so onion services (rather than clearnet
              # port-forwarding) are the addresses nix-bitcoin can maintain
              # without router changes. Traffic arrives over Tor via loopback,
              # so both daemons stay bound to 127.0.0.1 (their defaults).
              # ---------------------------------------------------------------------------
              services.tor = {
                enable = true;
                client.enable = true;
              };
              nix-bitcoin.onionServices = {
                bitcoind.public = true;
                lnd.public = true;
              };

              # ---------------------------------------------------------------------------
              # Electrum indexer — required by mempool explorer
              # ---------------------------------------------------------------------------
              services.electrs = {
                enable = true;
                dataDir = "/mnt/data/electrs";
              };

              # ---------------------------------------------------------------------------
              # Web explorers and management interfaces
              # ---------------------------------------------------------------------------
              services.mempool = {
                enable = true;
                electrumServer = "electrs";
                address = "0.0.0.0";
                frontend = {
                  enable = true;
                  address = "0.0.0.0";
                  port = 8080;
                };
              };
              
	      # Increase memory b/c mempool was crashing OOM cache restore after reboot
	      systemd.services.mempool.environment = {
  		NODE_OPTIONS = "--max-old-space-size=4096";
	      };

              services.mysql.dataDir = "/mnt/data/mysql";

              services.rtl = {
                enable = true;
                dataDir = "/mnt/data/rtl";
                nodes.lnd.enable = true;
                address = "0.0.0.0";
                port = 3000;
              };

              # ---------------------------------------------------------------------------
              # Liquid sidechain (disabled - saves ~2-4GB RAM)
              # ---------------------------------------------------------------------------
              # services.liquidd = {
              #   enable = true;
              #   dataDir = "/mnt/data/liquidd";
              # };

              # ---------------------------------------------------------------------------
              # Alby Hub — Nostr Wallet Connect server
              # ---------------------------------------------------------------------------
              systemd.services.albyhub = {
                wantedBy = [ "multi-user.target" ];
                after = [ "lnd.service" ];
                script = ''
                                    export LN_BACKEND_TYPE=LND
                                    export LND_ADDRESS=127.0.0.1:10009
                                    export LND_CERT_FILE=/etc/nix-bitcoin-secrets/lnd-cert
                                    export LND_MACAROON_FILE=/mnt/data/lnd/chain/bitcoin/mainnet/admin.macaroon
                                    export PORT=8082
                  export WORK_DIR=/mnt/data/albyhub
                                  export XDG_DATA_HOME=/mnt/data/albyhub
                                    exec ${pkgs.albyhub}/bin/albyhub
                '';
                serviceConfig = {
                  User = "cody";
                  Restart = "on-failure";
                  RestartSec = "10";
                };
              };

              systemd.tmpfiles.rules = [
                "d /mnt/data/albyhub 0755 cody users"
              ];

              # ---------------------------------------------------------------------------
              # Operator — gives `cody` access to bitcoin-cli, lightning-cli, etc.
              # without needing sudo.
              # ---------------------------------------------------------------------------
              nix-bitcoin.operator = {
                enable = true;
                name = "cody";
              };

              # ---------------------------------------------------------------------------
              # Tools for bitcoing
              # ---------------------------------------------------------------------------
              nix-bitcoin.nodeinfo.enable = true;

              # ---------------------------------------------------------------------------
              # Backups
              # ---------------------------------------------------------------------------
              services.backups = {
                enable = true;
                destination = "file:///mnt/data/backups";
                frequency = "daily";
                # with-bulk-data = true;  # uncomment to include blockchain data
              };
            }
          )
        ];
      };
    };
}
