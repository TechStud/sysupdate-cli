#!/bin/bash
# ==============================================================================
# Script Name   : sysupdate-cli (sysupdates.sh)
# Description   : Styled, interactive system package manager wrapper for Debian/Ubuntu.
# Author        : TechStud
# Repository    : https://github.com/TechStud/sysupdate-cli
# License       : MIT License
# Created       : 2026
# ==============================================================================

set -e

# ==============================================================================
# Privilege Elevation Check
# ==============================================================================
if [ "$EUID" -ne 0 ]; then
    YELLOW='\033[1;33m'
    CYAN='\033[1;36m'
    GREEN='\033[1;32m'
    RED='\033[1;31m'
    NC='\033[0m'

    echo -e "${NC}"
    echo -e "${YELLOW}┌──[ PRIVILEGE NOTICE ]──────────────────────────────────────────╮${NC}"
    echo -e "${YELLOW}│${NC} This script requires elevated permissions (sudo) to query and  "
    echo -e "${YELLOW}│${NC} update system package registries using 'apt'.                  "
    echo -e "${YELLOW}└────────────────────────────────────────────────────────────────╯${NC}"
    
    echo -ne " ${CYAN}Proceed with sudo elevation? [Y/n]: ${NC}"
    read -r elevate_confirm || true
    elevate_confirm="${elevate_confirm:-y}"

    if [[ "$elevate_confirm" =~ ^[yY](es)?$ ]]; then
        echo -e " ${GREEN}✔ Relaunching with sudo privileges...${NC}\n"
        SCRIPT_PATH="$(realpath "$0")"
        exec sudo -E "$SCRIPT_PATH" "$@"
    else
        echo -e "${NC}\n ${RED}✖ Operation canceled. Elevated privileges are required to run.${NC}\n"
        exit 1
    fi
fi

# Terminal Color Palette & Styling
BOLD='\033[1m'
DIM='\033[2m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
MAGENTA='\033[1;35m'
NC='\033[0m'

# File path configurations
LOG_FILE="/var/log/sysupdates.log"
REBOOT_REQUIRED_FILE="/var/run/reboot-required"

# Default variable assignment
REPORT_ONLY=false
VERBOSE=false
STEP_CURR=0
TOTAL_STEPS=3

# Reset Option Pointer & Parse Options
OPTIND=1
while getopts ":rvh" opt; do
  case ${opt} in
    r) REPORT_ONLY=true ;;
    v) VERBOSE=true ;;
    h)
      echo "Usage: sudo $0 [-r] [-v] [-h]"
      echo "  -r, --report-only    Preview upgradable packages without applying changes."
      echo "  -v, --verbose        Stream full apt progress logs."
      echo "  -h, --help           Display this help screen."
      exit 0
      ;;
    \?)
      echo -e "${NC}${RED}✖ Invalid option: -$OPTARG${NC}" >&2
      exit 1
      ;;
  esac
done

# Adjust Total Steps if running Report-Only mode
if [ "$REPORT_ONLY" = true ]; then
    TOTAL_STEPS=2
fi

# Helper: Visual Section Headers with Dynamic Step Counting
print_banner() {
    STEP_CURR=$((STEP_CURR + 1))
    local title="[$STEP_CURR/$TOTAL_STEPS] $1"
    echo -e "${NC}\n${CYAN}╭$(printf '─%.0s' {1..60})╮${NC}"
    echo -e "${NC}${CYAN}│${NC} ${BOLD}${title}${NC}"
    echo -e "${NC}${CYAN}╰$(printf '─%.0s' {1..60})╯${NC}"
}

# Helper: Command execution wrapped for quiet vs verbose execution
run_cmd() {
    if [ "$VERBOSE" = true ]; then
        "$@"
    else
        "$@" > /dev/null 2>&1
    fi
}

# ==============================================================================
# Step 1: Sync Package Registries
# ==============================================================================
print_banner "Syncing Package Registries"

