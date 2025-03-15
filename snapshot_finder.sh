#!/bin/bash
# Solana Firedancer Node Recovery Script
# Author: vano.one (Originally by MARGUS.ONE)
# Snapshot finder originally from https://github.com/c29r3/solana-snapshot-finder.git
# Uncomment to enable debug mode
# set -x

# Initialize helper UI functions
load_helper_functions() {
    eval "$(curl -fsSL https://raw.githubusercontent.com/ivan-leschinsky/solana-configs/v2.9/helper.sh)"
}

# Locate and parse service configuration file to extract paths
find_service_configuration() {
    # Initialize arrays to store detected services
    local detected_services=()
    local service_types=()
    local ledger_paths=()
    local snapshot_paths=()
    local inc_snapshot_paths=()

    # Try Solana configurations first
    local solana_service_file="/root/solana/solana.service"
    local solana_script_file="/root/solana/validator.sh"

    # Try Firedancer configurations
    local firedancer_config="/home/firedancer/solana_fd/solana-testnet.toml"

    # Check for Solana service file
    if [ -f "$solana_service_file" ]; then
        detected_services+=("Solana service")
        service_types+=("solana")
        ledger_paths+=($(grep "\--ledger" "$solana_service_file" 2>/dev/null | awk '{ print $2 }'))
        snapshot_paths+=($(grep "\--snapshots" "$solana_service_file" 2>/dev/null | awk '{ print $2 }'))
        inc_snapshot_paths+=("")
        echo "Found Solana service file: $solana_service_file"
    fi

    # Check for Solana script file
    if [ -f "$solana_script_file" ] && [ ${#detected_services[@]} -eq 0 ]; then
        detected_services+=("Solana script")
        service_types+=("solana")
        ledger_paths+=($(grep "\--ledger" "$solana_script_file" 2>/dev/null | awk '{ print $2 }'))
        snapshot_paths+=($(grep "\--snapshots" "$solana_script_file" 2>/dev/null | awk '{ print $2 }'))
        inc_snapshot_paths+=($(grep "\--incremental-snapshot-archive-path" "$solana_script_file" 2>/dev/null | awk '{ print $2 }'))
        echo "Found Solana validator script: $solana_script_file"
    fi

    # Check for Firedancer config
    if [ -f "$firedancer_config" ]; then
        detected_services+=("Firedancer")
        service_types+=("firedancer")
        ledger_paths+=($(awk '/^\[ledger\]/ {in_ledger=1; next} /^\[/ && !/^\[ledger\]/ {in_ledger=0} in_ledger && $1=="path" {gsub(/"/, "", $3); print $3; exit}' "$firedancer_config" 2>/dev/null))
        snapshot_paths+=($(awk '/^\[snapshots\]/ {in_ledger=1; next} /^\[/ && !/^\[snapshots\]/ {in_ledger=0} in_ledger && $1=="path" {gsub(/"/, "", $3); print $3; exit}' "$firedancer_config" 2>/dev/null))
        inc_snapshot_paths+=("")
        echo "Found Firedancer config file: $firedancer_config"
    fi

    # If multiple services detected, prompt for selection
    if [ ${#detected_services[@]} -gt 1 ]; then
        echo "Multiple validator services detected. Please select which one to use:"
        for i in "${!detected_services[@]}"; do
            echo "[$i] ${detected_services[$i]}"
        done

        read -p "Enter selection number [0-$((${#detected_services[@]}-1))]: " selection

        # Validate input
        if ! [[ "$selection" =~ ^[0-9]+$ ]] || [ "$selection" -lt 0 ] || [ "$selection" -ge ${#detected_services[@]} ]; then
            echo "Invalid selection. Using the first option."
            selection=0
        fi

        # Set variables based on selection
        SERVICE_TYPE="${service_types[$selection]}"
        SERVICE_NAME="${service_types[$selection]}"
        LEDGER="${ledger_paths[$selection]}"
        SNAPSHOTS="${snapshot_paths[$selection]}"
        INC_SNAPSHOTS="${inc_snapshot_paths[$selection]}"

        echo "Selected ${detected_services[$selection]}."
    elif [ ${#detected_services[@]} -eq 1 ]; then
        # Only one service detected, use it
        SERVICE_TYPE="${service_types[0]}"
        SERVICE_NAME="${service_types[0]}"
        LEDGER="${ledger_paths[0]}"
        SNAPSHOTS="${snapshot_paths[0]}"
        INC_SNAPSHOTS="${inc_snapshot_paths[0]}"

        echo "Using the only detected service: ${detected_services[0]}"
    else
        echo "No configuration files found."
        return 1
    fi

    return 0
}

# Get network RPC URL from Solana CLI config
get_network_rpc_url() {
    local config_file="/root/.config/solana/cli/config.yml"

    networkrpcURL=$(grep json_rpc_url "$config_file" | grep -o '".*"' | tr -d '"')
    if [ -z "$networkrpcURL" ]; then
        networkrpcURL=$(grep json_rpc_url "$config_file" | awk '{ print $2 }')
    fi

    echo "Using RPC URL: $networkrpcURL"
}

# Wait for node to catch up to the network
catchup_info() {
    echo "Waiting for node to catch up..."

    while true; do
        if [ "$SERVICE_TYPE" == "solana" ]; then
            rpcPort=$(ps aux | grep solana-validator | grep -Po "\-\-rpc\-port\s+\K[0-9]+")
        else # firedancer
            config_path=$(ps aux | grep -v grep | grep 'fdctl run --config ' | sed -E 's/.*--config +([^[:space:]]+).*/\1/' | head -n 1)
            if [ -n "$config_path" ]; then
                rpcPort=$(awk '/^\[rpc\]/ {in_rpc=1; next} /^\[/ && !/^\[rpc\]/ {in_rpc=0} in_rpc && $1=="port" {gsub(/[^0-9]/, "", $3); print $3; exit}' "$config_path")
            else
                rpcPort=""
            fi
        fi

        if [ -z "$rpcPort" ]; then
            echo "RPC port not found. Waiting 30 seconds..."
            sleep 30
            continue
        fi

        echo "Checking catchup status on port $rpcPort..."
        if sudo -i -u root solana catchup --our-localhost "$rpcPort"; then
            echo "Catchup completed successfully!"
            return 0
        fi

        echo "Waiting 30 seconds before checking catchup again..."
        sleep 30
    done
}

# Download and run snapshot finder based on network
run_snapshot_finder() {
    local network="$1"
    local snapshot_path="$2"

    mkdir -p solana-snapshot-finder
    cd solana-snapshot-finder || exit 1

    echo "Downloading snapshot finder..."
    curl -o snapshot-finder https://raw.githubusercontent.com/ivan-leschinsky/solana-configs/master/binaries/snapshot-finder
    chmod +x snapshot-finder

    case "$network" in
        "https://api.testnet.solana.com")
            echo "Running snapshot finder for testnet..."
            ./snapshot-finder --snapshot_path "$snapshot_path" -r "$network" --max_latency 250 --min_download_speed 30
            ;;
        "https://api.mainnet-beta.solana.com")
            echo "Running snapshot finder for mainnet..."
            ./snapshot-finder --snapshot_path "$snapshot_path" --max_latency 100 --min_download_speed 60
            ;;
        "https://api.devnet.solana.com")
            echo "Running snapshot finder for devnet..."
            ./snapshot-finder --snapshot_path "$snapshot_path" -r "$network" --max_latency 500 --min_download_speed 20
            ;;
        *)
            echo "Unknown network: $network"
            exit 1
            ;;
    esac
}

# Move incremental snapshots if needed
handle_incremental_snapshots() {
    if [ -n "$INC_SNAPSHOTS" ]; then
        echo "Processing incremental snapshots..."

        if [ ! -d "$INC_SNAPSHOTS" ]; then
            mkdir -p "$INC_SNAPSHOTS"
        fi

        cd "$SNAPSHOTS" || exit 1
        echo "Moving incremental snapshots to $INC_SNAPSHOTS"
        mv incremental-snapshot* "$INC_SNAPSHOTS" 2>/dev/null || echo "No incremental snapshots to move"
    fi
}

load_helper_functions

print_multiline_header "Solana/Firedancer Snapshot Finder" \
    "This script will perform the following operations:" \
    "* stop validator service (solana or firedancer)" \
    "* delete ledger and snapshots" \
    "* download snapshot finder and run" \
    "* cluster definition and download snapshot" \
    "* wait for catchup" \
    "* start validator service" \
    "" \
    "*** Script provided by vano.one (originally MARGUS.ONE)"

find_service_configuration
get_network_rpc_url

if [ -z "$SERVICE_TYPE" ]; then
    echo "Error: No service configuration found!"
    exit 1
fi

cd /root/solana || exit 1

# Stop the appropriate service
echo "Stopping $SERVICE_NAME service..."
systemctl stop "$SERVICE_NAME"

# Check if ledger and snapshots paths are valid
if [ -z "$LEDGER" ] || [ -z "$SNAPSHOTS" ]; then
    echo "Error: Ledger or snapshots path not found. No removal will be performed."
else
    # Remove snapshots, but keep ledger for safety
    echo "Removing snapshots from $SNAPSHOTS"
    rm -fr "$SNAPSHOTS"/*
fi

# Create snapshots directory if it doesn't exist
if [ ! -d "$SNAPSHOTS" ]; then
    echo "Creating snapshots directory: $SNAPSHOTS"
    mkdir -p "$SNAPSHOTS"
fi

# Run snapshot finder based on network
run_snapshot_finder "$networkrpcURL" "$SNAPSHOTS"

# Handle incremental snapshots if needed
handle_incremental_snapshots

# Start the appropriate service
echo "Starting $SERVICE_NAME service..."
systemctl start "$SERVICE_NAME"

# Wait for catchup
catchup_info
