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

# Terminal Color Palette
BOLD='\033[1m'
DIM='\033[2m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
MAGENTA='\033[1;35m'
NC='\033[0m'

# Gracefully handle Ctrl+C interruptions without leaving background processes dangling
trap 'echo; echo -e "\n${NC}${RED}✖ Operation interrupted.${NC}\n  ↳ If a package operation was in progress, run: sudo dpkg --configure -a"; exit 130' INT

# Default variable assignment
REPORT_ONLY=false
VERBOSE=false
STEP_CURR=0
TOTAL_STEPS=3

OPTIND=1
while getopts ":rvh" opt; do
  case ${opt} in
    r) REPORT_ONLY=true ;;
    v) VERBOSE=true ;;
    h)
      echo "Usage: sudo $0 [-r] [-v] [-h]"
      echo "  -r   (report-only) Preview upgradable packages without applying changes."
      echo "  -v   (verbose)     Stream full apt progress logs."
      echo "  -h   (help)        Display this help screen."
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

# File path configurations
LOG_FILE="/var/log/sysupdates.log"
REBOOT_REQUIRED_FILE="/var/run/reboot-required"

# Secure log initialization
if [ ! -f "$LOG_FILE" ]; then
    touch "$LOG_FILE" && chmod 666 "$LOG_FILE"
fi

# Lightweight log event helper
log_event() {
    local event="$1" detail="${2:-}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ${event}${detail:+ | ${detail}}" >> "$LOG_FILE"
}

