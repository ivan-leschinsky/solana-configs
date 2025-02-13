#!/bin/bash

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

SCRIPT_DIR="/root/status_checker"
CONFIG_FILE="$SCRIPT_DIR/config.conf"
MONITOR_SCRIPT="$SCRIPT_DIR/check_delinquent.sh"

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

# Create config directory if it doesn't exist
mkdir -p "$SCRIPT_DIR"

# Function to read existing configuration
read_existing_config() {
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
        return 0
    fi
    return 1
}

# Function to check if we want to use existing configuration
check_use_existing_config() {
    if read_existing_config; then
        echo "Found existing configuration:"
        echo "Network: $NETWORK"
        echo "Identity Address: $IDENTITY_ADDRESS"
        echo "Vote Account: $VOTE_ACCOUNT"
        echo "Uptime Kuma URL: $UPTIME_KUMA_URL"

        read -p "Would you like to keep this configuration and just update the scripts? (y/n): " use_existing
        if [[ $use_existing =~ ^[Yy]$ ]]; then
            return 0
        fi
    fi
    return 1
}

clean_url() {
  local url=$1
  # Remove everything after ? or & if present
  echo "$url" | sed 's/[?&].*$//'
}

# Function to validate Solana address
validate_address() {
    local address=$1
    if [[ ! $address =~ ^[1-9A-HJ-NP-Za-km-z]{32,44}$ ]]; then
        return 1
    fi
    return 0
}

# Function to get vote account from identity
get_vote_account() {
    local identity=$1
    local rpc_url=$2

    result=$(curl -s -X POST -H "Content-Type: application/json" -d '{
        "jsonrpc": "2.0",
        "id": 1,
        "method": "getProgramAccounts",
        "params": [
            "Vote111111111111111111111111111111111111111",
            {
                "encoding": "jsonParsed",
                "filters": [
                    {
                        "memcmp": {
                            "offset": 4,
                            "bytes": "'$identity'"
                        }
                    }
                ]
            }
        ]
    }' "$rpc_url")

    vote_account=$(echo "$result" | jq -r '.result[0].pubkey')

    if [ "$vote_account" = "null" ] || [ -z "$vote_account" ]; then
        return 1
    fi
    echo "$vote_account"
    return 0
}

# Function to safely update crontab
update_crontab() {
    local script_path=$1
    local temp_cron=$(mktemp)

    # Export current crontab
    crontab -l 2>/dev/null > "$temp_cron"

    # Check if entry already exists
    if grep -F "$script_path" "$temp_cron" >/dev/null 2>&1; then
        echo "Crontab entry already exists"
    else
        # Add new entry
        echo "*/2 * * * * $script_path" >> "$temp_cron"
        crontab "$temp_cron"
        echo "Added new crontab entry"
    fi

    # Clean up
    rm "$temp_cron"
}

# Try to get identity address automatically, then ask for confirmation or manual input
get_identity_address() {
  # Check if solana CLI is available
  if ! command -v solana &> /dev/null; then
    echo "Solana CLI not found. Please enter identity address manually."
    return 1
  fi

  # Try to get address from solana CLI
  local auto_address
  auto_address=$(solana address 2>/dev/null)

  if [ $? -eq 0 ] && [ ! -z "$auto_address" ]; then
    echo "Found identity address from Solana CLI: $auto_address"
    read -p "Use this address? (y/n): " use_auto
    if [[ $use_auto =~ ^[Yy]$ ]]; then
      echo "$auto_address"
      return 0
    fi
  fi

  return 1
}

# Main script execution
if check_use_existing_config; then
    print_header "Validator Monitor Setup: Using existing configuration..."
