#!/bin/bash

set -e

# Initialize helper UI functions
eval "$(curl -fsSL https://raw.githubusercontent.com/ivan-leschinsky/solana-configs/v2.9/helper.sh)"

print_header "Restarting Firedancer"

wait_for_restart_window() {
  if agave-validator --ledger /home/firedancer/solana_fd/ledger wait-for-restart-window --min-idle-time 10 --max-delinquent-stake 14; then
    return 0
  else
    return 1
  fi
}

restart_fd() {
  service firedancer restart
}

if check_root; then
  update_fd
  if command_exists "agave-validator"; then
    print_header "Waiting to restart Firedancer"
    if wait_for_restart_window; then
      restart_fd
    fi
  else
    restart_fd
  fi
  print_header "Started Firedancer, check service status please with: service firedancer status"

  echo

  print_multiline_header "Almost finished" \
    "If status shows an error our out of memory error - please reboot the server and run immediately after boot:" \
    "fdctl configure init all --config /home/firedancer/solana_fd/solana-testnet.toml" \
    "service firedancer start" \
    "" \
    "You can also try to start directly:  service firedancer start" \
    "and then check status with:          service firedancer status" \
    "if it works fine - no need to reboot the server" \
    "" \
    "Good luck"
else
  echo -e "${RED}❌ This script must be run as root user.${NC}"
  exit 1
fi
