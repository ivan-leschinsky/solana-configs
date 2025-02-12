#!/bin/bash
#set -x -e

SOLANA_DIR=/root/solana
mkdir -p $SOLANA_DIR

echo "###################### WARNING!!! ###################################"
echo "###   This script will perform the following operations:          ###"
echo "###   * install monitoring (option)                               ###"
echo "###                                                               ###"
echo "###   *** Script provided by vano.one (originally MARGUS.ONE)     ###"
echo "#####################################################################"
echo

echo "nameserver 8.8.8.8" >> /etc/resolv.conf

echo "#############################################################"
echo "###       Installing base:   curl, wget       ###"
echo "#############################################################"
apt update -y && apt upgrade -y && apt install curl wget -y


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
apt-get update
apt-get -y install telegraf jq bc
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

install_monitoring
echo "### Done."

exit 0
