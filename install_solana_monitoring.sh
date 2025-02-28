#!/bin/bash

# Initialize helper UI functions
eval "$(curl -fsSL https://raw.githubusercontent.com/ivan-leschinsky/solana-configs/v2.9/helper.sh)"

# Function to generate monitoring URL
generate_monitoring_url() {
  local address="${1//,/}"
  local validator_name="$2"
  local base_url="https://metrics.stakeconomy.com/d/f2b2HcaGz/solana-community-validator-dashboard"
  local params="orgId=1&refresh=1m&var-pubkey=${address}&var-server=${validator_name}&var-inter=1m&var-netif=&var-version="
  echo "${base_url}?${params}"
}

SOLANA_DIR=/root/solana
mkdir -p $SOLANA_DIR

print_multiline_header "Solana Monitoring Installer v2.9" \
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
  rm influxdata-archive_compat.key
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
