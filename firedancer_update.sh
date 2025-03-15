#!/bin/bash

set -e


# Initialize helper UI functions
eval "$(curl -fsSL https://raw.githubusercontent.com/ivan-leschinsky/solana-configs/v3.7.0/helper.sh)"

print_multiline_header "Solana Firedancer Updater v3.8.6" \
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
  NEW_VERSION=$(curl -s https://api.vano.one/fd-version)
  if [ -n "$NEW_VERSION" ]; then
    echo -e "${YELLOW}ℹ️ Using firedancer version: $NEW_VERSION${NC}"
  else
    echo -e "${RED}❌ Need to pass version as argument to this script.${NC}"
    exit 1
  fi
fi

print_header "Starting updating Firedancer to the $NEW_VERSION..."

DOWNLOADED=false
REBOOT_AFTER_UPDATE="n"
AGAVE_VALIDATOR_URL="https://raw.githubusercontent.com/ivan-leschinsky/solana-configs/master/binaries/agave-validator"

# Function to download binary or file
download_file() {
  local url="$1"
  local output_file="$2"
  local description="${3:-file}"

  echo -e "${CYAN}📥 Downloading ${description}...${NC}"

  # Using curl with progress bar for large files
  curl -L --progress-bar "$url" -o "$output_file"

  local result=$?

  if [ $result -eq 0 ] && [ -f "$output_file" ]; then
    local filesize=$(du -h "$output_file" | cut -f1)
    echo -e "${GREEN}✅ Successfully downloaded ${description}! (Size: ${filesize})${NC}"
    return 0
  else
    echo -e "${RED}❌ Failed to download ${description}. Error code: ${result}${NC}"
    return 1
  fi
}

download_file_lfs() {
  local filename="$1"
  local output_file="$2"
  local description="${3:-file}"
  local git_url="https://raw.githubusercontent.com/ivan-leschinsky/solana-configs/master/binaries/$filename"

  echo -e "${CYAN}📥 Downloading ${description} from LFS...${NC}"

  # Step 1: Get the LFS pointer file
  local lfs_pointer=$(curl -s "$git_url")

  # Step 2: Extract the LFS URL from the pointer file
  if [[ "$lfs_pointer" == *"oid sha256:"* ]]; then
    echo -e "${CYAN}This is an LFS-managed file. Processing...${NC}"

    # Extract the OID (SHA256 hash)
    local oid=$(echo "$lfs_pointer" | grep "oid sha256:" | cut -d: -f2 | tr -d '[:space:]')

    # Extract the size
    local size=$(echo "$lfs_pointer" | grep "size" | cut -d' ' -f2 | tr -d '[:space:]')

    # Get the repository information
    local repo_owner="ivan-leschinsky"
    local repo_name="solana-configs"

    # Construct the LFS API URL
    local lfs_api_url="https://github.com/$repo_owner/$repo_name.git/info/lfs/objects/batch"

    # Create JSON payload for the LFS API request
    local json_payload="{\"operation\": \"download\", \"transfers\": [\"basic\"], \"objects\": [{\"oid\": \"$oid\", \"size\": $size}]}"

    # Make the LFS API request to get the download URL
    local lfs_response=$(curl -s -X POST \
        -H "Accept: application/vnd.git-lfs+json" \
        -H "Content-Type: application/vnd.git-lfs+json" \
        -d "$json_payload" \
        "$lfs_api_url")

    # Extract the download URL from the response
    local download_url=$(echo "$lfs_response" | jq -r '.objects[0].actions.download.href')

    if [ -z "$download_url" ] || [ "$download_url" == "null" ]; then
        echo -e "${RED}❌ Failed to get download URL from LFS API. Response:${NC}"
        echo "$lfs_response"
        return 1
    fi

    # Download the actual file with progress bar
    echo -e "${CYAN}Downloading file from: $download_url${NC}"
    curl -L --progress-bar "$download_url" -o "$output_file"
  else
    # If it's not an LFS file, just download it directly
    echo -e "${YELLOW}⚠️ This appears to be a regular file, not LFS-managed. Downloading directly...${NC}"
    curl -L --progress-bar "$git_url" -o "$output_file"
  fi

  local result=$?

  if [ $result -eq 0 ] && [ -f "$output_file" ]; then
    local filesize=$(du -h "$output_file" | cut -f1)
    echo -e "${GREEN}✅ Successfully downloaded ${description}! (Size: ${filesize})${NC}"
    chmod +x "$output_file"
    return 0
  else
    echo -e "${RED}❌ Failed to download ${description}. Error code: ${result}${NC}"
    return 1
  fi
}

compile_fd() {
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

update_fd() {
  install_packages jq

  # Create version-specific directory for downloaded binaries
  DOWNLOAD_DIR="/root/firedancer-${NEW_VERSION}"
  mkdir -p "$DOWNLOAD_DIR"

  # Check if pre-compiled binary is available
  AVAILABILITY_URL="https://api.vano.one/files/fdctl-${NEW_VERSION}"
  AVAILABILITY_RESPONSE=$(curl -s "$AVAILABILITY_URL")

  if echo "$AVAILABILITY_RESPONSE" | jq -e '.available == true' > /dev/null 2>&1; then
    if ask_yes_no "Download pre-compiled binaries for firedancer ${NEW_VERSION} instead of compiling?" "y"; then
      FDCTL_URL="https://solana-api.vano.one/fdctl-${NEW_VERSION}"
      SOLANA_URL="https://solana-api.vano.one/solana-${NEW_VERSION}"

      # Download fdctl and check if successful
      if ! download_file "$FDCTL_URL" "${DOWNLOAD_DIR}/fdctl" "fdctl binary"; then
        echo -e "${RED}❌ Failed to download fdctl binary. Falling back to compilation.${NC}"
        compile_fd
        return
      fi

      # Download solana and check if successful
      if ! download_file "$SOLANA_URL" "${DOWNLOAD_DIR}/solana" "solana binary"; then
        echo -e "${RED}❌ Failed to download solana binary. Falling back to compilation.${NC}"
        compile_fd
        return
      fi

      # Verify files exist and are executable
      if [ -f "${DOWNLOAD_DIR}/fdctl" ] && [ -f "${DOWNLOAD_DIR}/solana" ]; then
        chmod +x "${DOWNLOAD_DIR}/fdctl" "${DOWNLOAD_DIR}/solana"

        # Create a marker file to indicate binaries were downloaded, not compiled
        touch "${DOWNLOAD_DIR}/downloaded"
        DOWNLOADED=true

        echo -e "${GREEN}✅ Firedancer binaries downloaded successfully!${NC}"
      else
        compile_fd
      fi
    else
      compile_fd
    fi
  else
    echo -e "${YELLOW}⚠️ Pre-compiled binaries for version ${NEW_VERSION} are not available. Proceeding with compilation.${NC}"
    compile_fd
  fi
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
  local DOWNLOAD_DIR="/root/firedancer-${NEW_VERSION}"

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

      # Check if we downloaded binaries or compiled them
      if [ -f "${DOWNLOAD_DIR}/downloaded" ]; then
        # Copy from downloaded directory
        cp ${DOWNLOAD_DIR}/fdctl /usr/local/bin/
        cp ${DOWNLOAD_DIR}/solana /usr/local/bin/
        echo -e "${GREEN}✅ Copied downloaded binaries to /usr/local/bin/${NC}"
      else
        # Copy from compiled directory
        cp /root/firedancer/build/native/gcc/bin/* /usr/local/bin/
        echo -e "${GREEN}✅ Copied compiled binaries to /usr/local/bin/${NC}"
      fi

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
  if ! [ "$REBOOT_AFTER_UPDATE" = "y" ]; then
    start_fd
  fi
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

if check_root; then
  add_firedancer_start
  configure_fd
  update_fd

  # if $DOWNLOADED; then
  #   REBOOT_AFTER_UPDATE="n"
  #   # echo -e "${GREEN}Using downloaded binaries, reboot not required.${NC}"
  # elif ask_yes_no "Do you want to reboot the system after Firedancer update?" "y"; then
  #   REBOOT_AFTER_UPDATE="y"
  # fi
  if ask_yes_no "Do you want to reboot the system after Firedancer update?" "y"; then
    REBOOT_AFTER_UPDATE="y"
  fi

  if command_exists "agave-validator"; then
    print_header "Waiting to restart Firedancer"
    if wait_for_restart_window; then
      restart_with_copy
    fi
  else
    if download_file "$AGAVE_VALIDATOR_URL" "/usr/local/bin/agave-validator" "agave-validator binary"; then
      chmod +x /usr/local/bin/agave-validator
      print_header "Waiting to restart Firedancer"
      if wait_for_restart_window; then
        restart_with_copy
      fi
    else
      echo -e "${RED}❌ Failed to download agave-validator binary. Falling back to simple restart.${NC}"
      restart_with_copy
    fi
  fi

  print_header "${GREEN}Started Firedancer, check service status please${NC}"

  echo

  if [ "$REBOOT_AFTER_UPDATE" = "y" ]; then
    print_multiline_header "Almost finished" \
    "Rebooting server, after that need to check status of the firedancer with:" \
      "service firedancer status" \
      "" \
      "If it fails - start it manually:  service firedancer start" \
      "" \
      "Good luck"
    reboot now
  else
    if $DOWNLOADED; then
      print_multiline_header "Finished" \
        "Check status now:" \
        "service firedancer status"
    else
      print_multiline_header "Almost finished" \
        "After any server reboot run immediately after boot:" \
        "service firedancer start" \
        "" \
        "You can also try to start directly:  service firedancer start" \
        "and then check status with:          service firedancer status" \
        "if it works fine - no need to reboot the server" \
        "" \
        "Good luck"
    fi
  fi
else
  echo -e "${RED}❌ This script must be run as root user.${NC}"
  exit 1
fi
