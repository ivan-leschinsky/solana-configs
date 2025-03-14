#!/bin/bash
# set -x # uncomment to enable debug
echo "###################### WARNING!!! ###################################"
echo "###   This script will perform the following operations:          ###"
echo "###   * stop firedancer service                                   ###"
echo "###   * delete ledger and snapshots                               ###"
echo "###   * download snapshot finder and run                          ###"
echo "###   * cluster definition and download snapshot                  ###"
echo "###   * wait for catchup                                          ###"
echo "###   * start firedancer service                                  ###"
echo "###                                                               ###"
echo "###   *** Script provided by vano.one (originally MARGUS.ONE)     ###"
echo "#####################################################################"

# Initialize helper UI functions
eval "$(curl -fsSL https://raw.githubusercontent.com/ivan-leschinsky/solana-configs/v2.9/helper.sh)"


service_file="/root/solana/solana.service"
LEDGER=$(cat $service_file | grep "\--ledger" | awk '{ print $2 }' )
SNAPSHOTS=$(cat $service_file | grep "\--snapshots" | awk '{ print $2 }' )

if [ "$LEDGER" == "" ]; then
service_file=/root/solana/validator.sh
LEDGER=$(cat $service_file | grep "\--ledger" | awk '{ print $2 }' )
SNAPSHOTS=$(cat $service_file | grep "\--snapshots" | awk '{ print $2 }' )
INC_SNAPSHOTS=$(cat $service_file | grep "\--incremental-snapshot-archive-path" | awk '{ print $2 }' )
fi

if [ "$LEDGER" == "" ]; then
service_file=/home/firedancer/solana_fd/solana-testnet.toml
LEDGER=$(awk '/^\[ledger\]/ {in_ledger=1; next} /^\[/ && !/^\[ledger\]/ {in_ledger=0} in_ledger && $1=="path" {gsub(/"/, "", $3); print $3; exit}' $service_file)
fi
if [ "$SNAPSHOTS" == "" ]; then
SNAPSHOTS=$(awk '/^\[snapshots\]/ {in_snapshots=1; next} /^\[/ && !/^\[snapshots\]/ {in_snapshots=0} in_snapshots && $1=="path" {gsub(/"/, "", $3); print $3; exit}' $service_file)
fi
networkrpcURL=$(cat /root/.config/solana/cli/config.yml | grep json_rpc_url | grep -o '".*"' | tr -d '"')
if [ "$networkrpcURL" == "" ]; then networkrpcURL=$(cat /root/.config/solana/cli/config.yml | grep json_rpc_url | awk '{ print $2 }')
fi

catchup_info() {
  while true; do
    rpcPort=$(ps aux | grep solana-validator | grep -Po "\-\-rpc\-port\s+\K[0-9]+")
    sudo -i -u root solana catchup --our-localhost $rpcPort
    status=$?
    if [ $status -eq 0 ];then
      exit 0
    fi
    echo "waiting next 30 seconds for rpc"
    sleep 30
  done
}

if [ -f $service_file ]; then

# systemctl stop solana
systemctl stop firedancer
cd /root/solana
# rm -fr solana-snapshot-finder
if [ -z "$LEDGER" ] || [ -z "$SNAPSHOTS" ]; then
  echo "Ledger or snapshots not found. No remove!"
else
# rm -fr $LEDGER/*
rm -fr $SNAPSHOTS/*
fi
if ! [ -d $SNAPSHOTS ]; then
mkdir $SNAPSHOTS
fi

# if ! [ -d "solana-snapshot-finder" ]; then
#   git clone https://github.com/c29r3/solana-snapshot-finder.git
# fi

mkdir -p solana-snapshot-finder
cd solana-snapshot-finder
curl -o snapshot-finder https://raw.githubusercontent.com/ivan-leschinsky/solana-configs/master/binaries/snapshot-finder
chmod +x snapshot-finder
if [ "$networkrpcURL" == "https://api.testnet.solana.com" ]; then
./snapshot-finder --snapshot_path $SNAPSHOTS -r https://api.testnet.solana.com --max_latency 250 --min_download_speed 30
# systemctl start solana
systemctl start firedancer
catchup_info
elif [ "$networkrpcURL" == "https://api.mainnet-beta.solana.com" ]; then
  ./snapshot-finder --snapshot_path $SNAPSHOTS  --max_latency 100 --min_download_speed 60

if ! [ "$INC_SNAPSHOTS" == "" ]; then

if ! [ -d $INC_SNAPSHOTS ]; then
mkdir $INC_SNAPSHOTS
fi

cd $SNAPSHOTS
mv incremental-snapshot* $INC_SNAPSHOTS
fi

# systemctl start solana
systemctl start firedancer
catchup_info
elif [ "$networkrpcURL" == "https://api.devnet.solana.com" ]; then
# cd solana-snapshot-finder
./snapshot-finder --snapshot_path $SNAPSHOTS -r https://api.devnet.solana.com --max_latency 500 --min_download_speed 20
# systemctl start solana
systemctl start firedancer
catchup_info
fi

else
echo "solana.service not found! Default: /root/solana/solana.service"
fi
