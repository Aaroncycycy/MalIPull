#!/bin/bash

# Function to check if Zenity is installed
check_zenity() {
    if ! command -v zenity &> /dev/null; then
        echo "Zenity not found. Attempting to install..."
        # Try installing Zenity based on the system package manager
        if command -v apt-get &> /dev/null; then
            sudo apt-get update && sudo apt-get install -y zenity
        elif command -v yum &> /dev/null; then
            sudo yum install -y zenity
        elif command -v pacman &> /dev/null; then
            sudo pacman -S zenity
        else
            echo "Package manager not supported. Please install Zenity manually."
            exit 1
        fi
    else
        echo "Zenity is already installed."
    fi
}

# Call check_zenity function
check_zenity

# List of URLs to scrape
URLS=(
    "https://www.projecthoneypot.org/list_of_ips.php"
    "https://www.maxmind.com/en/high-risk-ip-sample-list"
    "https://www.abuseipdb.com/"
    "https://blocklist.de/en/statisticsmonth.html"
)

# Output file for consolidated IPs
OUTPUT_FILE="malicious_ips_consolidated.txt"
TEMP_FILE="temp_ips.txt"

# Rate limit in seconds (adjust based on site policies)
RATE_LIMIT=2

# Clear previous output files
> "$OUTPUT_FILE"

# Function to fetch and process a single URL
process_url() {
    local URL="$1"
   
    # Fetch webpage content
    RESPONSE=$(curl -sL "$URL" -o webpage.html)
    if [[ $? -ne 0 ]]; then
        echo "Failed to fetch $URL. Skipping..."
        return 1
    fi
   
    # Extract IPs from webpage (adjust for dynamic content or API)
    if grep -oE '\b([0-9]{1,3}\.){3}[0-9]{1,3}\b' webpage.html >> "$TEMP_FILE"; then
        echo "Extracted IPs from $URL"
    else
        echo "No IPs found in $URL or content may be dynamic."
    fi

    # Pause to avoid overwhelming servers
    sleep "$RATE_LIMIT"
}

# Initialize the Zenity progress bar
(
    total_steps=${#URLS[@]}
    progress_step=0
    echo "0" ; echo "# Starting the process..."; sleep 1

    # Loop through each URL and update the progress bar
    for i in "${!URLS[@]}"; do
        process_url "${URLS[$i]}"
        progress_step=$((($i + 1) * 100 / $total_steps))
        echo $progress_step
        echo "# Processing ${URLS[$i]}"
        sleep 1
    done
) | zenity --progress --title="Scraping IPs" --text="Processing URLs..." --percentage=0 --width=400 --auto-close

# Consolidate, remove duplicates, and sort
if [[ -f "$TEMP_FILE" ]]; then
    sort -u "$TEMP_FILE" > "$OUTPUT_FILE"
    zenity --info --text="Malicious IPs successfully compiled. List saved to $OUTPUT_FILE" --width=400
else
    zenity --error --text="No IPs were found across the sources." --width=400 --timeout=3
fi


# Cleanup
rm -f webpage.html "$TEMP_FILE"

