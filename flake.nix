{
  description = "nix-bitcoin node — nixbit VM";

  # nix-bitcoin is ARCHIVED and unmaintained as of 2026-08-13; v0.0.139 is its
  # final release and no further updates or security fixes will come from it.
  # Pin the tag rather than the `release` branch: both resolve to commit
  # 37931e52881956c7d6ace2f56415f54b012000a1 today, but the tag cannot be
  # moved or deleted out from under us.
  inputs.nix-bitcoin.url = "github:fort-nix/nix-bitcoin/v0.0.139";

  # nixpkgs deliberately does NOT follow nix-bitcoin. nix-bitcoin is archived
  # and its nixpkgs pin is frozen at a 2026-08-09 revision, which meant this
  # node stopped receiving security backports for the whole base system. The
  # bitcoin-stack packages are unaffected: nix-bitcoin's overlay still pins
  # them (pkgs/pinned.nix) while taking everything else from our pkgs, and it
  # pulls lnd/btcpayserver/fulcrum from its own frozen nixpkgs-unstable.
  # Tracking the supported stable branch keeps getting kernel, nginx, tor,
  # tailscale, mariadb and openssl fixes. Bump to nixos-26.11 when cut.
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

  outputs = {
    self,
    nixpkgs,
    nix-bitcoin,
    ...
  }: {
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
          {
            lib,
            pkgs,
            ...
          }: {
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
              # Without an outbound Tor proxy, bitcoind marks the onion
              # network as unreachable and refuses to register our onion
              # externalip as a local address (getnetworkinfo shows
              # "onion": {"reachable": false} and empty "localaddresses").
              tor.proxy = true;
              extraConfig = ''
                dbcache=450
                maxmempool=300
                maxconnections=40
                # Also bind RPC on the Tailscale interface so desktop wallets
                # (Sparrow) can connect over the encrypted tailnet. The
                # nix-bitcoin default rpcbind=127.0.0.1 stays in place;
                # rpcbind is additive. rpcallowip restricts RPC clients to
                # the Tailscale CGNAT range.
                rpcbind=100.94.170.33
                rpcallowip=100.64.0.0/10
              '';
            };

            # bitcoind binds RPC to the Tailscale IP, so make sure the
            # tailnet interface is up before bitcoind starts.
            systemd.services.bitcoind = {
              after = ["tailscaled.service"];
              wants = ["tailscaled.service"];
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
              # Needed to dial out to peers that only have an onion address
              # (roughly half the Lightning network). Inbound connections
              # over our own onion service work regardless of this setting.
              tor.proxy = true;
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
            # Alby Hub — Nostr Wallet Connect server.
            # No upstream NixOS module exists (nix-bitcoin PR #794 "albyhub: add
            # module" was closed unmerged, and nix-bitcoin is now archived), so
            # this unit stays hand-rolled. It runs as `cody` rather than a system
            # user because the LND macaroon it reads lives in the user's data dir.
            # ---------------------------------------------------------------------------
            systemd.services.albyhub = {
              description = "Alby Hub — Nostr Wallet Connect server for LND";
              wantedBy = ["multi-user.target"];
              after = ["lnd.service"];
              environment = {
                LN_BACKEND_TYPE = "LND";
                LND_ADDRESS = "127.0.0.1:10009";
                LND_CERT_FILE = "/etc/nix-bitcoin-secrets/lnd-cert";
                LND_MACAROON_FILE = "/mnt/data/lnd/chain/bitcoin/mainnet/admin.macaroon";
                PORT = "8082";
                WORK_DIR = "/mnt/data/albyhub";
                XDG_DATA_HOME = "/mnt/data/albyhub";
              };
              serviceConfig = {
                ExecStart = "${lib.getExe pkgs.albyhub}";
                User = "cody";
                WorkingDirectory = "/mnt/data/albyhub";
                # Required because ProtectSystem=strict below remounts the whole
                # hierarchy read-only. nix-bitcoin pairs these the same way
                # (modules/lnd.nix:263, modules/rtl.nix:222).
                ReadWritePaths = ["/mnt/data/albyhub"];
                Restart = "on-failure";
                RestartSec = "10";
                # Mirrors nix-bitcoin's defaultHardening profile (pkgs/lib.nix),
                # minus the directives that would block outbound network access.
                # ProtectHome is safe: the macaroon is under /mnt/data, not $HOME.
                PrivateTmp = true;
                ProtectSystem = "strict";
                ProtectHome = true;
                NoNewPrivileges = true;
                ProtectKernelTunables = true;
                ProtectKernelModules = true;
                ProtectKernelLogs = true;
                ProtectControlGroups = true;
                ProtectClock = true;
                ProtectProc = "invisible";
                ProcSubset = "pid";
                LockPersonality = true;
                RemoveIPC = true;
                RestrictSUIDSGID = true;
                RestrictRealtime = true;
                SystemCallArchitectures = "native";
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
