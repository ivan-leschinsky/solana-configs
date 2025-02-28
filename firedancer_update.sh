#!/bin/bash

set -e

# Initialize helper UI functions
eval "$(curl -fsSL https://raw.githubusercontent.com/ivan-leschinsky/solana-configs/master/helper.sh)"

print_multiline_header "Solana Firedancer Updater" \
    "This script will perform the following operations" \
    "Update installed firedancer to the latest version or to the specified version from an argument" \
    "" \
    "Author: vano.one"



# Ensure the script is run as root
if [[ $EUID -ne 0 ]]; then
  echo -e "${RED}❌ This script must be run as root. Please run it with 'sudo' or as root user.${NC}"
  exit 1
fi

if [ -n "$1" ] && [ ${#1} -gt 8 ]; then
  NEW_VERSION="$1"
else
  echo -e "${RED}❌ Need to pass version as argument to this script.${NC}"
fi

print_header "Starting updating Firedancer to the $NEW_VERSION..."

update_fd() {
  USERNAME="firedancer"
  USER_ID=$(id -u "$USERNAME")
  GROUP_ID=$(id -g "$USERNAME")

  cd /root/firedancer
  git checkout $NEW_VERSION
  git submodule update --init --recursive
  sed -i "/^[ \t]*results\[ 0 \] = pwd\.pw_uid/c results[ 0 ] = $USER_ID;" ~/firedancer/src/app/fdctl/config.c
  sed -i "/^[ \t]*results\[ 1 \] = pwd\.pw_gid/c results[ 1 ] = $GROUP_ID;" ~/firedancer/src/app/fdctl/config.c

  ./deps.sh </dev/tty
  make -j fdctl solana
}

stop_fd() {
  service firedancer stop
  cp /root/firedancer/build/native/gcc/bin/* /usr/local/bin/
  # service firedancer start
}

update_fd
stop_fd

print_multiline_header "Almost finished" \
    "Nowreboot server and run immediately after boot: \033[0;32mfdctl configure init hugetlbfs\033[0m" \
    "${GREEN}fdctl configure init all --config /home/firedancer/solana_fd/solana-testnet.toml${NC}" \
    "${GREEN}service firedancer start${NC}" \
    "" \
    "Good luck"