# Helper: Visual Section Headers with Dynamic Step Counting
print_banner() {
    STEP_CURR=$((STEP_CURR + 1))
    local title="[$STEP_CURR/$TOTAL_STEPS] $1"
    echo -e "${NC}\n${CYAN}┌$(printf '─%.0s' {1..60})┐${NC}"
    echo -e "${NC}${CYAN}│${NC} ${BOLD}${title}${NC}"
    echo -e "${NC}${CYAN}└$(printf '─%.0s' {1..60})┘${NC}"
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
# Privilege Elevation Check
# ==============================================================================
if [ "$EUID" -ne 0 ]; then
    SCRIPT_PATH="$(realpath "$0")"
    SUDO_CACHED=false

    # ==============================================================================
    # Session Header
    # ==============================================================================
    if sudo -n true 2>/dev/null; then
        SUDO_CACHED=true
    fi
    DISTRO_NAME=$(. /etc/os-release && echo "$PRETTY_NAME")
    KERNEL=$(uname -r)
    HOSTNAME=$(hostname)
    LAST_LOG=$(grep 'TRANSACTION_START' "$LOG_FILE" 2>/dev/null | tail -1 | grep -oP '^\[\K[^\]]+')   
    log_event "SESSION_START" "=================================================================="
    log_event "ENVIRONMENT" "hostname=${HOSTNAME} user=${USER} distro=${DISTRO_NAME} kernel=${KERNEL} last_run=${LAST_LOG}"
    echo ""
    echo -e "${NC}${CYAN}┌──[ sysupdate-cli ]───────────────────────────────────────┐${NC}"
    echo -e "${NC}${CYAN}|${NC} ${DIM}Makes routine Linux system maintenance effortless, by turning${NC}"
    echo -e "${NC}${CYAN}|${NC}   ${DIM}complicated updates into a simple, transparent process that${NC}"
    echo -e "${NC}${CYAN}|${NC}   ${DIM}puts users in control of keeping their systems clean, secure,${NC}"
    echo -e "${NC}${CYAN}|${NC}   ${DIM}and up to date.${NC}"
    echo -e "${NC}${CYAN}│${NC}  ${DIM}A modern take on the boring apt update && apt upgrade process${NC}"
    echo -e "${NC}${CYAN}├$(printf '─%.0s' {1..64})┤${NC}\n"
    echo -e "${NC}${CYAN}│${NC}  ${GREEN}●${NC} Distro:    ${DISTRO_NAME}${NC}"
    echo -e "${NC}${CYAN}│${NC}  ${GREEN}●${NC} Kernel:    ${KERNEL}${NC}"
    echo -e "${NC}${CYAN}│${NC}  ${GREEN}●${NC} Host:      ${HOSTNAME}${NC}"
    if $SUDO_CACHED; then
        echo -e "${NC}${CYAN}│${NC}  ${GREEN}●${NC} User:      ${USER} ${GREEN}${DIM}(✔ sudo detected)${NC}"
    else
        echo -e "${NC}${CYAN}│${NC}  ${GREEN}●${NC} User:      ${USER} ${RED}${DIM}(✖ sudo not-detected)${NC}"
    fi
    log_event "SUDO_DETECTED" "user=${USER} cached=${SUDO_CACHED}"
    echo -e "${NC}${CYAN}│${NC}  ${GREEN}●${NC} Date/Time: $(date '+%Y-%m-%d %H:%M:%S')${NC}"
    if [ -n "$LAST_LOG" ]; then
        echo -e "${NC}${CYAN}│${NC}  ${DIM}●${NC} Last Run:  ${LAST_LOG}${NC}"
    fi
    echo -e "${NC}${CYAN}└$(printf '─%.0s' {1..64})┘${NC}\n"
    echo -e "${NC}"
    echo -e "${YELLOW}┌──[ PRIVILEGE NOTICE ]──────────────────────────────────────────┐${NC}"
    echo -e "${YELLOW}│${NC} This script requires elevated permissions (sudo) to query and  "
    echo -e "${YELLOW}│${NC} update system package registries using 'apt'.                  "
    echo -e "${YELLOW}└────────────────────────────────────────────────────────────────┘${NC}"

    # Smart Detection: Check if user has passwordless sudo or a cached session
    if $SUDO_CACHED; then
        ELEVATION_METHOD="cached"
        echo -e " ${GREEN}✔ Active sudo capabilities detected. Proceeding...${NC}\n"
    else
        # Fallback Strategy: Prompt when elevation isn't actively cached
        ELEVATION_METHOD="prompt"
        echo -ne " ${CYAN}Proceed with sudo elevation? [y/N]: ${NC}"
        read -r elevate_confirm || true
        elevate_confirm="${elevate_confirm:-n}"

        if [[ ! "$elevate_confirm" =~ ^[yY](es)?$ ]]; then
            echo -e "${NC}\n ${RED}✖ Operation Canceled! Elevated Privileges (sudo) are Required in order to continue.${NC}\n"
            log_event "SUDO_REQUESTED" "user=${USER} method=prompt result=cancelled"
            log_event "SESSION_END" "=================================================================="
            exit 1
        fi
        echo -e " ${GREEN}✔ ${NC}${YELLOW}Requesting authentication...${NC}\n"
    fi

    if sudo TERM="$TERM" ELEVATED=1 ORIG_USER="$USER" ELEVATION_METHOD="$ELEVATION_METHOD" "$SCRIPT_PATH" "$@"; then   
        exit 0
    else
        echo -e "${NC}\n ${RED}✖ Elevated Privileges (sudo) are Required in order to continue. Exiting...${NC}\n"
        log_event "SUDO_REQUESTED" "user=${USER} method=${ELEVATION_METHOD} result=failed"
        log_event "SESSION_END  " "=================================================================="
        exit 1
    fi
fi

if [ -n "${ELEVATED:-}" ]; then
    LOG_USER="${ORIG_USER:-root}"
    echo -e " ${GREEN}✔ Privilege elevation successful.${NC}\n"
    log_event "SUDO_REQUESTED" "user=${LOG_USER} method=${ELEVATION_METHOD:-cached} result=success"
fi

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

        sanitized_lines=$(echo "$update_output" | grep -E '^(Hit|Get|Ign):' || true)
        total_sources=$(echo "$sanitized_lines" | wc -l)
        hits=$(echo "$sanitized_lines" | grep -c '^Hit:' || true)
        gets=$(echo "$sanitized_lines" | grep -c '^Get:' || true)
        igns=$(echo "$sanitized_lines" | grep -c '^Ign:' || true)

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
        log_event "APT_UPDATE" "repos=${total_sources} hits=${hits} gets=${gets} ignored=${igns}"
    else
        echo -e "${NC}\n${RED}========================================================================${NC}"
        echo -e "${NC}${RED}CRITICAL ERROR:${NC}${YELLOW} Failed to synchronize package registries.${NC}"
        echo -e "${NC}\n${RED}$update_output${NC}" | grep -i 'err:' || true
        echo -e "========================================================================${NC}"
        log_event "APT_UPDATE_FAILED" "exit=${update_status}"
        log_event "SESSION_END  " "=================================================================="
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
    if [ "$REPORT_ONLY" = true ]; then
        log_event "REPORT_ONLY" "packages=0"
    fi
    exit 0
else
    pkg_count=$(echo "$raw_apt_output" | wc -l)
    echo -e " ${NC}${YELLOW}▲ Found ${pkg_count} package(s) available for upgrade:${NC}\n"

    formatted_table=$(
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
    )

    # Ensures log files remain plain text with zero color bytes
    log_payload=$(
        echo -e "APPLICATION NAME||CURRENT VERSION||UPGRADABLE VERSION"
        echo -e "----------------||---------------||------------------"
        while read -r line; do
            [ -z "$line" ] && continue
            pkg_name=$(echo "$line" | cut -d'/' -f1)
            next_version=$(echo "$line" | awk '{print $2}')
            curr_version=$(echo "$line" | grep -oP '(?<=upgradable from: ).*(?=])' || true)
            curr_version=$(echo "$curr_version" | sed -E 's/~ubuntu\.[0-9]{2}\.[0-9]{2}~[a-z]+$//')
            next_version=$(echo "$next_version" | sed -E 's/~ubuntu\.[0-9]{2}\.[0-9]{2}~[a-z]+$//')
            if [ -z "$curr_version" ]; then curr_version="Unknown"; fi
            echo -e "${pkg_name}||${curr_version}||${next_version}"
        done <<< "$raw_apt_output"
    )

    # echo "${NC}$formatted_table" | sed 's/^/  /'
    COLUMNS=1000 column -t -s "||" <<< "$formatted_table" | sed 's/^/  /'
    echo ""
fi

if [ "$REPORT_ONLY" = true ]; then
    echo -e "${NC}${YELLOW}ℹ Report mode active. No system modifications applied.${NC}\n"
    log_event "REPORT_ONLY" "packages=${pkg_count}"
    exit 0
fi

# Predictive Reboot Check
reboot_packages_pattern="linux-image|linux-generic|linux-headers|linux-firmware|libc6|systemd|dbus|snapd"
predict_reboot=false

if echo "$raw_apt_output" | grep -qE "$reboot_packages_pattern"; then
    predict_reboot=true
fi

echo -e "${MAGENTA}┌──[ ACTION REQUIRED ]───────────────────────────────────────────┐${NC}"
if [ "$predict_reboot" = true ]; then
    echo -e "${MAGENTA}│${NC} ${YELLOW}⚠️  Note: This update includes core components that may${NC}"
    echo -e "${MAGENTA}│${NC} ${YELLOW}           require a system reboot once applied.${NC}"
    echo -e "${MAGENTA}├────────────────────────────────────────────────────────────────┘${NC}"
fi
echo -ne "${MAGENTA}│${NC} Apply these updates now? [y/N]: "
read -r confirm || true
confirm="${confirm:-n}"
echo -e "${MAGENTA}└───${NC}"

if [[ ! "$confirm" =~ ^[yY](es)?$ ]]; then
    echo -e "${NC}\n${YELLOW}⚠ Upgrade sequence canceled by user.${NC}\n"
    log_event "UPGRADE_CANCELED" "user=${LOG_USER}"
    log_event "SESSION_END  " "=================================================================="
    exit 0
else
    log_event "UPGRADE_CONFIRMED" "packages=${pkg_count}"
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
        log_event "DIST_UPGRADE_FAILED"
        log_event "SESSION_END  " "=================================================================="
        exit 1
    }
