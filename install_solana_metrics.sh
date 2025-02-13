#!/bin/bash
#set -x -e

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check if running as root
check_root() {
  if [ "$EUID" -ne 0 ]; then
      echo -e "${YELLOW}⚠️  This script needs sudo privileges to install packages.${NC}"
      return 1
  fi
  return 0
}

install_packages() {
  local packages_to_install=()
  local already_installed=()

  # First, check which packages need to be installed
  for package in "$@"; do
    if ! command_exists "$package"; then
      packages_to_install+=("$package")
    else
      already_installed+=("$package")
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
    if check_root; then
      apt install -y "${packages_to_install[@]}"
    else
      sudo apt install -y "${packages_to_install[@]}"
    fi

    # Verify installations
    local failed_installs=()
    for package in "${packages_to_install[@]}"; do
      if ! command_exists "$package"; then
        failed_installs+=("$package")
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

echo "###################### WARNING!!! ###################################"
echo "###   This script will perform the following operations:          ###"
echo "###   * system tuning (option) (install systuner.service)         ###"
echo "###   * system tuning (edit fstrim.timer daily on mainnet)        ###"
echo "###   * install monitoring (option)                               ###"
echo "###   * configure firewall                                        ###"
echo "###                                                               ###"
echo "###   *** Script provided by vano.one (originally MARGUS.ONE      ###"
echo "#####################################################################"
echo

echo "nameserver 8.8.8.8" >> /etc/resolv.conf

echo "###############################################################################"
echo "###      Ensure base packages presented in the system:   curl, wget, gnupg  ###"
echo "###############################################################################"
apt update -y && apt upgrade -y && apt install curl gnupg wget -y
install_packages curl wget gnupg

system_tuning() {

echo "#####################################################"
echo "###       Start system tuning by MARGUS.ONE       ###"
echo "#####################################################"

curl -fsSL https://api.margus.one/solana/tuning.sh | bash

select cluster in "mainnet-beta" "testnet"; do
  case $cluster in
      mainnet-beta )
    		clusternetwork="mainnet"
        break;;
      testnet )
    		clusternetwork="testnet"
        break;;
  esac
done

if [[ $clusternetwork = testnet ]];then
echo "This is testnet. No edit fstrim.timer"
elif [ $clusternetwork = mainnet ];then
echo "Edit /lib/systemd/system/fstrim.timer"
cat > /lib/systemd/system/fstrim.timer <<EOF
[Unit]
Description=Discard unused blocks once a week
Documentation=man:fstrim
ConditionVirtualization=!container

[Timer]
OnCalendar=daily
AccuracySec=1h
Persistent=true

[Install]
WantedBy=timers.target
EOF
fi
}



install_monitoring() {
echo "###########################################"
echo "###         Install monitoring          ###"
echo "###########################################"
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
echo "###########################################"
echo "### Please type your validator name     ###"
echo "###########################################"
read -p "Validator name:" VALIDATOR_NAME
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
}

ufw_configure() {
echo "###########################################"
echo "###      Configure ufw firewall         ###"
echo "###      Enable ufw (y|n)?              ###"
echo "###########################################"
install_packages ufw
sudo ufw allow 22/tcp
sudo ufw allow 2222/tcp
sudo ufw allow 8000:8020/tcp
sudo ufw allow 8000:8020/udp
sudo ufw allow 8899:8900/tcp
ufw allow 80:81/tcp
sudo ufw deny out from any to 10.0.0.0/8
sudo ufw deny out from any to 172.16.0.0/12
sudo ufw deny out from any to 192.168.0.0/16
sudo ufw deny out from any to 100.64.0.0/10
sudo ufw deny out from any to 198.18.0.0/15
sudo ufw deny out from any to 169.254.0.0/16
sudo ufw enable
}

echo "### Add System tuning?  Enter 1 or 2  ###"
select systemtuning in "Yes" "No"; do
    case $systemtuning in
        Yes )
        system_tuning
          break;;
        No )
          break;;
    esac
done


echo "### Install firewal?   Enter 1 or 2  ###"
select firewall in "Yes" "No"; do
  case $firewall in
        Yes )
        ufw_configure
          break;;
        No )
          break;;
    esac
done



echo "### Install monitoring?  Enter 1 or 2  ###"
select monitoring in "Yes" "No"; do
    case $monitoring in
        Yes )
          install_monitoring
          break;;
        No )
          break;;
    esac
done

echo "### Done."

exit 0