else
    print_header "Validator Monitor Setup"

    # Network selection
    while true; do
        echo "Select network:"
        echo "1) Mainnet"
        echo "2) Testnet"
        read -p "Enter choice (1-2): " network_choice

        case $network_choice in
            1)
                NETWORK="mainnet"
                RPC_URL="https://api.mainnet-beta.solana.com"
                break
                ;;
            2)
                NETWORK="testnet"
                RPC_URL="https://api.testnet.solana.com"
                break
                ;;
            *)
                echo "Invalid choice. Please select 1 or 2."
                ;;
        esac
    done

    # Identity address input
    while true; do
        # Try to get address automatically first
        auto_identity=$(get_identity_address)
        if [ $? -eq 0 ]; then
            IDENTITY_ADDRESS="$auto_identity"
            break
        fi

        # If automatic detection fails or is rejected, ask for manual input
        read -p "Enter validator identity address: " IDENTITY_ADDRESS
        if validate_address "$IDENTITY_ADDRESS"; then
            break
        else
            echo "Invalid address format. Please try again."
        fi
    done

    # Uptime Kuma URL input and cleaning
    while true; do
        read -p "Enter Uptime Kuma push URL: " raw_uptime_kuma_url

        # Clean the URL
        UPTIME_KUMA_URL=$(clean_url "$raw_uptime_kuma_url")

        # Validate URL format (basic check)
        if [[ $UPTIME_KUMA_URL =~ ^https?:// ]]; then
            echo "Cleaned URL: $UPTIME_KUMA_URL"
            break
        else
            echo "Invalid URL format. URL should start with http:// or https://"
        fi
    done

    # Get vote account
    echo "Finding vote account..."
    VOTE_ACCOUNT=$(get_vote_account "$IDENTITY_ADDRESS" "$RPC_URL")
    if [ $? -ne 0 ]; then
        echo "Error: Could not find vote account for this identity address"
        exit 1
    fi
    echo "Vote account found: $VOTE_ACCOUNT"

    # Create configuration file
    cat > "$CONFIG_FILE" << EOL
NETWORK="$NETWORK"
RPC_URL="$RPC_URL"
IDENTITY_ADDRESS="$IDENTITY_ADDRESS"
VOTE_ACCOUNT="$VOTE_ACCOUNT"
UPTIME_KUMA_URL="$UPTIME_KUMA_URL"
EOL
fi

# Create monitor script (this happens regardless of config choice)
cat > "$MONITOR_SCRIPT" << 'EOL'
#!/bin/bash

# Get the directory where the script is located
SCRIPT_DIR="/root/status_checker"
CONFIG_FILE="$SCRIPT_DIR/config.conf"

# Load configuration
source "$CONFIG_FILE"

# Function to check if validator is delinquent
check_delinquent() {
    local address=$1
    local rpc_url=$2

    result=$(curl -s -X POST -H "Content-Type: application/json" -d '{
        "jsonrpc": "2.0",
        "id": 1,
        "method": "getVoteAccounts",
        "params": []
    }' "$rpc_url")

    # Check in delinquent validators
    if echo "$result" | jq -r '.result.delinquent[].votePubkey' | grep -q "$address"; then
        return 0  # Delinquent
    else
        # Check in current validators
        if echo "$result" | jq -r '.result.current[].votePubkey' | grep -q "$address"; then
            return 1  # Active
        else
            return 2  # Not found
        fi
    fi
}

# Check delinquent status
check_delinquent "$VOTE_ACCOUNT" "$RPC_URL"
status=$?

# Prepare status message
case $status in
    0)
        status_msg="DOWN"
        status_code="down"
        ;;
    1)
        status_msg="UP"
        status_code="up"
        ;;
    2)
        status_msg="UNKNOWN"
        status_code='unknown'
        ;;
esac

# Send status to Uptime Kuma
if [[ "$UPTIME_KUMA_URL" == *"?"* ]]; then
    curl -s "${UPTIME_KUMA_URL}&status=$status_code&msg=Validator%20is%20$status_msg"
else
    curl -s "${UPTIME_KUMA_URL}?status=$status_code&msg=Validator%20is%20$status_msg"
fi
EOL

# Make monitor script executable
chmod +x "$MONITOR_SCRIPT"

# Add to crontab (every 5 minutes) if not already present
update_crontab "$MONITOR_SCRIPT"

echo "Setup completed!"
echo "Configuration saved to: $CONFIG_FILE"
echo "Monitor script installed at: $MONITOR_SCRIPT"
echo "Monitor will run every 2 minutes"

# Optional: Run the monitor script immediately for testing
read -p "Would you like to test the monitor script now? (y/n) " test_now
if [[ $test_now =~ ^[Yy]$ ]]; then
    echo "Running monitor script..."
    "$MONITOR_SCRIPT"
fi
