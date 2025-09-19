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

# Function to check if running as root
check_root() {
  if [ "$EUID" -ne 0 ]; then
    return 1
  fi
  return 0
}

# Function to create beautiful multiline header with title
print_multiline_header() {
  local title="$1"
  shift
  local lines=("$@")

  # Get terminal width (default 80)
  local terminal_width=$(tput cols 2>/dev/null || echo 80)

  # Function to get actual display length of text (accounting for emoji visual width)
  get_visual_length() {
    local text="$1"
    # Remove color codes for measurement
    local clean_text=$(echo -e "$text" | sed 's/\x1b\[[0-9;]*m//g')

    echo ${#clean_text}
  }

  # Find the longest line for consistent width
  local max_width=0
  local title_width=$(get_visual_length "$title")
  if [ $title_width -gt $max_width ]; then
    max_width=$title_width
  fi

  for line in "${lines[@]}"; do
    if [ -n "$line" ]; then
      local line_width=$(get_visual_length "$line")
      if [ $line_width -gt $max_width ]; then
        max_width=$line_width
      fi
    fi
  done

  # Add padding and ensure minimum width
  local content_width=$((max_width + 2))  # 4 extra chars for padding
  if [ $content_width -lt 60 ]; then
    content_width=60
  fi

  # Limit to terminal width
  if [ $content_width -gt $((terminal_width - 4)) ]; then
    content_width=$((terminal_width - 4))
  fi

  local total_width=$((content_width + 6))  # 6 = 2 borders + 4 spaces

  # Create border lines
  local border_line=$(printf '═%.0s' $(seq 1 $((total_width - 2))))
  local space_line=$(printf ' %.0s' $(seq 1 $((total_width - 2))))

  # Print header
  echo -e "${CYAN}"
  echo "╔${border_line}╗"

  # Print title - manually pad to avoid printf issues with emoji
  local title_visual_len=$(get_visual_length "$title")
  local title_padding=$((content_width - title_visual_len))
  printf "║  ${BOLD}%s${NC}%*s  ║\n" "$title" $title_padding ""

  echo "╠${border_line}╣"

  # Print content lines
  for linetext in "${lines[@]}"; do
    if [ -z "$linetext" ]; then
      # Empty line - match the content width + padding
      printf "║  %*s  ║\n" $content_width ""
    else
      # Content line - manually pad to avoid printf issues with emoji
      local line_visual_len=$(get_visual_length "$linetext")
      local line_padding=$((content_width - line_visual_len))
      echo -n "║  ${linetext}"
      printf "%*s" $line_padding ""
      echo "  ║"
    fi
  done

  # Print bottom border
  echo "╚${border_line}╝"
  echo -e "${NC}"
}

# Function to check if solana CLI is installed
check_solana_cli() {
  if ! command -v solana &> /dev/null; then
    echo -e "${YELLOW}⚠️  Solana CLI is not installed. Please install it first.${NC}"
    exit 1
  fi
}

# Function to ask a question with yes/no response
# Usage examples:
#   ask_yes_no "Do you want to proceed?" "y"  # Default to yes
#   ask_yes_no "Delete all files?" "n"        # Default to no
#   ask_yes_no "Continue installation?"       # No default, must explicitly answer
ask_yes_no() {
  local question="$1"
  local default="${2:-}"  # Default value (y/n or empty)

  local prompt="$question"
  local default_upper=""

  # Format the prompt based on the default value
  if [ "$default" = "y" ] || [ "$default" = "Y" ]; then
    prompt="$question [Y/n] "
    default_upper="Y"
  elif [ "$default" = "n" ] || [ "$default" = "N" ]; then
    prompt="$question [y/N] "
    default_upper="N"
  else
    prompt="$question [y/n] "
    default_upper=""
  fi

  local answer
  while true; do
    echo -en "${CYAN}$prompt${NC}"
    read -r answer

    # Convert to lowercase for comparison
    answer=$(echo "$answer" | tr '[:upper:]' '[:lower:]')

    # Handle empty response with default
    if [ -z "$answer" ] && [ -n "$default" ]; then
      answer=$(echo "$default" | tr '[:upper:]' '[:lower:]')
    fi

    case "$answer" in
      y|yes) return 0 ;;
      n|no) return 1 ;;
      *) echo -e "${YELLOW}⚠️  Please answer with 'yes' or 'no' (or y/n).${NC}" ;;
    esac
  done
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
      echo -e "${YELLOW}⚠️  This script needs sudo privileges to install packages.${NC}"
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
