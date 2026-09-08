#!/bin/bash

# ==============================================================================
# Script Name   : sysupdate-cli (sysupdates.sh)
# Description   : Styled, interactive system package manager wrapper for Debian/Ubuntu.
# Author        : TechStud
# Repository    : https://github.com/TechStud/sysupdate-cli
# License       : MIT License
# Created       : 2026
# ==============================================================================

# Exit immediately if a command exits with a non-zero status
set -e

# Professional Terminal Color Palette & Styling
BOLD='\033[1m'
DIM='\033[2m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
MAGENTA='\033[1;35m'
NC='\033[0m' # No Color

# File path configurations
LOG_FILE="/var/log/sysupdates.log"
REBOOT_REQUIRED_FILE="/var/run/reboot-required"

# Default variable assignment
REPORT_ONLY=false
VERBOSE=false

# Helper: Visual Section Headers
print_banner() {
    local title="$1"
    echo -e "\n${CYAN}╭$(printf '─%.0s' {1..60})╮${NC}"
    echo -e "${CYAN}│${NC} ${BOLD}${title}${NC}"
    echo -e "${CYAN}╰$(printf '─%.0s' {1..60})╯${NC}"
}

# Helper: Command execution wrapped for quiet vs verbose execution
run_cmd() {
    if [ "$VERBOSE" = true ]; then
        "$@"
    else
        "$@" > /dev/null 2>&1
    fi
}

# Help Function
show_help() {
    echo "Usage: sudo $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -r, --report-only    Only fetch and display the upgradable packages table. Do not upgrade."
    echo "  -v, --verbose        Show raw command output (apt update/upgrade streams) for troubleshooting."
    echo "  -h, --help           Show this help message and exit."
    echo ""
}

# Parse command line flags
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -r|--report-only) REPORT_ONLY=true; shift ;;
        -v|--verbose) VERBOSE=true; shift ;;
        -h|--help) show_help; exit 0 ;;
        *) echo -e "${RED}✖ Unknown option: $1${NC}"; show_help; exit 1 ;;
    esac
done

# Step 1: Root privilege check
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}✖ Error: This script must be run with sudo privileges.${NC}"
    exit 1
fi

print_banner " [1/2] Syncing Package Registries"

# If verbose mode is enabled, run apt-get update directly to stream full logs
if [ "$VERBOSE" = true ]; then
    apt-get -o APT::Color=1 update
    
    echo -e "\n  ${GREEN}✔ Package registries updated successfully.${NC}"
else
    # Non-verbose mode: Parse apt output for summary metrics
    update_output=$(apt-get update 2>&1) || update_status=$?

    if [ "${update_status:-0}" -eq 0 ]; then
        # Parse domains for all synced endpoints
        parsed_repos=$(echo "$update_output" | grep -E '^(Hit|Get|Ign)' | awk '{print $2}' | cut -d'/' -f3 | sort -u)
        
        # Parse domains specifically for endpoints with actual updates (Get)
        updated_repos=$(echo "$update_output" | grep '^Get:' | awk '{print $2}' | cut -d'/' -f3 | sort -u)
        
        total_sources=$(echo "$update_output" | grep -cE '^(Hit|Get|Ign)' || true)
        hits=$(echo "$update_output" | grep -c '^Hit:' || true)
        gets=$(echo "$update_output" | grep -c '^Get:' || true)
        igns=$(echo "$update_output" | grep -c '^Ign:' || true)

        echo -e "  ${CYAN}➜ Synced ${total_sources} repository endpoints across active mirrors:${NC}"
        
        while read -r domain; do
            if [ -n "$domain" ]; then
                # Highlight active domains in Yellow if they fetched updates (Get), otherwise Dimmed
                if echo "$updated_repos" | grep -q "^${domain}$"; then
                    echo -e "    ${YELLOW}• ${domain} (Updated)${NC}"
                else
                    echo -e "    ${DIM}• ${domain}${NC}"
                fi
            fi
        done <<< "$parsed_repos"

        echo -e "  ${CYAN}➜ Sync Summary:${NC} ${GREEN}${hits} Unchanged (Hit)${NC} | ${YELLOW}${gets} Updated (Get)${NC} | ${DIM}${igns} Ignored${NC}\n"
        echo -e "  ${GREEN}✔ All package registries synchronized successfully.${NC}"
    else
        echo -e "\n${RED}========================================================================"
        echo -e "CRITICAL ERROR: Failed to synchronize package registries."
        echo "$update_output" | grep -i 'err:'
        echo -e "========================================================================${NC}"
        exit 1
    fi
fi


print_banner " [2/2] Analyzing Upgradable Packages"

# Extract raw apt data
raw_apt_output=$(apt list --upgradable 2>/dev/null | tail -n +2)

if [ -z "$raw_apt_output" ]; then
    echo -e " ${GREEN}✔ Your system is fully up to date! No updates available.${NC}\n"
    exit 0
