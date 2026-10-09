# agentsystemctl — a systemctl wrapper that enforces a subcommand allowlist.
#
# Why this exists: sudoers matches argument *lists*, not subcommands. A sudoers
# rule for `/bin/systemctl is-active` permits exactly that one argument and
# denies `/bin/systemctl is-active bitcoind`, because sudo sees the arguments as
# "is-active bitcoind". There is no sudoers syntax for "this subcommand with any
# following arguments", so a passwordless grant that is actually usable has to
# name a wrapper like this one and let the wrapper do the narrowing.
#
# Verified on nixbit: sudoers CAN express a bare command with any arguments —
# omit the argument specifier entirely. Do not write `""`, which means *no*
# arguments allowed. Hence the sudoers rule grants this script with no argument
# specifier, and the allowlist below does the actual filtering.
#
# The script lives in the nix store, so it is immutable and travels with the
# closure — unlike something dropped into /usr/local/bin, which sudoers would
# then have to trust.
{
  systemd,
  writeShellScript,
}:
writeShellScript "agentsystemctl" ''
  set -eu

  # Read-only verbs plus ordinary service control. Deliberately excluded:
  # edit, set-property, link, revert, isolate — these write unit files or
  # otherwise alter the system as root and have no business being reachable by
  # an unattended agent.
  allowed='status show is-active is-enabled is-enabled-runtime is-failed list-units list-unit-files list-sockets cat start stop restart reload daemon-reload try-restart-or-reload mask unmask'

  if [ "$#" -eq 0 ]; then
    echo "usage: agentsystemctl <subcommand> [args...]" >&2
    exit 2
  fi

  subcommand=$1
  case " $allowed " in
    *" $subcommand "*) ;;
    *)
      echo "agentsystemctl: refusing systemctl subcommand '$subcommand'" >&2
      echo "agentsystemctl: permitted: $allowed" >&2
      exit 126
      ;;
  esac

  shift
  exec ${systemd}/bin/systemctl "$subcommand" "$@"
''
