#!/bin/bash

set -e

# Initialize helper UI functions
eval "$(curl -fsSL https://raw.githubusercontent.com/ivan-leschinsky/solana-configs/v2.9/helper.sh)"

print_multiline_header "Solana Firedancer Updater v2.9" \
    "This script will perform the following operations" \
    "Update installed firedancer to the latest version or to the specified version from an argument" \
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

  cd /root/firedancer
  git checkout .
  git fetch
  git checkout $NEW_VERSION
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
      cp /root/firedancer/build/native/gcc/bin/* /usr/local/bin/
      break
    fi

    sleep 5
  done
}

stop_fd() {
  service firedancer stop
  sleep 5
  # cp /root/firedancer/build/native/gcc/bin/* /usr/local/bin/
  # service firedancer start
}

if check_root; then
  update_fd
  stop_fd
  copy_when_free

  echo

  print_multiline_header "Almost finished" \
    "Now reboot server and run immediately after boot: \033[0;32mfdctl configure init hugetlbfs\033[0m" \
    "${GREEN}fdctl configure init all --config /home/firedancer/solana_fd/solana-testnet.toml${NC}" \
    "${GREEN}service firedancer start${NC}" \
    "" \
    "You can also try to start directly: ${GREEN}service firedancer start${NC}" \
    "and then check status with: ${GREEN}service firedancer status${NC}" \
    "if it works fine - no need to reboot the server" \
    "" \
    "Good luck"
else
  echo -e "${RED}❌ This script must be run as root user.${NC}"
  exit 1
fi