else
    pkg_count=$(echo "$raw_apt_output" | wc -l)
    echo -e " ${YELLOW}▲ Found ${pkg_count} package(s) available for upgrade:${NC}\n"

    # Build formatted table string
    formatted_table=$(
        (
            echo -e "${BOLD}APPLICATION NAME${NC}||${BOLD}CURRENT VERSION${NC}||${BOLD}UPGRADABLE VERSION${NC}"
            echo -e "${DIM}----------------${NC}||${DIM}---------------${NC}||${DIM}------------------${NC}"

            while read -r line; do
                pkg_name=$(echo "$line" | cut -d'/' -f1)
                next_version=$(echo "$line" | awk '{print $2}')
                curr_version=$(echo "$line" | grep -oP '(?<=upgradable from: ).*(?=])')

                # Trim release tag suffixes (~ubuntu.xx.xx~codename)
                curr_version=$(echo "$curr_version" | sed -E 's/~ubuntu\.[0-9]{2}\.[0-9]{2}~[a-z]+$//')
                next_version=$(echo "$next_version" | sed -E 's/~ubuntu\.[0-9]{2}\.[0-9]{2}~[a-z]+$//')

                if [ -z "$curr_version" ]; then curr_version="Unknown"; fi

                # Colorize version outputs for terminal display
                echo -e "${CYAN}${pkg_name}${NC}||${DIM}${curr_version}${NC}||${GREEN}${next_version}${NC}"
            done <<< "$raw_apt_output"
        ) | column -t -s "||"
    )

    # Print table with left padding margin
    echo "$formatted_table" | sed 's/^/  /'
    echo ""
fi

# Step 3: Branch logic depending on configuration flags
if [ "$REPORT_ONLY" = true ]; then
    echo -e "${YELLOW}ℹ Report mode active. No system modifications applied.${NC}\n"
    exit 0
fi

# Check if any package in the upgrade list is known to require a reboot
reboot_packages_pattern="linux-image|linux-generic|linux-headers|linux-firmware|libc6|systemd|dbus|snapd"
predict_reboot=false

if echo "$raw_apt_output" | grep -qE "$reboot_packages_pattern"; then
    predict_reboot=true
fi

# Visual Action Callout Box
echo -e "${MAGENTA}┌──[ ACTION REQUIRED ]───────────────────────────────────────────╮${NC}"
if [ "$predict_reboot" = true ]; then
    echo -e "${MAGENTA}│${NC} ${YELLOW}⚠️  Note: This update includes core components that may${NC}"
    echo -e "${MAGENTA}│${NC} ${YELLOW}           require a system reboot once applied.${NC}"
    echo -e "${MAGENTA}├────────────────────────────────────────────────────────────────╯${NC}"
fi
echo -ne "${MAGENTA}│${NC} Apply these updates now? [Y/n]: "
read confirm
echo -e "${MAGENTA}└───${NC}"

confirm="${confirm:-y}"

if [[ ! "$confirm" =~ ^[yY](es)?$ ]]; then
    echo -e "\n${YELLOW}⚠ Upgrade sequence canceled by user.${NC}\n"
    exit 0
fi

print_banner " Applying Package Updates"

if [ "$VERBOSE" = true ]; then
    apt-get upgrade -y
else
    apt-get upgrade -y > /dev/null 2>&1
fi

echo -e "\n${CYAN}➜ Cleaning up obsolete cached packages...${NC}"
run_cmd apt-get autoremove -y
run_cmd apt-get clean
echo -e " ${GREEN}✔ Cleanup complete.${NC}"

# Log processing
{
    echo "[TRANSACTION_START] $(date '+%Y-%m-%d %H:%M:%S')"
    echo "=================================================================="
    echo "The following packages were successfully upgraded:"
    echo ""
    # Strip terminal ANSI color codes before saving table to log file
    echo "$formatted_table" | sed 's/\x1b\[[0-9;]*m//g'
    echo "=================================================================="
    echo "[TRANSACTION_END]"
    echo ""
} >> "$LOG_FILE"

# Reboot Verification Check
if [ -f "$REBOOT_REQUIRED_FILE" ]; then
    echo -e "\n${RED}┌──[ REBOOT REQUIRED ]───────────────────────────────────────────╮${NC}"
    echo -e "${RED}│${NC} Core updates (Kernel or Snap components) require a system reboot."
    echo -e "${RED}└───${NC}"
    echo -e " ${GREEN}✔ Log saved to: ${YELLOW}$LOG_FILE${NC}\n"

    echo -ne "${RED}Reboot system right now? [y/N]: ${NC}"
    read reboot_confirm
    reboot_confirm="${reboot_confirm:-n}"

    if [[ "$reboot_confirm" =~ ^[yY](es)?$ ]]; then
        echo -e "${GREEN}Restarting machine...${NC}"
        reboot
    else
        echo -e "${YELLOW}Reboot skipped. Please reboot manually when convenient.${NC}\n"
    fi
else
    echo -e "\n${GREEN}✔ System updates applied successfully! No reboot required.${NC}"
    echo -e " ${GREEN}✔ Log saved to: ${YELLOW}$LOG_FILE${NC}\n"
fi
