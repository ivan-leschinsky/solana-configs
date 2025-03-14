#!/bin/bash

set -e

# Initialize helper UI functions
eval "$(curl -fsSL https://raw.githubusercontent.com/ivan-leschinsky/solana-configs/v2.9/helper.sh)"

print_multiline_header "Solana Firedancer Updater v3.4.0" \
    "This script will perform the following operations" \
    "Update installed firedancer to the latest version or to the specified version from an argument" \
    "Add auto-start script as an option" \
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
    echo "Restarting firedancer service to apply changes..."
    systemctl restart firedancer.service
  else
    echo "The firedancer service is not currently running."
    echo "It will run automatically on the next system boot."
    echo "You can start it manually with: systemctl start firedancer.service"
  fi

  echo "Firedancer boot setup completed successfully!"
}

ask_add_autoboot() {
  # Check if fd-boot service already exists and is enabled
  if systemctl is-enabled --quiet firedancer.service 2>/dev/null; then
    echo "firedancer service is already set up and enabled. Skipping auto start configuration."
    return
  fi

  read -p "Do you want to auto start Firedancer init and service on server reboot? (Y/n): " choice
  choice=${choice:-Y}  # Default to Y if empty (user pressed Enter)
  case "$choice" in
    [Yy]* ) add_firedancer_start;;
    * ) echo "ok, skipping auto start";;
  esac
}

if check_root; then
  ask_add_autoboot
  update_fd
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
