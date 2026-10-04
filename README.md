# 🚀 sysupdate-cli

A clean, modern, and interactive Bash utility for Debian and Ubuntu system package updates. It replaces standard `apt` output noise with an organized UI, clean version comparisons, repository sync metrics, and automated logging.

![License](https://img.shields.io/badge/license-MIT-blue.svg)
![Platform](https://img.shields.io/badge/platform-Ubuntu%20%7C%20Debian-orange.svg)
![Language](https://img.shields.io/badge/shell-Bash-green.svg)

---

## ✨ Features

* **Privilege Elevation Check**: Automatically checks for elevated permissions (sudo). Will prompt the user otherwise.
* **Clean Registry Summaries**: Aggregates sync operations into simple domain counts and flags which repositories actually fetched updates (`Get`).
* **Distro Suffix Trimming**: Strips repetitive release suffixes (e.g., `~ubuntu.24.04~noble`) to display clean version comparisons side-by-side.
* **Troubleshooting Mode (`-v`)**: Pass `--verbose` to restore full, color-coded, live `apt` terminal streams whenever diagnosis is needed.
* **Safe Dry-Run Reporting (`-r`)**: Preview available updates in a clean table without executing system modifications.
* **Automated Audit Logging**: Automatically strips ANSI color codes and appends structured upgrade history to `/var/log/sysupdates.log`.
* **Reboot Detection**: Intercepts `/var/run/reboot-required` and prompts for machine restarts after core kernel/snap updates.

---

## 🛠️ Installation

1. **Clone the repository**:
   ```bash
   git clone https://github.com/TechStud/sysupdate-cli.git
   ```

2. Make the script executable:
   ```bash
   cd sysupdate-cli
   chmod +x sysupdates.sh
   ```

4. (Optional) Symlink to system PATH:
   ```bash
   sudo ln -s "$(pwd)/sysupdates.sh" /usr/local/bin/sysupdate
   ```

---

## 📖 Usage

If you created the Symlink, run from any path:

``` bash
# Run interactive upgrade sequence
sysupdate

# Run report mode (display available updates without upgrading)
sysupdate -r

# Run with verbose output (streams full apt-get stdout/stderr)
sysupdate -v
```

Without Symlink... Run directly:

``` bash
# Run interactive upgrade sequence
/path/to/sysupdate-cli/sysupdates.sh

# Run report mode (display available updates without upgrading)
/path/to/sysupdate-cli/sysupdates.sh -r

# Run with verbose output (streams full apt-get stdout/stderr)
/path/to/sysupdate-cli/sysupdates.sh -v
```

### Automated Privilege Escalation Check

```
┌──[ PRIVILEGE NOTICE ]──────────────────────────────────────────╮
│ This script requires elevated permissions (sudo) to query and  
│ update system package registries using 'apt'.                  
└────────────────────────────────────────────────────────────────╯
 Proceed with sudo elevation? [Y/n]: Y
 ✔ Relaunching with sudo privileges...

[sudo] password for <username>: 

```

### Options

| Flag | Long Flag | Description |
| :--- | :--- | :--- |
| -r | --report-only | Displays the upgradable packages table and exits without applying changes. |
| -v | --verbose | Streams uncompressed, colorized apt-get progress output. |
| -h | --help | Displays help information and available options. |

---

## Screenshots

<img width="836" height="1172" alt="image" src="https://github.com/user-attachments/assets/0d7fc3d1-b0ec-48f7-9087-4346454ce945" />

---

## 📝 Logging & Diagnostics

All completed upgrade operations append transaction records directly to:
`/var/log/sysupdates.log`

---

## 📄 License

Distributed under the MIT License. See LICENSE for more information.
