# 🛡️ MalIPull - Threat Feed Aggregator

MalIPull is a lightweight, open-source Bash-based threat feed aggregator designed to help resource-constrained organizations collect, consolidate, and review malicious IP addresses from public threat intelligence sources. Built with both CLI and GUI interfaces (using Zenity), MalIPull is intended for easy deployment and operation in environments where proactive cybersecurity measures are needed without enterprise-scale budgets.

Developed as part of a cybersecurity capstone project for, the tool enables organizations to automate threat monitoring, enforce role-based access control, and export structured indicators of compromise for further analysis or SIEM integration.

---

## 🚀 Features

- ✅ **Aggregates malicious IPs** from multiple public threat intelligence feeds  
- 🖥️ **Zenity GUI and CLI modes** for flexible operation across user roles  
- 🔐 **Role-based authentication** (Admin/Analyst) with salted SHA-256 password hashing  
- 📅 **Automated daily scan scheduler** with differential IP logging  
- 📄 **Structured output** in CSV or JSON  
- 🔍 **Differential tracking** of new indicators between scans  
- 🧰 **Self-validates and installs dependencies** like `curl`, `jq`, and `zenity` on supported systems  
- 🧱 **Low system overhead**—suitable for virtual machines, legacy hardware, and Raspberry Pi  
- 📚 Includes a full-featured **User & Admin Guide**  

---

## 📦 Installation

### Requirements

- Linux OS (Ubuntu, Debian, RedHat, Arch)  
- Bash 4.x or later  
- `curl`, `jq`, and `zenity` (installed automatically if not present)  

### Setup Instructions

1. **Download the Script**

```bash
wget https://raw.githubusercontent.com/Aaroncycycy/MalIPull/refs/heads/main/malipull.sh
chmod +x malipull.sh
```
---

## Running MalIPull
- Simply navigate to the directory and type in "bash malipull.sh"
- alternatively you move malipull's directory to PATH if you want to be able to run it from anywhere just by typing in "malipull"
For example:
  
```bash
sudo mv /path/to/malipull.sh /usr/local/bin/malipull
chmod +x /usr/local/bin/malipull
```
Now MalIPull will run from the terminal just by typing in "malipull" regardless of the directory you are currently in.

---

## Tool Capabilities:

- | Feature           | Description                                                   |
| ----------------- | ------------------------------------------------------------- |
| Run Scan          | Aggregates IPs from all feeds and detects new threats         |
| Output Formats    | Export full or differential results in CSV or JSON            |
| Feed Management   | Add or remove threat feed URLs with input validation          |
| User Management   | Add Admins or Analysts; change passwords; restrict user roles |
| Daily Scheduler   | Schedule background scans with configurable time window       |
| Role-Based Access | Restricts advanced settings to Admins only                    |
| Log Review        | View scan logs and summaries via GUI or CLI                   |

