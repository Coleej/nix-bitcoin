# Implementation plan — modernize `nixbit` after the nix-bitcoin archive

- **Status:** ready for implementation (phases are ordered; each is independently deployable)
- **Written:** 2026-10-07
- **Repo:** `/home/cody/Projects/Nix/nix-bitcoin` (branch `main`, remote `git@github.com:Coleej/nix-bitcoin.git`)
- **Target host:** `nixbit` (VM; user `cody` is a nix trusted-user, so closures can be pushed without root)

---

## 1. Context

`nix-bitcoin` — the project this configuration is built on — is **archived and unmaintained**.

From the top of `master/README.md` (<https://github.com/fort-nix/nix-bitcoin>):

> [!WARNING]
> **Archived and unmaintained as of August 13, 2026.**
> v0.0.139 is the final release; there will be no further updates or security fixes.

Important detail: the GitHub REST API still reports `"archived": false` for `fort-nix/nix-bitcoin`
(the *Archive* button was never pressed). **Do not rely on the API flag** — the README warning is
the authoritative signal. A scripted check should grep the README for `Archived and unmaintained`.

Consequences for this flake:

1. The `release` branch and tag `v0.0.139` both point at commit
   `37931e52881956c7d6ace2f56415f54b012000a1` (NixOS 26.05 based). Nothing after it will ever ship.
2. Our lock is **not** at the final release: `flake.lock` pins nix-bitcoin
   `360e30fee5ba32f9fecc89bc35628195d9d2dbbe` (the old `nixos-25.11` branch head).
3. Because `flake.nix` sets `inputs.nixpkgs.follows = "nix-bitcoin/nixpkgs"`, the **entire OS
   package set** is pinned to nix-bitcoin's frozen nixpkgs revision
   (`b6018f87da91d19d0ab4cf979885689b469cdd41`, dated **2026-06-30**). No security backports have
   reached this node in over three months.

### What `nix-bitcoin` still gives us (do not lose this)

`generateSecrets` (macaroons/certs in `/etc/nix-bitcoin-secrets`), `onionServices` (wires `.onion`
addresses into bitcoind/lnd configs), `services.bitcoind.tor.proxy`, `nix-bitcoin.operator`,
`nix-bitcoin.nodeinfo`, `services.backups`, and the systemd hardening profile
(`pkgs/lib.nix → defaultHardening`) applied to every service.

Nixpkgs has **no** modules for lnd, mempool, RTL or electrs (only `services.bitcoind` and
`services.blockbook-frontend`). Migrating off nix-bitcoin would mean hand-writing four systemd
units plus manual secret management — explicitly out of scope. The plan keeps nix-bitcoin and
unfreezes everything it does not need to own.

---

## 2. Verified version deltas

All numbers below were produced by evaluating the actual `nixosSystem` (not by reading package
definitions). Reproduce with the probes in Appendix A.

### 2.1 Bitcoin-stack packages (served from `config.nix-bitcoin.pkgs`)

| Package | Current lock | nb `v0.0.139` + `follows` | nb `v0.0.139` + own nixpkgs | Upstream latest |
|---|---|---|---|---|
| bitcoind (`bitcoin`) | 31.0 | **31.1** | 31.1 | 31.1 ✅ |
| lnd | 0.21.1-beta | 0.21.1-beta | 0.21.1-beta | 0.21.4-beta (no security fixes in .2/.3/.4) |
| clightning (disabled) | 26.04.1 | 26.04.1 | 26.04.1 | 26.04.1 ✅ |
| electrs | 0.11.0 | 0.11.0 | 0.11.0 | 0.12.0 (2026-09-13) ⚠️ frozen |
| mempool | 3.2.1 (2025-04) | 3.2.1 | 3.2.1 | 3.3.1 (2026-04-21) ⚠️ frozen |
| rtl | 0.15.8 (2026-02) | 0.15.8 | 0.15.8 | 0.15.13 (2026-10-01) ⚠️ **frozen, security gap** |
| albyhub (plain nixpkgs pkg) | 1.20.0 | **1.22.2** | 1.22.2 | 1.24.1 (2026-10-06) |

Note: services use `config.nix-bitcoin.pkgs.*`, **not** `pkgs.*` (see `modules/lnd.nix:105-108`).
`nix-bitcoin.pkgs` is built from our `pkgs` for the pinned set and from
`pkgs/nixpkgs-pinned.nix` (nix-bitcoin's own frozen `nixpkgs-unstable`) for lnd/btcpayserver/fulcrum.

### 2.2 Base OS packages (served from `pkgs`)

| Package | Current lock (2026-06-30) | Plan (nixos-26.05, 2026-10-07) |
|---|---|---|
| kernel | 6.12.93 | **6.18.55** |
| glibc | 2.40 | 2.42 |
| openssl | 3.6.2 | 3.6.5 |
| systemd | 258.7 | 260.5 |
| curl | 8.20.0 | 8.22.0 |
| sudo | 1.9.17p2 | 1.9.17p2 |
| nginx | 1.28.3 | **1.30.5** |
| tor | 0.4.9.11 | **0.4.9.13** |
| mariadb | 11.4.8 | 11.4.12 |
| tailscale | 1.90.9 | 1.98.10 (latest upstream 1.104.1) |
| albyhub | 1.20.0 | 1.22.2 |
| nodejs | 22.22.2 | 24.x |

### 2.3 Concrete security findings

**nginx 1.28.3 (current) is knowingly vulnerable.** From <https://nginx.org/en/security_advisories.html>,
vulnerable in 1.28.3 and fixed by 1.30.3/1.30.4:

| CVE | Severity | Issue |
|---|---|---|
| CVE-2026-42533 | **major** | Buffer overflow when using `map` and regex |
| CVE-2026-60005 | medium | Memory disclosure in `ngx_http_slice_module` |
| CVE-2026-56434 | medium | Use-after-free in `ngx_http_ssi_module` |
| CVE-2026-42055 | medium | Buffer overflow in `ngx_http_proxy_v2_module` / `ngx_http_grpc_module` |
| CVE-2026-48142 | low | Buffer overread in `ngx_http_charset_module` |
| CVE-2026-42926 | medium | HTTP/2 request injection in `ngx_http_proxy_module` |
| CVE-2026-42945 / 42946 / 42934 | medium/medium/low | rewrite buffer overflow, scgi/uwsgi overread, charset overread |
| CVE-2026-40460 | medium | HTTP/3 address spoofing |
| CVE-2026-40701 | medium | Resolver use-after-free in OCSP |

CVE-2026-90439 (medium, HTTP/3 buffer overflow) additionally requires **1.30.5** — only the
Phase 2 configuration gets it. nix-bitcoin's generated mempool nginx config does not enable
HTTP/3, so practical exposure is low, but the code would be unpatched.

This matters because the mempool frontend serves nginx on `0.0.0.0:8080` and port 8080 is open on
every interface today.

**Kernel 6.12.93 → 6.18.55.** kernel.org lists **6.12.112** (2026-10-03) as the current 6.12.y
stable, i.e. ~19 stable releases of fixes are missing on the frozen rev.

**RTL 0.15.8 misses a published advisory.** RTL 0.15.12 (2026-09-08) release notes:

> "Every state-changing route now carries the authentication guard, enforced by a test that walks
> the route tree (#1688); this closes [GHSA-wj92-jhwh-85j5], an unauthenticated circular-rebalance
> call on Eclair nodes"

and it also allowlisted the application-settings save so an authenticated caller can no longer
re-point macaroon / rune / config paths or provision an unknown node. The named advisory is
Eclair-only (we run LND), but the auth-guard sweep is broader and we did not audit the full diff.
Our RTL is bound to `0.0.0.0:3000` with port 3000 open on every interface, and nix-bitcoin's
generated RTL config (`modules/rtl.nix:149-157`) contains only `multiPass`, `host`, `port`,
`SSO`, `nodes` — no `auth` block.

**No other frozen package has a published advisory.** Tailscale's newest GHSA is from 2023,
lnd's are 2022/2024 (both long fixed), and bitcoin/mempool/electrs/albyhub/nginx publish none
(release notes for mempool 3.3.0 contain only an `[auth] better handling of 'disabled' users`
change). `albyhub` 1.23.0+ release bodies were not retrievable (GitHub rate limit) — unverified,
not "clean".

---

## 3. Pre-flight checklist

- [ ] Confirm a rollback path: this is a VM, so also snapshot the disk or note how to re-attach
      a console if the firewall change in Phase 4 locks you out.
- [ ] Confirm `cody` can reach `nixbit` **over Tailscale** (needed for Phase 4).
- [ ] Back up before Phase 1:
      - `systemctl stop albyhub; tar czf ~/albyhub-backup.tgz -C /mnt/data albyhub`
      - `mariadb-dump -u root mempool > ~/mempool.sql` (or the credentials Alby uses)
      - `lncli chanbackup export --all` / copy `/mnt/data/lnd/data/chain/bitcoin/mainnet/channel.backup`
      - `bitcoin-cli -rpcuser=... -rpcpassword=... wallet backupwallet /mnt/data/…/wallet.bak`
- [ ] Read `AGENTS.md` deploy section: prefer build-locally + `nix copy` + `switch-to-configuration`
      over `nixos-rebuild switch` (no root needed for the copy).

---

## 4. Phase 1 — pin the final nix-bitcoin release and bump the lock

**Goal:** move off the dead 25.11-based rev onto the final 26.05-based rev, and pin it immutably.

### Steps

1. Edit `flake.nix:4-6`:

   ```nix
   # nix-bitcoin is ARCHIVED and unmaintained as of 2026-08-13 (see its README
   # warning). v0.0.139 is the final release — no further updates or security
   # fixes will come from this project. Pin the tag, not the branch, so the
   # lock cannot be broken if the branch is ever deleted.
   inputs.nix-bitcoin.url = "github:fort-nix/nix-bitcoin/v0.0.139";
   ```

2. Leave `inputs.nixpkgs.follows` as-is for this phase only (Phase 2 changes it). Bump with:

   ```bash
   nix flake update nix-bitcoin
   ```

3. Sanity-check the resulting lock:

   ```bash
   nix flake metadata | jq -r '.locks.nodes["nix-bitcoin"].locked'
   # expect rev 37931e52881956c7d6ace2f56415f54b012000a1
   ```

### Verify

```bash
nix eval --json .#nixosConfigurations.nixbit.pkgs.bitcoin.version   # 31.1
nix eval --impure --json --expr '
let c = builtins.getFlake (toString ./.);
    nbp = c.nixosConfigurations.nixbit.config.nix-bitcoin.pkgs;
in { lnd = nbp.lnd.version; bitcoin = nbp.bitcoin.version; rtl = nbp.rtl.version;
     mempool = nbp.mempool-backend.version; clightning = nbp.clightning.version; }'
```

Expected: `bitcoin 31.1`, `lnd 0.21.1-beta` (unchanged — it was already coming from
nix-bitcoin's pinned unstable), `rtl 0.15.8`, `mempool 3.2.1`.

No module option-surface changes exist between the two revisions for every module we use
(`bitcoind`, `lnd`, `mempool`, `rtl`, `electrs`, `onion-services`, `secrets`, `operator`,
`nodeinfo`, `backups`) — zero added/removed options, so config compatibility risk is low.

### Deploy

```bash
sudo nixos-rebuild dry-activate --flake .#nixbit          # if run on nixbit itself
# or, preferred (from this machine):
Toplevel=$(nix eval --raw .#nixosConfigurations.nixbit.config.system.build.toplevel)
nix build --no-link "$Toplevel"
nix copy --to ssh://cody@nixbit "$Toplevel"
ssh -t cody@nixbit "sudo $Toplevel/bin/switch-to-configuration switch"
```

After switching: `systemctl --failed`, `bitcoin-cli getblockchaininfo`, `lncli getinfo`,
`systemctl status mempool rtl albyhub`, `curl -s localhost:8080/api/blocks/tip/height`.

### Rollback

`git checkout HEAD~1 -- flake.nix flake.lock && rebuild`. Data formats are unchanged in this phase
(lnd stays 0.21.1; bitcoind 31.0→31.1 needs no migration; mariadb 11.4.8→11.4.12 is in-place
compatible).

---

## 5. Phase 2 — unfreeze the base OS package set

**Goal:** stop inheriting nix-bitcoin's dead nixpkgs revision, so the OS keeps getting security
backports. **This is the single highest-value security change in the plan.**

### Steps

`flake.nix:7-8`:

```nix
inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
# nixpkgs intentionally does NOT follow nix-bitcoin: nix-bitcoin is archived and
# its nixpkgs pin is frozen at a 2026-06-30 revision. nix-bitcoin's overlay still
# pins the bitcoin-stack packages it owns (see nix-bitcoin/pkgs/pinned.nix), so
# unpinning here only affects the rest of the system (kernel, tor, nginx,
# tailscale, mariadb, …). Tracking the supported stable branch keeps getting
# security backports; bump to nixos-26.11 once that branch is cut.
```

- Remove `inputs.nixpkgs-unstable.follows = "nix-bitcoin/nixpkgs-unstable";` — nothing in
  `outputs` reads `nixpkgs-unstable`; the transitive input is locked by nix-bitcoin's own lockfile.
- `nix flake update`

### Why this is safe

nix-bitcoin's `overlay.nix` is `self: super: import ./pkgs { pkgs = super; }`, so nix-bitcoin's
`pinned` packages (`bitcoin`, `bitcoind`, `electrs`, `clightning`, …) are taken from **our** pkgs,
while `pkgsUnstable` (lnd, btcpayserver, fulcrum) still comes from `pkgs/nixpkgs-pinned.nix`
inside nix-bitcoin. Verified: a `nixosSystem` with nix-bitcoin `v0.0.139` + `nixos-26.05`
evaluates cleanly and yields `lnd 0.21.1-beta`, `bitcoin 31.1`, `tor 0.4.9.13`,
`tailscale 1.98.10`, `mariadb 11.4.12`, `nginx 1.30.5` (see Appendix A.2).

`system.stateVersion` **stays** `"25.11"` (`configuration.nix:159`) — do not bump it as part of a
package upgrade; that is a separate, deliberate migration.

### Verify

```bash
nix eval --json .#nixosConfigurations.nixbit.config.boot.kernelPackages.kernel.version  # 6.18.55
nix eval --json .#nixosConfigurations.nixbit.pkgs.nginx.version        # 1.30.5
nix eval --json .#nixosConfigurations.nixbit.pkgs.tor.version          # 0.4.9.13
nix eval --json .#nixosConfigurations.nixbit.pkgs.glibc.version        # 2.42
```

Then deploy as in Phase 1 and confirm the new kernel booted (`uname -r`), nginx/mempool respond,
tailscale reconnects, and mariadb comes up with the existing `/mnt/data/mysql` data.

### Rollback

Same as Phase 1. The kernel jump (6.12 → 6.18) is the only item worth smoke-testing early;
`nixos-rebuild` keeps the previous generation in the boot loader.

---

## 6. Phase 3 — clean up the hand-written Alby Hub unit

**Why:** no upstream module will ever exist — nix-bitcoin PR #794 ("albyhub: add module") was
closed unmerged, and upstream is dead. The current unit uses a `script` with `export` lines and
misaligned indentation (`flake.nix:164-182`).

### Target shape (replace `flake.nix:161-186`)

```nix
            # ---------------------------------------------------------------------------
            # Alby Hub — Nostr Wallet Connect server.
            # No upstream NixOS module exists (nix-bitcoin PR #794 was closed
            # unmerged and the project is archived), so this unit is hand-rolled
            # against `pkgs.albyhub`. Runs as `cody` because the LND macaroon it
            # reads lives in the user's own data dir.
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
                Restart = "on-failure";
                RestartSec = "10";
                # Match the hardening profile nix-bitcoin applies to its own services
                PrivateTmp = true;
                ProtectSystem = "strict";
                ProtectHome = true;
                NoNewPrivileges = true;
                ProtectKernelTunables = true;
                ProtectKernelModules = true;
                ProtectControlGroups = true;
                RestrictSUIDSGID = true;
                LockPersonality = true;
                SystemCallArchitectures = "native";
              };
            };

            systemd.tmpfiles.rules = [
              "d /mnt/data/albyhub 0755 cody users"
            ];
```

Notes:
- The inline module currently takes `{pkgs, ...}` (`flake.nix:31`) — add `lib` to that argument
  list if `lib.getExe` is used.
- `ProtectHome = true` is safe here: the macaroon is under `/mnt/data`, not `$HOME`.
- Do **not** add `RestrictAddressFamilies = "AF_UNIX"`-only or `IPAddressDeny = "any"` without an
  allow-list; Alby Hub needs outbound network access.
- Alby Hub runs its own SQLite migrations on startup; from 1.20.0 → 1.22.2 the pre-Phase-1 backup
  in §3 is the safety net.

### Verify

```bash
systemctl status albyhub --no-pager
journalctl -u albyhub -n 50 --no-pager
curl -sS -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8082/api/v1/health
```

---

## 7. Phase 4 (next phase) — exposure reduction and hardening

**Deploy separately from Phases 1-3.** 🔴 **Lockout risk:** item 1 and item 2 change SSH/firewall
reachability. Verify Tailscale connectivity to `nixbit` (and keep VM console access) *before*
switching. If you administer over the LAN rather than Tailscale, scope the firewall rules to your
LAN interface instead of `tailscale0`.

Current state (`configuration.nix:120-133`): ports 22, 8080, 3000, 8081, 8082, 9735 are open on
**every** interface, all over plain HTTP.

### Steps

1. **Move the app surface to `tailscale0`.**

   ```nix
   networking.firewall.allowedTCPPorts = [ 22 ]; # SSH only
   networking.firewall.interfaces.tailscale0.allowedTCPPorts = [
     8080 # mempool explorer
     8081 # LND REST API
     8082 # Alby Hub
     3000 # RTL
     8332 # Bitcoin Core RPC (Sparrow)
   ];
   ```

   Drop 9735 only after confirming the node does not rely on clearnet inbound Lightning —
   inbound currently comes from the `lnd.public` onion service (`flake.nix:111-113`), and
   `services.lnd.tor.proxy = true`. If channels/funnels show clearnet inbound, keep 9735 on
   `tailscale0` too, or leave it open and note why.

2. **SSH hardening** (`configuration.nix:111-117`):

   ```nix
   services.openssh.settings = {
     PermitRootLogin = "no";
     PasswordAuthentication = false;   # only after confirming key-based login works
     KbdInteractiveAuthentication = false;
   };
   ```

   Test `ssh cody@nixbit` from a second session *before* dropping password auth; keep the console
   available as the recovery path.

3. **RTL: bind to loopback and reach it over Tailscale.**

   ```nix
   services.rtl = {
     enable = true;
     dataDir = "/mnt/data/rtl";
     nodes.lnd.enable = true;
     address = "127.0.0.1";   # was 0.0.0.0
     port = 3000;
   };
   ```

   Access via `tailscale serve --bg http://127.0.0.1:3000` on the node, or an SSH tunnel
   (`ssh -L 3000:127.0.0.1:3000 cody@nixbit`). This matches nix-bitcoin's documented guidance
   (`docs/services.md`, RTL section). With RTL off the LAN, the frozen 0.15.8 is no longer
   remotely reachable — which is what makes Phase 5 optional rather than urgent.

   Note: `networking.firewall.interfaces.tailscale0` rules become irrelevant for a loopback-bound
   service; keep or drop the 3000 entry to match.

4. **Alby Hub macaroon scoping (optional, manual).** Alby Hub currently reads LND's **admin**
   macaroon (`flake.nix:171` region), i.e. full node control. Investigate a restricted
   invoice/payments macaroon instead: create it with `lncli` (`macaroon add` with limited
   permissions) and point `LND_MACAROON_FILE` at it. This requires rotating the credential Alby
   has stored, so treat it as its own change with its own rollback.

### Verify

```bash
# from a LAN host (should now be refused)
curl -sS -m 5 http://<nixbit-lan-ip>:3000/ ; echo "expect timeout/refused"
curl -sS -m 5 http://<nixbit-lan-ip>:8080/ ; echo "expect timeout/refused"
# over tailscale (should succeed)
curl -sS -m 5 http://100.94.170.33:8080/api/blocks/tip/height
ssh -o BatchMode=yes cody@nixbit true && echo "key auth ok"
```

---

## 8. Phase 5 (next phase) — remediating the frozen packages

nix-bitcoin is dead, so these cannot be fixed by upstream. Ordered by value.

| # | Item | Action | Risk |
|---|---|---|---|
| 5.1 | RTL 0.15.8 → 0.15.13 | Vendor `pkgs/rtl/default.nix` + `pkgs/build-support/fetch-node-modules.nix` from nix-bitcoin (MIT, same project) into `pkgs/rtl.nix` in this repo; bump `version` to `0.15.13`; recompute the `fetchurl` hash and the `fetchNodeModules` hash; point the unit at it via `systemd.services.rtl.overrideConfig = { ExecStart = "${myRtl}/bin/rtl"; };` | Medium — needs two new hashes; RTL 0.15.10+ may no longer need `npmFlags = "--legacy-peer-deps"` (nb's file has a `TODO-EXTERNAL` about it) |
| 5.2 | Drop RTL instead of 5.1 | Disable `services.rtl`; use mempool + `nix-bitcoin.nodeinfo` (+ Alby Hub for payments) | Low — but loses a node-management UI |
| 5.3 | albyhub 1.22.2 → 1.23.0+ | Available in nixpkgs master only. Add a second input pinned to `nixpkgs-unstable` and set `ExecStart` via `systemd.services.albyhub.overrideConfig`, or override `pkgs.albyhub` | Low-medium — unreleased channel |
| 5.4 | tailscale 1.98.10 → 1.104.x | Same mechanism as 5.3 | Low-medium — unreleased channel; no advisories since 2022 |
| 5.5 | mempool 3.2.1 → 3.3.1 | **Not realistically vendorable** (NAPI + rust-gbt backend build). Accept 3.2.1; Phase 4 makes it tailnet-only; no advisories | Accepted |
| 5.6 | electrs 0.11.0 → 0.12.0 | Frozen by nix-bitcoin. Accept — it is loopback-only for mempool | Accepted |
| 5.7 | lnd 0.21.1 → 0.21.4 | `services.lnd.package` exists, but `nixos-26.05` stable is *older* (0.20.1), so this means tracking master. Release notes for 0.21.2/3/4 contain no security fixes | Skip |
| 5.8 | Community fork | `ostermayer/nix-bitcoin` has weekly pin bumps + hardening work, but it is a 0-star personal fork — a supply-chain decision, not a technical one. `bitcoin-nix/nix-bitcoin` and others are unmodified forks | Avoid unless the owner opts in |

### Gotcha: overriding a package that a nix-bitcoin module hardcodes

`services.lnd.package`, `services.bitcoind.package` and `services.mempool.package` are **public**
options defaulting to `config.nix-bitcoin.pkgs.*`, so those are easy to override. RTL and electrs
have **no** `package` option — their units hardcode the package path
(`modules/rtl.nix:216` uses `${nbPkgs.rtl}/bin/rtl`; `modules/electrs.nix:79-81` uses
`${config.nix-bitcoin.pkgs.electrs}/bin/electrs`). For those, use:

```nix
systemd.services.rtl.overrideConfig = { ExecStart = "${myRtl}/bin/rtl"; };
```

`overrideConfig` takes precedence over a module's `serviceConfig` without an `mkForce` conflict,
and leaves nix-bitcoin's `ExecStartPre` macaroon-install steps intact. Do **not** set
`systemd.services.rtl.serviceConfig.ExecStart` directly — that collides with the module's
definition.

### Gotcha: overriding `services.lnd.package` on an existing node

`lndinit` (from `config.nix-bitcoin.pkgs.lndinit`, itself pinned at `0.1.3-beta`) is only invoked
to create a seed/wallet when they do not exist (`modules/lnd.nix:242-252`). This node already has a
wallet and macaroons, so changing `services.lnd.package` does not regenerate credentials. Still,
test on a copy of `/mnt/data/lnd` first if you go down this path.

---

## 9. Phase 6 — documentation

Update `AGENTS.md`:

1. Add a "nix-bitcoin is archived" note: archived 2026-08-13, pinned to `v0.0.139`, and that
   `inputs.nixpkgs` intentionally does **not** follow nix-bitcoin (rewrite the comment now at
   `flake.nix:4-5` which states the opposite).
2. Replace every `nixosConfigurations.mynode` example with `nixbit` (current file uses both names).
3. Remove the `nixel` section (upstream is gone and it is not in nixpkgs).
4. Remove `services.joinmarket.enable` from "Common services": JoinMarket is archived upstream and
   was removed from nix-bitcoin master (issue #839, PR #850, 2026-10-07).
5. Add an Alby Hub section documenting the hand-rolled unit, why no module exists, and how to reach
   it over Tailscale.
6. Document the exposure model (Tailscale-only web UI, loopback RTL) in the security notes.
7. Add a "re-verify upstream versions" snippet (Appendix A.3) so a future agent can tell what has
   drifted without trusting this document.

---

## 10. Open decisions (resolve before starting Phase 4/5)

- [ ] **Q1** — Is `nixbit` administered over Tailscale or over the LAN? Determines whether Phase 4
      item 1 is safe as written.
- [ ] **Q2** — RTL: vendor 0.15.13 (5.1), bind-to-localhost-only and stay on 0.15.8, or drop RTL (5.2)?
- [ ] **Q3** — Include the Alby Hub admin-macaroon → restricted-macaroon rotation (Phase 4 item 4)?
- [ ] **Q4** — Track unreleased nixpkgs master for albyhub/tailscale (5.3/5.4), or wait for
      `nixos-26.11`?

---

## Appendix A — verification probes

### A.1 Current config (locked state)

```bash
nix eval --impure --json --expr '
let c = builtins.getFlake (toString ./.);
    cfg = c.nixosConfigurations.nixbit.config;
    nbp = cfg.nix-bitcoin.pkgs;
    p = c.nixosConfigurations.nixbit.pkgs;
in { lnd = nbp.lnd.version; bitcoin = nbp.bitcoin.version; electrs = nbp.electrs.version;
     rtl = nbp.rtl.version; mempool = nbp.mempool-backend.version;
     albyhub = p.albyhub.version; tor = p.tor.version; tailscale = p.tailscale.version;
     nginx = p.nginx.version; mariadb = p.mariadb.version;
     kernel = cfg.boot.kernelPackages.kernel.version; glibc = p.glibc.version; }'
```

`services.*` modules read `config.nix-bitcoin.pkgs.*` for bitcoind/lnd/electrs/rtl/mempool and
plain `pkgs.*` for everything else (including `pkgs.albyhub` and `pkgs.mysql`).

### A.2 Decoupling proof (does not touch the repo)

```bash
nix eval --impure --json --expr '
let
  nb = builtins.getFlake "github:fort-nix/nix-bitcoin/v0.0.139";
  np = builtins.getFlake "github:NixOS/nixpkgs/nixos-26.05";
  sys = np.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [ nb.nixosModules.default ({ ... }: {
      nixpkgs.pkgs = np.legacyPackages.x86_64-linux;
      nix-bitcoin.generateSecrets = true;
      services.bitcoind.enable = true; services.lnd.enable = true;
      services.electrs.enable = true; services.rtl.enable = true;
      services.mempool.enable = true;
      system.stateVersion = "25.11";
    }) ];
  };
  nbp = sys.config.nix-bitcoin.pkgs;
in { lnd = nbp.lnd.version; bitcoin = nbp.bitcoin.version; tor = sys.pkgs.tor.version;
     tailscale = sys.pkgs.tailscale.version; nginx = sys.pkgs.nginx.version; }'
```

### A.3 Detect a future upstream archive/maintenance change

```bash
curl -sS https://raw.githubusercontent.com/fort-nix/nix-bitcoin/master/README.md \
  | head -5
# WARNING line appears at the top once archived
```

Do **not** use `api.github.com/repos/fort-nix/nix-bitcoin` → `archived` field; it is `false`
despite the archive.

### A.4 Check what a package's latest upstream version is

```bash
curl -sS "https://api.github.com/repos/<owner>/<repo>/releases?per_page=5" \
  | jq -r '.[].tag_name'
```

Rate limits apply unauthenticated (GitHub returned 403s during this investigation for some
endpoints; `<owner>/<repo>/security-advisories` and per-release fetches worked
intermittently). nginx advisories live at <https://nginx.org/en/security_advisories.html>, not in
the GitHub API.

## Appendix B — reference links

- Archive notice: <https://github.com/fort-nix/nix-bitcoin#readme>
- Final release `v0.0.139` = commit `37931e52881956c7d6ace2f56415f54b012000a1`
- RTL advisory: <https://github.com/Ride-The-Lightning/RTL/security/advisories/GHSA-wj92-jhwh-85j5>
- nginx advisories: <https://nginx.org/en/security_advisories.html>
- nix-bitcoin pin semantics: `pkgs/pinned.nix`, `pkgs/nixpkgs-pinned.nix`, `overlay.nix`,
  `modules/nix-bitcoin.nix` (option `nix-bitcoin.pkgs`)
- Bitcoind upstream: <https://github.com/bitcoin/bitcoin/releases> (v31.1, 2026-07-08, current)