#!/bin/bash

set -e

# Initialize helper UI functions
eval "$(curl -fsSL https://raw.githubusercontent.com/ivan-leschinsky/solana-configs/v2.9/helper.sh)"

print_multiline_header "Solana Firedancer Updater v3.6.0" \
    "This script will perform the following operations" \
    "Update installed firedancer to the latest version or to the specified version from an argument" \
    "Update toml configs and ensure auto-start for firedancer" \
    "firedancer GUI will be enabled on 8080 port" \
    "" \
    "Author: vano.one"

# Based on original docs https://docs.firedancer.io/guide/getting-started.html#releases

if [ -n "$1" ] && [ ${#1} -gt 8 ]; then
  NEW_VERSION="$1"
else
  echo -e "${RED}❌ Need to pass version as argument to this script.${NC}"
  exit 1
fi

print_header "Starting updating Firedancer to the $NEW_VERSION..."

update_fd() {
  USERNAME="firedancer"
  USER_ID=$(id -u "$USERNAME")
  GROUP_ID=$(id -g "$USERNAME")

  if [ ! -d "/root/firedancer" ]; then
    echo "/root/firedancer does not exist, cloning from git..."
    git clone --recurse-submodules https://github.com/firedancer-io/firedancer.git
  fi

  cd /root/firedancer
  git checkout .
  git fetch
  git checkout $NEW_VERSION
  rm -rf agave
  git submodule update --init --recursive
  sed -i "/^[ \t]*results\[ 0 \] = pwd\.pw_uid/c results[ 0 ] = $USER_ID;" ~/firedancer/src/app/fdctl/config.c
  sed -i "/^[ \t]*results\[ 1 \] = pwd\.pw_gid/c results[ 1 ] = $GROUP_ID;" ~/firedancer/src/app/fdctl/config.c

  ./deps.sh </dev/tty
  make -j fdctl solana
}

configure_fd() {
  mkdir -p /home/firedancer/solana_fd
  chown -R firedancer:firedancer /home/firedancer/solana_fd/

  if [ ! -f "/home/firedancer/solana_fd/validator-keypair.json" ] && [ -f "/root/solana/validator-keypair.json" ]; then
    cp /root/solana/validator-keypair.json /home/firedancer/solana_fd/validator-keypair.json
    chmod 660 /home/firedancer/solana_fd/validator-keypair.json
    chown root:firedancer /home/firedancer/solana_fd/validator-keypair.json
  fi

  if [ ! -f "/home/firedancer/solana_fd/vote-account-keypair.json" ] && [ -f "/root/solana/vote-account-keypair.json" ]; then
    cp /root/solana/vote-account-keypair.json /home/firedancer/solana_fd/vote-account-keypair.json
    chmod 660 /home/firedancer/solana_fd/vote-account-keypair.json
    chown root:firedancer /home/firedancer/solana_fd/vote-account-keypair.json
  fi

  if [ ! -f "/home/firedancer/solana_fd/validator-keypair.json" ] && [ ! -f "/root/solana/validator-keypair.json" ]; then
    echo -e "${RED}❌ WARNING: validator-keypair.json not found in either /home/firedancer/solana_fd/ or /root/solana/!${NC}"
    echo -e "${RED}❌ Please ensure you have a valid validator keypair before continuing.${NC}"
  fi

  if [ ! -f "/home/firedancer/solana_fd/vote-account-keypair.json" ] && [ ! -f "/root/solana/vote-account-keypair.json" ]; then
    echo -e "${RED}❌ WARNING: vote-account-keypair.json not found in either /home/firedancer/solana_fd/ or /root/solana/!${NC}"
    echo -e "${RED}❌ Please ensure you have a valid vote account keypair before continuing.${NC}"
  fi

  cat > /home/firedancer/solana_fd/solana-testnet.toml <<EOF
name = "fd1"
user = "firedancer"
dynamic_port_range = "8004-8024"

[log]
    path = "/home/firedancer/solana_fd/solana.log"
#    level_logfile = "DEBUG"
#    level_stderr = "DEBUG"
#    level_flush = "DEBUG"

[ledger]
    path = "/home/firedancer/solana_fd/ledger"
    # accounts_path = "/mnt/accounts"
    limit_size = 50_000_000

[gossip]
    entrypoints = [
    "entrypoint.testnet.solana.com:8001",
    "entrypoint2.testnet.solana.com:8001",
    "entrypoint3.testnet.solana.com:8001",
    ]
    port_check=true

[layout]
    affinity = "auto"
    agave_affinity = "auto"
    verify_tile_count = 1
    bank_tile_count = 1

[consensus]
    identity_path = "/home/firedancer/solana_fd/validator-keypair.json"
    vote_account_path = "/home/firedancer/solana_fd/vote-account-keypair.json"

    expected_genesis_hash = "4uhcVJyU9pJkvQyS88uRDiswHXSCkY3zQawwpjk2NsNY"
    known_validators = [
        "5D1fNXzvv5NjV1ysLjirC4WY92RNsVH18vjmcszZd8on",
        "dDzy5SR3AXdYWVqbDEkVFdvSPCtS9ihF5kJkHCtXoFs",
        "Ft5fbkqNa76vnsjYNwjDZUXoTWpP7VYm3mtsaQckQADN",
        "eoKpUABi59aT4rR9HGS3LcMecfut9x7zJyodWWP43YQ",
        "9QxCLckBiJc783jnMvXZubK4wH86Eqqvashtrwvcsgkv",
    ]
    snapshot_fetch = true
    genesis_fetch = true

[rpc]
    port = 8899
    full_api = true
    private = true
    only_known = false

[reporting]
    solana_metrics_config = "host=https://metrics.solana.com:8086,db=tds,u=testnet_write,p=c4fa841aa918bf8274e3e2a44d77568d9861b3ea"

[snapshots]
    full_snapshot_interval_slots = 100000
    incremental_snapshot_interval_slots = 4000
    maximum_full_snapshots_to_retain = 1
    maximum_incremental_snapshots_to_retain = 1
    path = "/home/firedancer/solana_fd/snapshots"
    minimum_snapshot_download_speed = 150000000

[tiles.gui]
    enabled = true
    gui_listen_address = "0.0.0.0"
    gui_listen_port = 8080

[tiles.bundle]
    enabled = true
    url = "https://testnet.block-engine.jito.wtf"
    tip_distribution_program_addr = "F2Zu7QZiTYUhPd7u9ukRVwxh7B71oA3NMJcHuCHc29P2"
    tip_payment_program_addr = "GJHtFqM9agxPmkeKjHny6qiRKrXZALvvFGiKf11QE7hy"
    tip_distribution_authority = "GZctHpWXmsZC1YHACTGGcHhYxjdRqQvTpYkb9LMvxDib"
    commission_bps = 10000

EOF
}

is_file_busy() {
  local file="$1"

  if lsof "$file" > /dev/null 2>&1; then
    return 0
  else
    return 1
  fi
}

copy_when_free() {
  local FILES=("/usr/local/bin/fdctl" "/usr/local/bin/solana")

  while true; do
    ALL_FREE=true

    for file in "${FILES[@]}"; do
      if is_file_busy "$file"; then
        ALL_FREE=false
        break
      fi
    done

    if $ALL_FREE; then
      echo -e "Copying ${RED}fdctl${NC} and ${RED}solana${NC} binary files..."
      cp /root/firedancer/build/native/gcc/bin/* /usr/local/bin/
      break
    fi
    echo -e "${YELLOW}Waiting for solana,fdctl files to be free...${NC}"
    sleep 5
  done
}

stop_fd() {
  service firedancer stop
}

start_fd() {
  service firedancer start
}

wait_for_restart_window() {
  if agave-validator --ledger /home/firedancer/solana_fd/ledger wait-for-restart-window --min-idle-time 3 --max-delinquent-stake 14; then
    return 0
  else
    return 1
  fi
}

restart_with_copy() {
  stop_fd
  sleep 5
  copy_when_free
  start_fd
}

add_firedancer_start() {
  print_header "Setting up Firedancer boot script..."

  # Create/update the systemd service file
  cat > /etc/systemd/system/firedancer.service <<EOF
[Unit]
Description=Firedancer Node
Wants=network.target
After=network.target

[Service]
# User=root
# Group=root
ExecStart=/bin/bash -c ' \\
  /usr/local/bin/fdctl configure init all --config /home/firedancer/solana_fd/solana-testnet.toml && \\
  /usr/local/bin/fdctl run --config /home/firedancer/solana_fd/solana-testnet.toml'
Restart=on-failure
RestartSec=30
[Install]
WantedBy=multi-user.target
EOF

  # Reload systemd manager to recognize changes
  systemctl daemon-reload
  echo "Systemd service configuration reloaded"

  # Enable the service to run at boot (this is idempotent - safe to run multiple times)
  systemctl enable firedancer.service
  echo "Systemd service enabled to run at boot"

  # Check if the service is already running
  if systemctl is-active --quiet firedancer.service; then
    echo "firedancer service already running..."
    # systemctl restart firedancer.service
  else
    echo "The firedancer service is not currently running."
    echo "It will run automatically on the next system boot."
  fi
}

# ask_add_autoboot() {
#   # Check if fd-boot service already exists and is enabled
#   if systemctl is-enabled --quiet firedancer.service 2>/dev/null; then
#     echo "firedancer service is already set up and enabled. Skipping auto start configuration."
#     return
#   fi

#   read -p "Do you want to auto start Firedancer init and service on server reboot? (Y/n): " choice
#   choice=${choice:-Y}  # Default to Y if empty (user pressed Enter)
#   case "$choice" in
#     [Yy]* ) add_firedancer_start;;
#     * ) echo "ok, skipping auto start";;
#   esac
# }

if check_root; then
  add_firedancer_start
  update_fd
  configure_fd
  if command_exists "agave-validator"; then
    print_header "Waiting to restart Firedancer"
    if wait_for_restart_window; then
      restart_with_copy
    fi
  else
    restart_with_copy
  fi

  print_header "${GREEN}Started Firedancer, check service status please${NC}"

  echo

  print_multiline_header "Almost finished" \
    "After any server reboot run immediately after boot:" \
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
