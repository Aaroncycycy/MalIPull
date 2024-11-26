# MalIPull - A Simple Malicious IP Scraper

This Bash script scrapes IP addresses from various websites known to provide malicious or high-risk IP lists. The script then compiles and consolidates these IP addresses into a single file. The user interface is powered by **Zenity** for a smoother experience, displaying progress bars and success/error messages during the execution.

## Features

- **Scrapes multiple sources**: Collects malicious IPs from multiple trusted websites.
- **Zenity UI**: Provides a graphical progress bar, success, and error messages.
- **Automatic Zenity installation**: The script checks if Zenity is installed and installs it if necessary.
- **Rate limiting**: The script pauses between requests to avoid overwhelming the target websites. (So you dont get blocked)

## Installation

### Prerequisites

- **Zenity** (GUI utility) installed. The script will attempt to install Zenity automatically if it is not found.

### How to Use

1. **Clone the repository** or download the script:
    ```bash
    git clone https://github.com/yourusername/malicious-ip-scraper.git
    cd malicious-ip-scraper
    ```

2. **Run the script**:
    ```bash
    ./scrape_malicious_ips.sh
    ```

   The script will check if **Zenity** is installed. If not, it will attempt to install Zenity using your system's package manager. Once Zenity is available, the script will scrape the defined websites for malicious IPs and display a progress bar. 

3. **Output**: The resulting IP list will be saved in the `malicious_ips_consolidated.txt` file.

### Example Output

```bash
Malicious IPs successfully compiled. List saved to malicious_ips_consolidated.txt