if [ "$VERBOSE" = true ]; then
    apt-get -o APT::Color=1 update
    echo -e "${NC}\n  ${GREEN}✔ Package registries updated successfully.${NC}"
else
    update_output=$(apt-get update 2>&1) || update_status=$?

    if [ "${update_status:-0}" -eq 0 ]; then
        parsed_repos=$(echo "$update_output" | grep -E '^(Hit|Get|Ign)' | awk '{print $2}' | cut -d'/' -f3 | sort -u)
        updated_repos=$(echo "$update_output" | grep '^Get:' | awk '{print $2}' | cut -d'/' -f3 | sort -u)
        
        total_sources=$(echo "$update_output" | grep -cE '^(Hit|Get|Ign)' || true)
        hits=$(echo "$update_output" | grep -c '^Hit:' || true)
        gets=$(echo "$update_output" | grep -c '^Get:' || true)
        igns=$(echo "$update_output" | grep -c '^Ign:' || true)

        echo -e "  ${NC}${CYAN}➜ Synced ${total_sources} repository endpoints across active mirrors:${NC}"
        
        while read -r domain; do
            if [ -n "$domain" ]; then
                if echo "$updated_repos" | grep -q "^${domain}$"; then
                    echo -e "    ${YELLOW}• ${domain} (Updated)${NC}"
                else
                    echo -e "    ${DIM}• ${domain}${NC}"
                fi
            fi
        done <<< "$parsed_repos"

        echo -e "  ${NC}${CYAN}➜ Sync Summary:${NC} ${GREEN}${hits} Unchanged (Hit)${NC} | ${YELLOW}${gets} Updated (Get)${NC} | ${DIM}${igns} Ignored${NC}\n"
        echo -e "  ${NC}${GREEN}✔ All package registries synchronized successfully.${NC}"
    else
        echo -e "${NC}\n${RED}========================================================================"
        echo -e "CRITICAL ERROR: Failed to synchronize package registries."
        echo "$update_output" | grep -i 'err:'
        echo -e "========================================================================${NC}"
        exit 1
    fi
fi

# ==============================================================================
# Step 2: Analyze Upgradable Packages (Table Output)
# ==============================================================================
print_banner "Analyzing Upgradable Packages"

raw_apt_output=$(apt list --upgradable 2>/dev/null | tail -n +2 || true)

if [ -z "$raw_apt_output" ]; then
    echo -e " ${NC}${GREEN}✔ Your system is fully up to date! No updates available.${NC}\n"
    exit 0
else
    pkg_count=$(echo "$raw_apt_output" | wc -l)
    echo -e " ${NC}${YELLOW}▲ Found ${pkg_count} package(s) available for upgrade:${NC}\n"

    formatted_table=$(
        (
            echo -e "${NC}${BOLD}APPLICATION NAME${NC}||${BOLD}CURRENT VERSION${NC}||${BOLD}UPGRADABLE VERSION${NC}"
            echo -e "${NC}${DIM}----------------${NC}||${DIM}---------------${NC}||${DIM}------------------${NC}"

            while read -r line; do
                [ -z "$line" ] && continue
                pkg_name=$(echo "$line" | cut -d'/' -f1)
                next_version=$(echo "$line" | awk '{print $2}')
                curr_version=$(echo "$line" | grep -oP '(?<=upgradable from: ).*(?=])' || true)

                curr_version=$(echo "$curr_version" | sed -E 's/~ubuntu\.[0-9]{2}\.[0-9]{2}~[a-z]+$//')
                next_version=$(echo "$next_version" | sed -E 's/~ubuntu\.[0-9]{2}\.[0-9]{2}~[a-z]+$//')

                if [ -z "$curr_version" ]; then curr_version="Unknown"; fi

                echo -e "${NC}${CYAN}${pkg_name}${NC}||${DIM}${curr_version}${NC}||${GREEN}${next_version}${NC}"
            done <<< "$raw_apt_output"
        ) | column -t -s "||"
    )

    echo "${NC}$formatted_table" | sed 's/^/  /'
    echo ""
fi

