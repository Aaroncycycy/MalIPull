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

---

## 📦 Running