fi

echo -e "${NC}\n${CYAN}➜ Cleaning up obsolete cached packages...${NC}"
run_cmd apt-get autoremove -y
run_cmd apt-get clean
echo -e " ${GREEN}✔ Cleanup complete.${NC}"

# Write Transaction Log
{
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] TRANSACTION_START"
    echo "=================================================================="
    echo "The following packages were successfully upgraded:"
    echo ""
    COLUMNS=1000 column -t -s "||" <<< "$log_payload"
    echo "=================================================================="
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] TRANSACTION_END"
    echo ""
} >> "$LOG_FILE"

# Reboot Verification Check
if [ -f "$REBOOT_REQUIRED_FILE" ]; then
    echo -e "${NC}\n${RED}┌──[ REBOOT REQUIRED ]───────────────────────────────────────────┐${NC}"
    echo -e "${RED}│${NC} Core updates (Kernel or Snap components) require a system reboot.${NC}"
    echo -e "${RED}└────────────────────────────────────────────────────────────────┘${NC}"
    echo -e " ${GREEN}✔ Log saved to: ${YELLOW}$LOG_FILE${NC}\n"

    echo -ne "${RED}Reboot system right now? [y/N]: ${NC}"
    read -r reboot_confirm || true
    reboot_confirm="${reboot_confirm:-n}"

    if [[ "$reboot_confirm" =~ ^[yY](es)?$ ]]; then
        echo -e "${NC}${GREEN}Restarting machine...${NC}"
        log_event "REBOOT" "action=${reboot_confirm} result=rebooting"
        reboot
    else
        echo -e "${NC}${YELLOW}Reboot skipped. Please reboot manually when convenient.${NC}\n"
        log_event "REBOOT" "action=${reboot_confirm} result=skipped"
    fi
else
    echo -e "${NC}\n${GREEN}✔ System updates applied successfully! No reboot required.${NC}"
    log_event "REBOOT" "result=not_required"
    echo -e "${NC} ${GREEN}✔ Log saved to: ${YELLOW}$LOG_FILE${NC}\n"
fi
log_event "SESSION_END  " "=================================================================="