if [ "$REPORT_ONLY" = true ]; then
    echo -e "${NC}${YELLOW}ℹ Report mode active. No system modifications applied.${NC}\n"
    exit 0
fi

# Predictive Reboot Check
reboot_packages_pattern="linux-image|linux-generic|linux-headers|linux-firmware|libc6|systemd|dbus|snapd"
predict_reboot=false

if echo "$raw_apt_output" | grep -qE "$reboot_packages_pattern"; then
    predict_reboot=true
fi

echo -e "${MAGENTA}┌──[ ACTION REQUIRED ]───────────────────────────────────────────╮${NC}"
if [ "$predict_reboot" = true ]; then
    echo -e "${MAGENTA}│${NC} ${YELLOW}⚠️  Note: This update includes core components that may${NC}"
    echo -e "${MAGENTA}│${NC} ${YELLOW}           require a system reboot once applied.${NC}"
    echo -e "${MAGENTA}├────────────────────────────────────────────────────────────────╯${NC}"
fi
echo -ne "${MAGENTA}│${NC} Apply these updates now? [Y/n]: "
read -r confirm || true
confirm="${confirm:-y}"
echo -e "${MAGENTA}└───${NC}"

if [[ ! "$confirm" =~ ^[yY](es)?$ ]]; then
    echo -e "${NC}\n${YELLOW}⚠ Upgrade sequence canceled by user.${NC}\n"
    exit 0
fi

# ==============================================================================
# Step 3: Apply Package Updates
# ==============================================================================
print_banner "Applying Package Updates"

echo -e "  ${NC}${CYAN}➜ Upgrading system packages (including phased updates)...${NC}"

APT_OPTS="-o APT::Get::Always-Include-Phased-Updates=true -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold"

if [ "$VERBOSE" = true ]; then
    apt-get dist-upgrade -y $APT_OPTS
else
    DEBIAN_FRONTEND=noninteractive apt-get dist-upgrade -y -qq $APT_OPTS > /dev/null 2>&1 || {
        echo -e "  ${NC}${RED}✖ Package upgrade failed! Run with -v to inspect details.${NC}"
        exit 1
    }
fi

echo -e "${NC}\n${CYAN}➜ Cleaning up obsolete cached packages...${NC}"
run_cmd apt-get autoremove -y
run_cmd apt-get clean
echo -e " ${GREEN}✔ Cleanup complete.${NC}"

# Write Transaction Log
{
    echo "[TRANSACTION_START] $(date '+%Y-%m-%d %H:%M:%S')"
    echo "=================================================================="
    echo "The following packages were successfully upgraded:"
    echo ""
    echo "$formatted_table" | sed 's/\x1b\[[0-9;]*m//g'
    echo "=================================================================="
    echo "[TRANSACTION_END]"
    echo ""
} >> "$LOG_FILE"

# Reboot Verification Check
if [ -f "$REBOOT_REQUIRED_FILE" ]; then
    echo -e "${NC}"echo -e "\n${RED}┌──[ REBOOT REQUIRED ]───────────────────────────────────────────╮${NC}"
    echo -e "${RED}│${NC} Core updates (Kernel or Snap components) require a system reboot.${NC}"
    echo -e "${RED}└───${NC}"
    echo -e " ${GREEN}✔ Log saved to: ${YELLOW}$LOG_FILE${NC}\n"

    echo -ne "${RED}Reboot system right now? [y/N]: ${NC}"
    read -r reboot_confirm || true
    reboot_confirm="${reboot_confirm:-n}"

    if [[ "$reboot_confirm" =~ ^[yY](es)?$ ]]; then
        echo -e "${NC}${GREEN}Restarting machine...${NC}"
        reboot
    else
        echo -e "${NC}${YELLOW}Reboot skipped. Please reboot manually when convenient.${NC}\n"
    fi
else
    echo -e "${NC}\n${GREEN}✔ System updates applied successfully! No reboot required.${NC}"
    echo -e "${NC} ${GREEN}✔ Log saved to: ${YELLOW}$LOG_FILE${NC}\n"
fi
