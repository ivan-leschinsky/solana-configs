#!/bin/bash
#set -x -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Function to create beautiful headers
print_header() {
  local text="$1"
  # Remove color codes for width calculation
  local text_no_color=$(echo -e "$text" | sed 's/\x1b\[[0-9;]*m//g')
  local width=$(( ${#text_no_color} + 4 ))
  local line=$(printf '═%.0s' $(seq 1 $width))

  echo -e "${CYAN}"
  echo "╔${line}╗"
  echo -e "║  ${text}${NC}${CYAN}  ║"
  echo "╚${line}╝"
  echo -e "${NC}"
}

# Function to create beautiful multiline header with title
print_multiline_header() {
  local title="$1"
  shift
  local lines=("$@")

  # Find the longest line length (including title)
  local max_length=${#title}
  for line in "${lines[@]}"; do
    if [ ${#line} -gt $max_length ]; then
      max_length=${#line}
    fi
  done

  # Add padding
  local width=$(( max_length + 4 ))
  local line=$(printf '═%.0s' $(seq 1 $width))
  local empty_line=$(printf ' %.0s' $(seq 1 $width))

  # Print title box
  echo -e "${CYAN}"
  echo "╔${line}╗"
  printf "║  ${BOLD}%-${max_length}s${NC}${CYAN}  ║\n" "$title"
  echo "╠${line}╣"

  # Print content
  for linetext in "${lines[@]}"; do
    printf "║  %-${max_length}s  ║\n" "$linetext"
  done

  # Print bottom border
  echo "╚${line}╝"
  echo -e "${NC}"
}

# Function to check if solana CLI is installed
check_solana_cli() {
  if ! command -v solana &> /dev/null; then
    echo -e "${YELLOW}⚠️  Solana CLI is not installed. Please install it first.${NC}"
    exit 1
  fi
}

# Function to validate and get Solana address
get_solana_address() {
  local address
  address=$(solana address 2>/dev/null)

  if [ $? -ne 0 ] || [ -z "$address" ]; then
    echo -e "${YELLOW}⚠️  Failed to get Solana address. Please check your Solana configuration.${NC}"
    exit 1
  fi
  echo "$address"
}

# Function to generate monitoring URL
generate_monitoring_url() {
  local address="${1//,/}"
  local validator_name="$2"
  local base_url="https://metrics.stakeconomy.com/d/f2b2HcaGz/solana-community-validator-dashboard"
  local params="orgId=1&refresh=1m&var-pubkey=${address}&var-server=${validator_name}&var-inter=1m&var-netif=&var-version="
  echo "${base_url}?${params}"
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}


install_packages() {
  local packages_to_install=()
  local already_installed=()
  local package_map=()  # Array to store package:binary mappings

  # First, process packages and create mapping
  for pkg in "$@"; do
    local package binary

    # Check if package has custom binary name (package:binary format)
    if [[ $pkg == *:* ]]; then
      package="${pkg%%:*}"  # Get package name (before colon)
      binary="${pkg#*:}"    # Get binary name (after colon)
    else
      package="$pkg"
      binary="$pkg"
    fi

    # Store mapping for later use
    package_map+=("$package:$binary")

    # Check if binary exists
    if ! command_exists "$binary"; then
      packages_to_install+=("$package")
    else
      already_installed+=("$package ($binary)")
    fi
  done

  # Print already installed packages
  if [ ${#already_installed[@]} -ne 0 ]; then
    echo -e "${GREEN}✅ Already installed:${NC}"
    printf '%s\n' "${already_installed[@]}" | sed 's/^/  /'
  fi

  # If there are packages to install
  if [ ${#packages_to_install[@]} -ne 0 ]; then
    echo -e "${YELLOW}🔍 Packages to install:${NC}"
    printf '%s\n' "${packages_to_install[@]}" | sed 's/^/  /'

    echo "📦 Updating package lists..."
    if check_root; then
      apt update
    else
      sudo apt update
    fi

    echo "📥 Installing packages..."
    apt install -y "${packages_to_install[@]}"

    # Verify installations
    local failed_installs=()
    for mapping in "${package_map[@]}"; do
      local package="${mapping%%:*}"
      local binary="${mapping#*:}"

      # Only check packages that were installed
      if [[ " ${packages_to_install[@]} " =~ " ${package} " ]]; then
        if ! command_exists "$binary"; then
          failed_installs+=("$package ($binary)")
        fi
      fi
    done

    # Report results
    if [ ${#failed_installs[@]} -eq 0 ]; then
      echo -e "${GREEN}✅ All packages installed successfully!${NC}"
    else
      echo -e "${RED}❌ Failed to install:${NC}"
      printf '%s\n' "${failed_installs[@]}" | sed 's/^/  /'
      exit 1
    fi
  else
    echo -e "${GREEN}✅ All packages are already installed!${NC}"
  fi
}

SOLANA_DIR=/root/solana
mkdir -p $SOLANA_DIR

print_multiline_header "Solana Monitoring Installer" \
    "This script will perform the following operations" \
    "Install and configure telegraf" \
    "Configure monitoring for stakeconomy metrics" \
    "" \
    "Author: vano.one"
echo

echo "nameserver 8.8.8.8" >> /etc/resolv.conf

# echo "#######################################################################"
# echo "###     Ensure base packages presented in the system:   curl, wget  ###"
# echo "#######################################################################"
print_header "Ensure base packages presented in the system:   curl, wget"
install_packages curl wget


install_monitoring() {
  print_header "Installing monitoring"

  print_header "Please type your validator name"
  read -p "Validator name: " VALIDATOR_NAME
  #cat <<
  #deb https://repos.influxdata.com/ubuntu bionic stable
  #EOF
  #curl -sL https://repos.influxdata.com/influxdb.key | apt-key add -
  wget -q https://repos.influxdata.com/influxdata-archive_compat.key
  echo '393e8779c89ac8d958f81f942f9ad7fb82a25e133faddaf92e15b16e6ac9ce4c influxdata-archive_compat.key' | sha256sum -c && cat influxdata-archive_compat.key | gpg --dearmor | sudo tee /etc/apt/trusted.gpg.d/influxdata-archive_compat.gpg > /dev/null
  echo 'deb [signed-by=/etc/apt/trusted.gpg.d/influxdata-archive_compat.gpg] https://repos.influxdata.com/debian stable main' | sudo tee /etc/apt/sources.list.d/influxdata.list
  install_packages telegraf jq bc
  adduser telegraf sudo
  adduser telegraf adm
  echo "telegraf ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers
  cp /etc/telegraf/telegraf.conf /etc/telegraf/telegraf.conf.orig
  rm -rf /etc/telegraf/telegraf.conf
  cd $SOLANA_DIR && mkdir -p solanamonitoring && cd solanamonitoring
  rm -r $SOLANA_DIR/solanamonitoring/monitor.sh
  wget -q https://raw.githubusercontent.com/ivan-leschinsky/solana-configs/v2.3/monitor.sh
  chmod +x $SOLANA_DIR/solanamonitoring/monitor.sh
  touch /etc/telegraf/telegraf.conf
  cat > /etc/telegraf/telegraf.conf <<EOF
# Global Agent Configuration
[agent]
  hostname = "$VALIDATOR_NAME" # set this to a name you want to identify your node in the grafana dashboard
  flush_interval = "15s"
  interval = "15s"
# Input Plugins
[[inputs.cpu]]
    percpu = true
    totalcpu = true
    collect_cpu_time = false
    report_active = false
[[inputs.disk]]
    ignore_fs = ["devtmpfs", "devfs"]
[[inputs.mem]]
[[inputs.net]]
[[inputs.system]]
[[inputs.swap]]
[[inputs.netstat]]
[[inputs.processes]]
[[inputs.kernel]]
[[inputs.diskio]]
# Output Plugin InfluxDB
[[outputs.influxdb]]
  database = "metricsdb"
  urls = [ "http://metrics.stakeconomy.com:8086" ] # keep this to send all your metrics to the community dashboard otherwise use http://yourownmonitoringnode:8086
  username = "metrics" # keep both values if you use the community dashboard
  password = "password"
[[inputs.exec]]
  commands = ["sudo su -c $SOLANA_DIR/solanamonitoring/monitor.sh -s /bin/bash root"] # change home and username to the useraccount your validator runs at
  interval = "3m"
  timeout = "1m"
  data_format = "influx"
  data_type = "integer"
EOF

  sudo systemctl enable --now telegraf

  check_solana_cli

  SOLANA_ADDRESS=$(get_solana_address)

  # Exit if SOLANA_ADDRESS is empty
  if [ -z "$SOLANA_ADDRESS" ]; then
    echo -e "${RED}❌ Error: Failed to get Solana address${NC}"
    exit 1
  fi

  echo -e "${GREEN}✅ Solana address: ${SOLANA_ADDRESS}${NC}"

  MONITORING_URL=$(generate_monitoring_url "$SOLANA_ADDRESS", "$VALIDATOR_NAME")

  echo -e "\n${GREEN}✅ Your Monitoring URL:${NC}"
  echo -e "${MONITORING_URL}"
}

install_monitoring

print_header "${GREEN}Done.${NC}"

exit 0
