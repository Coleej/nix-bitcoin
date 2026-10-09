# Edit this configuration file to define what should be installed on
# your system. Help is available in the configuration.nix(5) man page, on
# https://search.nixos.org/options and in the NixOS manual (`nixos-help`).
{
  config,
  lib,
  pkgs,
  ...
}: {
  imports = [
    # Include the results of the hardware scan.
    ./hardware-configuration.nix
  ];

  # Enable flakes and nix command
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];
  # Allow cody to push store paths to this machine (remote deployments)
  nix.settings.trusted-users = ["cody"];

  # Use the GRUB 2 boot loader.
  boot.loader.grub = {
    enable = true;
    efiSupport = true;
    efiInstallAsRemovable = true;
    device = "nodev";
  };
  # boot.loader.efi.efiSysMountPoint = "/boot/efi";
  # Define on which hard drive you want to install Grub.

  networking.hostName = "nixbit"; # Define your hostname.

  # Configure network connections interactively with nmcli or nmtui.
  networking.networkmanager.enable = true;

  # Set your time zone.
  time.timeZone = "America/Chicago";

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # Select internationalisation properties.
  # i18n.defaultLocale = "en_US.UTF-8";
  # console = {
  #   font = "Lat2-Terminus16";
  #   keyMap = "us";
  #   useXkbConfig = true; # use xkb.options in tty.
  # };

  # Enable the X11 windowing system.
  # services.xserver.enable = true;

  # Configure keymap in X11
  # services.xserver.xkb.layout = "us";
  # services.xserver.xkb.options = "eurosign:e,caps:escape";

  # Enable CUPS to print documents.
  # services.printing.enable = true;

  # Enable sound.
  # services.pulseaudio.enable = true;
  # OR
  # services.pipewire = {
  #   enable = true;
  #   pulse.enable = true;
  # };

  # Enable touchpad support (enabled default in most desktopManager).
  # services.libinput.enable = true;

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.cody = {
    isNormalUser = true;
    extraGroups = ["wheel"]; # Enable 'sudo' for the user.
    packages = with pkgs; [
      tree
      neovim
      opencode
      git
      jq
    ];
  };

  # programs.firefox.enable = true;

  # List packages installed in system profile.
  # You can use https://search.nixos.org/ to find more packages (and options).
  environment.systemPackages = with pkgs; [
    vim
    wget
    tailscale
  ];

  # Enable the tailscaled daemon for persistent Tailscale connectivity.
  services.tailscale.enable = true;

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  programs.gnupg.agent = {
    enable = true;
    enableSSHSupport = true;
  };

  # List services that you want to enable:

  # Enable the OpenSSH daemon.
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = true;
    };
  };

  # Open ports in the firewall.
  # Audited against `ss -tln` on 2026-10-08: every entry below has a matching
  # socket bound to a routable address. Ports that sound relevant but are
  # absent are accounted for under 'Deliberately not opened'.
  networking.firewall.allowedTCPPorts = [
    22 # SSH
    8080 # mempool explorer (nginx)
    3000 # RTL (Ride The Lightning)
    8082 # Alby Hub
    # # Liquid sidechain (disabled)
    # 7041 # Liquid RPC
    # 7042 # Liquid P2P
  ];
  # Bitcoin Core RPC — Tailscale interface only (for Sparrow on desktop).
  # NOTE: this rule has no effect as configured. `rpcbind` is a scalar option and
  # the first value in bitcoin.conf wins, so the `rpcbind=127.0.0.1` written by
  # nix-bitcoin overrides any rpcbind set via services.bitcoind.extraConfig.
  # bitcoind currently listens on 127.0.0.1:8332 only. To actually expose it,
  # set services.bitcoind.rpc.address in flake.nix instead of extraConfig.
  networking.firewall.interfaces.tailscale0.allowedTCPPorts = [8332];

  # Deliberately not opened:
  #   8081 — LND REST binds 127.0.0.1 only (nix-bitcoin's restAddress
  #          default), so no firewall rule is needed or useful.
  #   9735 — LND's clearnet P2P port also binds 127.0.0.1 because
  #          services.lnd.tor.proxy is true; inbound peers arrive over Tor
  #          via nix-bitcoin.onionServices.lnd.public.
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  # Copy the NixOS configuration file and link it from the resulting system
  # (/run/current-system/configuration.nix). This is useful in case you
  # accidentally delete configuration.nix.
  # system.copySystemConfiguration = true;

  # This option defines the first version of NixOS you have installed on this particular machine,
  # and is used to maintain compatibility with application data (e.g. databases) created on older NixOS versions.
  #
  # Most users should NEVER change this value after the initial install, for any reason,
  # even if you've upgraded your system to a new NixOS release.
  #
  # This value does NOT affect the Nixpkgs version your packages and OS are pulled from,
  # so changing it will NOT upgrade your system - see https://nixos.org/manual/nixos/stable/#sec-upgrading for how
  # to actually do that.
  #
  # This value being lower than the current NixOS release does NOT mean your system is
  # out of date, out of support, or vulnerable.
  #
  # Do NOT change this value unless you have manually inspected all the changes it would make to your configuration,
  # and migrated your data accordingly.
  #
  # For more information, see `man configuration.nix` or https://nixos.org/manual/nixos/stable/options#opt-system.stateVersion .
  system.stateVersion = "25.11"; # Did you read the comment?

  # Add swap for memory pressure
  swapDevices = [
    {
      device = "/var/lib/swapfile";
      size = 4096;
    }
  ];
}
