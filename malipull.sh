#!/bin/bash

#  Check for curl
check_curl() {
    if ! command -v curl &> /dev/null; then
        echo "Curl is not installed. Attempting to install..."

        if command -v apt-get &> /dev/null; then
            sudo apt-get update && sudo apt-get install -y curl
        elif command -v yum &> /dev/null; then
            sudo yum install -y curl
        elif command -v pacman &> /dev/null; then
            sudo pacman -Sy --noconfirm curl
        else
            echo "Unsupported package manager. Please install curl manually."
            exit 1
        fi

        # Final check
        if ! command -v curl &> /dev/null; then
            echo "Curl installation failed. Please install curl manually per your operating system, then re-run the script."
            exit 1
        fi
    else
        echo "Curl is installed."
    fi
}

check_curl

# JQ Check (For JSON output)
check_jq() {
    if ! command -v jq &> /dev/null; then
        echo "jq is not installed. Attempting to install..."

        if command -v apt-get &> /dev/null; then
            sudo apt-get update && sudo apt-get install -y jq
        elif command -v yum &> /dev/null; then
            sudo yum install -y jq
        elif command -v pacman &> /dev/null; then
            sudo pacman -Sy --noconfirm jq
        else
            echo "Unsupported package manager. Please install jq manually."
            exit 1
        fi

        if ! command -v jq &> /dev/null; then
            echo "jq installation failed. Please install manually and re-run the script."
            exit 1
        fi
    fi
}

#  MODE SELECTION
echo "How would you like to run this?"
echo "1) Application Mode (Zenity GUI)"
echo "2) CLI Mode (Text-based)"
echo -n "Enter your choice [1 or 2]: "
read -r MODE_CHOICE

if [[ "$MODE_CHOICE" == "2" ]]; then
    USE_CLI_MODE=true
else
    USE_CLI_MODE=false
fi

#  THESE ARE THE DEFAULT FILE PATHS
CONFIG_DIR="/etc/MalIPull_Configs"
FEEDS_FILE="$CONFIG_DIR/feeds.txt"
CONFIG_FILE="$CONFIG_DIR/config.cfg"
LOG_DIR="/var/log/MalIPull_Logs/$USER"
SCHEDULER_PID="$CONFIG_DIR/scheduler.pid"
USER_FILE="$CONFIG_DIR/UserShadows.txt"

# Create log directory if it doesnt exist
if [ ! -d "$LOG_DIR" ]; then
    sudo mkdir -p "$LOG_DIR"
    sudo chown "$USER":"$USER" "$LOG_DIR"
fi

# Create config directory with sudo if needed
if [ ! -d "$CONFIG_DIR" ]; then
    sudo mkdir -p "$CONFIG_DIR"
    sudo chown "$USER:$USER" "$CONFIG_DIR"
fi

# Create config file if it doesnt exist
touch "$CONFIG_FILE"


# Create feeds file with default sources if it doesnt exist (or is empty)
if [ ! -s "$FEEDS_FILE" ]; then
    cat <<EOF > "$FEEDS_FILE"
https://www.projecthoneypot.org/list_of_ips.php
https://www.maxmind.com/en/high-risk-ip-sample-list
https://www.abuseipdb.com/
https://www.spamhaus.org/drop/drop.txt
EOF
    echo "Initialized feeds.txt with default sources."
fi


#  Load Config 
OUTPUT_FORMAT=$(grep "format=" "$CONFIG_FILE" | cut -d= -f2)
if [ -z "$OUTPUT_FORMAT" ]; then
    OUTPUT_FORMAT="csv"
    echo "format=$OUTPUT_FORMAT" > "$CONFIG_FILE"
fi

# Utility Functions
extract_ips() {
    grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' | grep -v '^0\.' | sort -u
}

run_scan_cli() {
    TIMESTAMP=$(date +"%Y%m%d_%H%M")
    LOG_FILE="$LOG_DIR/scan-$TIMESTAMP.log"
    DIFF_FILE="$LOG_DIR/diff-$TIMESTAMP.txt"
    TEMP_IP_FILE=$(mktemp)
    MASTER_LIST="$CONFIG_DIR/output-master.txt"

    SCAN_MODE="Manual"

    echo "[$(date)] Starting $SCAN_MODE scan..." | tee "$LOG_FILE"

    while read -r URL; do
        [ -z "$URL" ] && continue
        echo "Fetching: $URL" | tee -a "$LOG_FILE"
        curl -s "$URL" | extract_ips >> "$TEMP_IP_FILE"
    done < "$FEEDS_FILE"

    sort -u "$TEMP_IP_FILE" > "$TEMP_IP_FILE.sorted"
    TOTAL=$(wc -l < "$TEMP_IP_FILE.sorted")
    echo "Found $TOTAL unique IPs." | tee -a "$LOG_FILE"

    # Detect new IPs
    touch "$MASTER_LIST"
    NEW_IPS=$(comm -23 "$TEMP_IP_FILE.sorted" <(sort "$MASTER_LIST"))  # Diff
    echo "$NEW_IPS" > "$DIFF_FILE"
    NEW_COUNT=$(wc -l < "$DIFF_FILE")
    echo "$NEW_COUNT new IPs discovered." | tee -a "$LOG_FILE"

    echo "$SCAN_MODE" > "$LOG_DIR/last-scan-mode.txt"
    echo "$TIMESTAMP" > "$LOG_DIR/last-scan-id.txt"

    # Update master list
    cat "$DIFF_FILE" >> "$MASTER_LIST"
    sort -u "$MASTER_LIST" -o "$MASTER_LIST"

    if [ "$OUTPUT_FORMAT" == "json" ]; then
        check_jq

        jq -Rs --arg timestamp "$TIMESTAMP" \
            '{ timestamp: $timestamp, indicators: split("\n") | map(select(length > 0)) }' \
            < "$MASTER_LIST" > "output.json"

        echo "Exported to output.json" | tee -a "$LOG_FILE"
    else
        cp "$MASTER_LIST" "output.csv"
        echo "Exported to output.csv" | tee -a "$LOG_FILE"
    fi

    rm "$TEMP_IP_FILE" "$TEMP_IP_FILE.sorted"
}

# Login / Admin Setup For CLI (Need to add PW Policy)

cli_login() {
    # If no admin account exists, prompt to create one
    if [ ! -f "$USER_FILE" ]; then
        echo "Welcome to MalIPull CLI!"
        echo "It looks like this is your first time running the tool."
        echo "Let's create your Admin account."

        while true; do
            read -rp "Enter admin username: " ADMIN_USERNAME
            read -rsp "Enter password: " ADMIN_PASSWORD && echo
            read -rsp "Confirm password: " ADMIN_PASSWORD_CONFIRM && echo

            if [[ -z "$ADMIN_USERNAME" || -z "$ADMIN_PASSWORD" || -z "$ADMIN_PASSWORD_CONFIRM" ]]; then
                echo "All fields are required."
                continue
            fi

            if [[ "$ADMIN_PASSWORD" != "$ADMIN_PASSWORD_CONFIRM" ]]; then
                echo "Passwords do not match. Try again."
                continue
            fi

            SALT=$(openssl rand -hex 8)
            HASH=$(echo -n "$SALT$ADMIN_PASSWORD" | sha256sum | awk '{print $1}')
            echo "$ADMIN_USERNAME:$SALT:$HASH:admin" > "$USER_FILE"
            echo "Admin account created successfully."
            break
        done
    fi

    # Login prompt
    while true; do
        read -rp "Username: " USERNAME_INPUT
        read -rsp "Password: " PASSWORD_INPUT && echo

        STORED_LINE=$(grep "^$USERNAME_INPUT:" "$USER_FILE")
        if [ -z "$STORED_LINE" ]; then
            echo "User not found. Try again."
            continue
        fi

        SALT=$(echo "$STORED_LINE" | cut -d: -f2)
        STORED_HASH=$(echo "$STORED_LINE" | cut -d: -f3)
        ROLE=$(echo "$STORED_LINE" | cut -d: -f4)
        INPUT_HASH=$(echo -n "$SALT$PASSWORD_INPUT" | sha256sum | awk '{print $1}')

        if [[ "$INPUT_HASH" != "$STORED_HASH" ]]; then
            echo "Incorrect password. Try again."
        else
            CURRENT_USER="$USERNAME_INPUT"
            CURRENT_ROLE="$ROLE"
            echo "Login successful. Welcome, $CURRENT_USER! Role: $CURRENT_ROLE"
            break
        fi
    done
}


#  CLI MODE 
if [ "$USE_CLI_MODE" = true ]; then
    cli_login

    while true; do
        echo
        echo "=== Threat Feed Aggregator (CLI Mode) ==="
        echo "1) Run Scan"
        echo "2) Choose Output Format (csv/json)"
        echo "3) Add Feed Resource"
        echo "4) Feed Scheduler"
        echo "5) Instructions"
        echo "6) Settings"
        echo "7) Exit"
        echo -n "Choose an option: "
        read -r CLI_CHOICE

        case "$CLI_CHOICE" in
            1)
                run_scan_cli
                ;;
            2)
                echo -n "Enter output format (csv or json): "
                read -r FORMAT
                sed -i "/format=/d" "$CONFIG_FILE"
                echo "format=$FORMAT" >> "$CONFIG_FILE"
                OUTPUT_FORMAT="$FORMAT"
                echo "Output format set to $FORMAT"
                ;;
            3)
                echo -n "Enter new feed URL: "
                read -r NEW_FEED

                NEW_FEED=$(echo "$NEW_FEED" | xargs)

                if [[ "$NEW_FEED" =~ ^https?://[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}(/.*)?$ ]]; then
                    if grep -Fxq "$NEW_FEED" "$FEEDS_FILE"; then
                        echo "That feed is already in the list."
                    else
                        echo "$NEW_FEED" >> "$FEEDS_FILE"
                        echo "Feed added successfully."
                    fi
                else
                    echo "Invalid URL. Please enter a valid website starting with http:// or https://"
                fi
                ;;
            4)
    if [ -f "$SCHEDULER_PID" ]; then
        echo "A feed scheduler is already running."
        read -p "Do you want to stop it? (y/N): " STOP_SCHED
        if [[ "$STOP_SCHED" =~ ^[Yy]$ ]]; then
            kill "$(cat "$SCHEDULER_PID")" 2>/dev/null
            rm "$SCHEDULER_PID"
            echo "Scheduler stopped."
        fi
        continue
    fi

    echo -n "Enter the time for the daily scan (24-hour format, HH:MM): "
    read -r SCHEDULE_TIME

    # Validate format
    if [[ ! "$SCHEDULE_TIME" =~ ^([01][0-9]|2[0-3]):[0-5][0-9]$ ]]; then
        echo "Invalid time format. Please enter time as HH:MM (e.g., 14:30)."
        continue
    fi

    echo "Daily scan will run at $SCHEDULE_TIME."

    # Start scheduler in background
    (
        echo $$ > "$SCHEDULER_PID"
        while true; do
            CURRENT_TIME=$(date +"%H:%M")
            if [ "$CURRENT_TIME" == "$SCHEDULE_TIME" ]; then
                echo "[$(date)] Scheduled scan triggered." >> "$LOG_DIR/scheduler.log"
                run_scan_cli >> "$LOG_DIR/scheduler.log" 2>&1
                sleep 61  # Avoid duplicate run within same minute
            fi
            sleep 30
        done
    ) &
    echo "Scheduler started in background."
    ;;
    
	    5)
    echo
    echo "=== Instructions ==="
    echo "CLI instructions coming soon!"
    echo
    ;;

	    6)
    while true; do
        echo
        echo "=== Settings ==="
        echo "1) Change User Password"
        echo "2) Add an Admin"
        echo "3) Add an Analyst"
        echo "4) Remove a User"
        echo "5) Back to Main Menu"
        echo -n "Choose a settings option: "
        read -r SETTINGS_CHOICE

        case "$SETTINGS_CHOICE" in
            1)
                echo "=== Change User Password ==="
                read -rsp "Enter current password: " OLD_PASS && echo
                STORED_LINE=$(grep "^$CURRENT_USER:" "$USER_FILE")
                SALT=$(echo "$STORED_LINE" | cut -d: -f2)
                STORED_HASH=$(echo "$STORED_LINE" | cut -d: -f3)
                CURRENT_ROLE=$(echo "$STORED_LINE" | cut -d: -f4)
                INPUT_HASH=$(echo -n "$SALT$OLD_PASS" | sha256sum | awk '{print $1}')
                if [ "$INPUT_HASH" != "$STORED_HASH" ]; then
                    echo "Incorrect current password."
                    continue
                fi

                read -rsp "Enter new password: " NEW_PASS && echo
                read -rsp "Confirm new password: " NEW_PASS_CONFIRM && echo

                if [ "$NEW_PASS" != "$NEW_PASS_CONFIRM" ]; then
                    echo "Passwords do not match."
                    continue
                fi

                NEW_SALT=$(openssl rand -hex 8)
                NEW_HASH=$(echo -n "$NEW_SALT$NEW_PASS" | sha256sum | awk '{print $1}')
                sed -i "/^$CURRENT_USER:/d" "$USER_FILE"
                echo "$CURRENT_USER:$NEW_SALT:$NEW_HASH:$CURRENT_ROLE" >> "$USER_FILE"
                echo "Password updated successfully."
                ;;

            2)
                if [ "$CURRENT_ROLE" != "admin" ]; then
                    echo "Access denied: Only admins can add new admins."
                    continue
                fi

                read -rp "Enter username for new admin: " NEW_ADMIN
                if grep -q "^$NEW_ADMIN:" "$USER_FILE"; then
                    echo "User already exists."
                    continue
                fi

                read -rsp "Enter password for new admin: " ADMIN_PASS && echo
                read -rsp "Confirm password: " ADMIN_PASS_CONFIRM && echo

                if [ "$ADMIN_PASS" != "$ADMIN_PASS_CONFIRM" ]; then
                    echo "Passwords do not match."
                    continue
                fi

                SALT=$(openssl rand -hex 8)
                HASH=$(echo -n "$SALT$ADMIN_PASS" | sha256sum | awk '{print $1}')
                echo "$NEW_ADMIN:$SALT:$HASH:admin" >> "$USER_FILE"
                echo "Admin user '$NEW_ADMIN' added successfully."
                ;;

            3)
                if [ "$CURRENT_ROLE" != "admin" ]; then
                    echo "Access denied: Only admins can add analysts."
                    continue
                fi

                read -rp "Enter username for new analyst: " NEW_ANALYST
                if grep -q "^$NEW_ANALYST:" "$USER_FILE"; then
                    echo "User already exists."
                    continue
                fi

                read -rsp "Enter password for new analyst: " ANALYST_PASS && echo
                read -rsp "Confirm password: " ANALYST_PASS_CONFIRM && echo

                if [ "$ANALYST_PASS" != "$ANALYST_PASS_CONFIRM" ]; then
                    echo "Passwords do not match."
                    continue
                fi

                SALT=$(openssl rand -hex 8)
                HASH=$(echo -n "$SALT$ANALYST_PASS" | sha256sum | awk '{print $1}')
                echo "$NEW_ANALYST:$SALT:$HASH:analyst" >> "$USER_FILE"
                echo "Analyst user '$NEW_ANALYST' added successfully."
                ;;

            4)
                if [ "$CURRENT_ROLE" != "admin" ]; then
                    echo "Access denied: Only admins can remove users."
                    continue
                fi

                echo "Users available for removal:"
                cut -d: -f1 "$USER_FILE" | grep -v "^$CURRENT_USER"
                read -rp "Enter the username to remove: " REMOVE_USER

                if ! grep -q "^$REMOVE_USER:" "$USER_FILE"; then
                    echo "User '$REMOVE_USER' does not exist."
                    continue
                fi

                REMOVE_ROLE=$(grep "^$REMOVE_USER:" "$USER_FILE" | cut -d: -f4)
                ADMIN_COUNT=$(grep ":admin$" "$USER_FILE" | wc -l)

                if [ "$REMOVE_ROLE" = "admin" ] && [ "$ADMIN_COUNT" -le 1 ]; then
                    echo "Cannot remove the last remaining admin."
                    continue
                fi

                read -rsp "Enter your password to confirm: " CONFIRM_PASS && echo
                STORED_HASH=$(echo "$STORED_LINE" | cut -d: -f3)
                CONFIRM_HASH=$(echo -n "$SALT$CONFIRM_PASS" | sha256sum | awk '{print $1}')
                if [ "$CONFIRM_HASH" != "$STORED_HASH" ]; then
                    echo "Incorrect password. Action canceled."
                    continue
                fi

                sed -i "/^$REMOVE_USER:/d" "$USER_FILE"
                echo "User '$REMOVE_USER' removed successfully."
                ;;

            5) break ;;
            *) echo "Invalid option." ;;
        esac
    done
    ;;
	    7)
    echo "Exiting Threat Feed Aggregator CLI. Goodbye!"
    break
    ;;

	    
            *)
                echo "Invalid option."
                ;;
        esac
    done

    exit 0
fi

# GUI/ZENITY MODE SECTION

# Function to check if Zenity is installed or fall back to CLI
check_zenity() {
    if ! command -v zenity &> /dev/null; then
        echo "Zenity not found. Attempting to install..."

        if command -v apt-get &> /dev/null; then
            sudo apt-get update && sudo apt-get install -y zenity
        elif command -v yum &> /dev/null; then
            sudo yum install -y zenity
        elif command -v pacman &> /dev/null; then
            sudo pacman -Sy --noconfirm zenity
        else
            echo "Unsupported package manager."
        fi

        # Re-check
        if ! command -v zenity &> /dev/null; then
            echo "Zenity installation failed."
            echo -n "Would you like to run in CLI-only mode? [y/N]: "
            read -r RESPONSE
            if [[ "$RESPONSE" =~ ^[Yy]$ ]]; then
                USE_CLI_MODE=true
            else
                echo "Exiting. Please install Zenity manually."
                exit 1
            fi
        fi
    fi
}


# Knock knock. Whose there? Zenity. Zenity who?......Zenity who?.........Zenity who?..........Hello?...................Zenity who? 
check_zenity

# ========== File Paths ==========
CONFIG_DIR="/etc/MalIPull_Configs"
FEEDS_FILE="$CONFIG_DIR/feeds.txt"
CONFIG_FILE="$CONFIG_DIR/config.cfg"
LOG_DIR="/var/log/MalIPull_Logs/$USER"
SCHEDULER_PID="$CONFIG_DIR/scheduler.pid"
USER_FILE="$CONFIG_DIR/UserShadows.txt"

# Login / Admin Setup For Zenity (Testing out multi-roles... and PW Policy)
#ROLE SUPPORT
# Ensure UserShadows.txt exists
if [ ! -f "$USER_FILE" ]; then
    zenity --info --text="Welcome! It looks like this is your first time running MalIPull. Let's create your admin account."

    while true; do
        ADMIN_USERNAME=$(zenity --entry --title="Create Admin Username" --text="Enter a username:")
        ADMIN_PASSWORD=$(zenity --password --title="Create Admin Password")
        ADMIN_PASSWORD_CONFIRM=$(zenity --password --title="Confirm Password")

        if [ -z "$ADMIN_USERNAME" ] || [ -z "$ADMIN_PASSWORD" ] || [ -z "$ADMIN_PASSWORD_CONFIRM" ]; then
            zenity --error --text="All fields are required."
            continue
        fi

        if [ "$ADMIN_PASSWORD" != "$ADMIN_PASSWORD_CONFIRM" ]; then
            zenity --error --text="Passwords do not match."
            continue
        fi

        SALT=$(openssl rand -hex 8)
        HASH=$(echo -n "$SALT$ADMIN_PASSWORD" | sha256sum | awk '{print $1}')
        echo "$ADMIN_USERNAME:$SALT:$HASH:admin" > "$USER_FILE"
        zenity --info --text="Admin account created."
        break
    done
fi

# Login Phase
while true; do
    USERNAME_INPUT=$(zenity --entry --title="Login" --text="Username:")
    PASSWORD_INPUT=$(zenity --password --title="Login")

    STORED_LINE=$(grep "^$USERNAME_INPUT:" "$USER_FILE")

    if [ -z "$STORED_LINE" ]; then
        zenity --error --text="Username not found."
        continue
    fi

    SALT=$(echo "$STORED_LINE" | cut -d: -f2)
    STORED_HASH=$(echo "$STORED_LINE" | cut -d: -f3)
    ROLE=$(echo "$STORED_LINE" | cut -d: -f4)
    INPUT_HASH=$(echo -n "$SALT$PASSWORD_INPUT" | sha256sum | awk '{print $1}')

    if [ "$INPUT_HASH" != "$STORED_HASH" ]; then
        zenity --error --text="Incorrect password."
        continue
    fi

    CURRENT_USER="$USERNAME_INPUT"
    CURRENT_ROLE="$ROLE"

    zenity --info --text="Login successful. Role: $ROLE"
    break
done



# Create log directory if it doesn't exist
if [ ! -d "$LOG_DIR" ]; then
    sudo mkdir -p "$LOG_DIR"
    sudo chown "$USER":"$USER" "$LOG_DIR"
fi

# Create config directory with sudo if needed
if [ ! -d "$CONFIG_DIR" ]; then
    sudo mkdir -p "$CONFIG_DIR"
    sudo chown "$USER:$USER" "$CONFIG_DIR"
fi

# Create config file if it doesn't exist
touch "$CONFIG_FILE"


# Create feeds file with default sources if it doesn't exist or is empty
if [ ! -s "$FEEDS_FILE" ]; then
    cat <<EOF > "$FEEDS_FILE"
https://www.projecthoneypot.org/list_of_ips.php
https://www.maxmind.com/en/high-risk-ip-sample-list
https://www.abuseipdb.com/
https://www.spamhaus.org/drop/drop.txt
EOF
    echo "Initialized feeds.txt with default sources."
fi


# Load Config 
OUTPUT_FORMAT=$(grep "format=" "$CONFIG_FILE" | cut -d= -f2)
if [ -z "$OUTPUT_FORMAT" ]; then
    OUTPUT_FORMAT="csv"
    echo "format=$OUTPUT_FORMAT" > "$CONFIG_FILE"
fi

# Extract IPs using grep
extract_ips() {
    grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' | grep -v '^0\.' | sort -u
}

run_scan() {
    TIMESTAMP=$(date +"%Y%m%d_%H%M")
    LOG_FILE="$LOG_DIR/scan-$TIMESTAMP.log"
    DIFF_FILE="$LOG_DIR/diff-$TIMESTAMP.txt"
    TEMP_IP_FILE=$(mktemp)

    SCAN_MODE=${1:-Manual}

    echo "[$(date)] Starting $SCAN_MODE scan..." | tee "$LOG_FILE"

    while read -r URL; do
        [ -z "$URL" ] && continue
        echo "Fetching: $URL" | tee -a "$LOG_FILE"
        curl -s "$URL" | extract_ips >> "$TEMP_IP_FILE"
    done < "$FEEDS_FILE"

    sort -u "$TEMP_IP_FILE" > "$TEMP_IP_FILE.sorted"
    TOTAL=$(wc -l < "$TEMP_IP_FILE.sorted")
    echo "Found $TOTAL unique IPs." | tee -a "$LOG_FILE"

    # Detect new IPs
    MASTER_LIST="output-master.txt"
    touch "$MASTER_LIST"
    NEW_IPS=$(comm -23 "$TEMP_IP_FILE.sorted" <(sort "$MASTER_LIST"))  # Diff
    echo "$NEW_IPS" > "$DIFF_FILE"
    NEW_COUNT=$(wc -l < "$DIFF_FILE")
    echo "$NEW_COUNT new IPs discovered." | tee -a "$LOG_FILE"
    echo "$SCAN_MODE" > "$LOG_DIR/last-scan-mode.txt"
    echo "$TIMESTAMP" > "$LOG_DIR/last-scan-id.txt"

    # Append new IPs to master output list
    cat "$DIFF_FILE" >> "$MASTER_LIST"
    sort -u "$MASTER_LIST" -o "$MASTER_LIST"

    if [ "$OUTPUT_FORMAT" == "json" ]; then
        check_jq  # Check for jq only when needed
        jq -Rs --arg timestamp "$TIMESTAMP" \
    '{ timestamp: $timestamp, indicators: split("\n") | map(select(length > 0)) }' \
    < "$MASTER_LIST" > "output.json"

        echo "Exported to output.json" | tee -a "$LOG_FILE"
    else
        cp "$MASTER_LIST" "output.csv"
        echo "Exported to output.csv" | tee -a "$LOG_FILE"
    fi

    rm "$TEMP_IP_FILE" "$TEMP_IP_FILE.sorted"
}

#  Main Menu
while true; do
    CHOICE=$(zenity --list --title="MalIPull: Threat Feed Aggregator" \
    --width=500 --height=600 \
        --column="Menu Option" \
        "Run Scan" \
        "Choose Output Format" \
        "Feed Resources" \
        "Feed Scheduler" \
        "View Last Scan Summary" \
        "Instructions" \
        "Settings" \
        "Exit")

    case "$CHOICE" in
                "Run Scan")
            run_scan
            zenity --info --text="Scan complete. Check output file and logs/ for details."
            ;;

        "Choose Output Format")
            FORMAT=$(zenity --list --title="Choose Output Format" --radiolist \
                --column="Select" --column="Format" \
                TRUE "csv" FALSE "json")

            if [ "$FORMAT" ]; then
                OUTPUT_FORMAT="$FORMAT"
                sed -i "/format=/d" "$CONFIG_FILE"
                echo "format=$OUTPUT_FORMAT" >> "$CONFIG_FILE"
                zenity --info --text="Output format set to $OUTPUT_FORMAT"
            fi
            ;;

        "Feed Resources")
    while true; do
        FEED_ACTION=$(zenity --list --title="Manage Feed Resources" \
            --width=400 --height=500 \
            --column="Action" \
            "View Feed Resources" \
            "Add Feed Resource" \
            "Remove Feed Resource")

        case "$FEED_ACTION" in
            "View Feed Resources")
                zenity --text-info --title="Feed List" --width=500 --height=500 \
                    --filename="$FEEDS_FILE"
                ;;

            "Add Feed Resource")
                NEW_FEED=$(zenity --entry --title="Add Feed URL" --text="Enter a threat feed URL:")
                if [ -n "$NEW_FEED" ]; then
                    NEW_FEED=$(echo "$NEW_FEED" | xargs)
                    if [[ "$NEW_FEED" =~ ^https?://[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}(/.*)?$ ]]; then
                        if grep -Fxq "$NEW_FEED" "$FEEDS_FILE"; then
                            zenity --warning --text="This feed is already in the list."
                        else
                            echo "$NEW_FEED" >> "$FEEDS_FILE"
                            zenity --info --text="Feed added successfully."
                        fi
                    else
                        zenity --error --text="Invalid URL. Please enter a valid website starting with http:// or https://"
                    fi
                fi
                ;;

            "Remove Feed Resource")
                FEED_TO_REMOVE=$(zenity --list --title="Select Feed to Remove" \
                    --width=500 --height=500 \
                    --column="Feed URLs" $(cat "$FEEDS_FILE"))
                if [ -n "$FEED_TO_REMOVE" ]; then
                    grep -Fxv "$FEED_TO_REMOVE" "$FEEDS_FILE" > temp_feeds.txt && mv temp_feeds.txt "$FEEDS_FILE"
                    zenity --info --text="Feed removed: $FEED_TO_REMOVE"
                fi
                ;;

            "" )
                break
                ;;
        esac
    done
    ;;


	"Feed Scheduler")
            if [ -f "$SCHEDULER_PID" ]; then
                zenity --question --text="A scheduler is already running. Do you want to stop it?"
                if [ $? -eq 0 ]; then
                    kill "$(cat "$SCHEDULER_PID")" 2>/dev/null
                    rm "$SCHEDULER_PID"
                    zenity --info --text="Scheduler stopped."
                fi
                continue
            fi

            # Step 1: Select Hour
            SCHEDULE_HOUR=$(zenity --list --title="Select Hour" \
                --text="Choose hour (24-hour format)" \
                --column="Hour" $(seq -w 0 23))
            [ -z "$SCHEDULE_HOUR" ] && continue

            # Step 2: Select Minute
            SCHEDULE_MINUTE=$(zenity --list --title="Select Minute" \
                --text="Choose minute" \
                --column="Minute" $(seq -w 0 59))
            [ -z "$SCHEDULE_MINUTE" ] && continue

            SCHEDULE_TIME="$SCHEDULE_HOUR:$SCHEDULE_MINUTE"

            # Confirm with user
            zenity --question --text="Schedule daily scan at $SCHEDULE_TIME?"
            [ $? -ne 0 ] && continue

            # Start scheduler in background
            (
                echo $$ > "$SCHEDULER_PID"
                while true; do
                    CURRENT_TIME=$(date +"%H:%M")
                    if [ "$CURRENT_TIME" == "$SCHEDULE_TIME" ]; then
                        echo "[$(date)] Scheduled scan triggered." >> "$LOG_DIR/scheduler.log"
                        run_scan
                        sleep 61
                    fi
                    sleep 30
                done
            ) &
            zenity --info --text="Scheduler started. Daily scan will run at $SCHEDULE_TIME."
            ;;

	"View Last Scan Summary")
    while true; do
        LAST_ID=$(cat "$LOG_DIR/last-scan-id.txt" 2>/dev/null)
        LAST_MODE=$(cat "$LOG_DIR/last-scan-mode.txt" 2>/dev/null)

        if [ -z "$LAST_ID" ] || [ ! -f "$LOG_DIR/scan-$LAST_ID.log" ]; then
            zenity --info --text="No scans have been run yet."
            break
        fi

        SUMMARY=$(grep -E 'Starting|new IPs|Exported' "$LOG_DIR/scan-$LAST_ID.log")
        zenity --question \
            --width=500 --height=300 \
            --title="Last Scan Summary" \
            --text="Mode: $LAST_MODE\n\n$SUMMARY\n\nWould you like to view the new IPs from this scan?" \
            --ok-label="View Differential" --cancel-label="Back to Main Menu"

        if [ $? -eq 0 ]; then
            zenity --text-info --title="New IPs from Last Scan" \
                --width=600 --height=400 \
                --filename="$LOG_DIR/diff-$LAST_ID.txt"
        else
            break
        fi
    done
    ;;


        "Instructions")
            zenity --text-info --width=500 --height=600 \
                --title="Instructions" \
                # Need to add instructions.txt file to the configs directory. (Watch me completely forget to do this lol)
                --filename="instructions.txt"
            ;;

	"Settings")
    while true; do
        SETTINGS_CHOICE=$(zenity --list --title="Settings Menu" \
            --width=400 --height=300 \
            --column="Settings Options" \
            "Account Settings" \
            "Back to Main Menu")

        case "$SETTINGS_CHOICE" in
            "Account Settings")
            
    while true; do
        ACCOUNT_CHOICE=$(zenity --list --title="Account Settings" \
            --width=400 --height=500 \
            --column="Option" \
            "Change User Password" \
            "Add an Admin" \
            "Add an Analyst" \
            "Remove a User" \
            "Back")

        case "$ACCOUNT_CHOICE" in
        
	    "Change User Password")
    # Ask for current password
    CURRENT_PASSWORD=$(zenity --password --title="Verify Current Password")
    STORED_LINE=$(grep "^$CURRENT_USER:" "$USER_FILE")
    SALT=$(echo "$STORED_LINE" | cut -d: -f2)
    STORED_HASH=$(echo "$STORED_LINE" | cut -d: -f3)

    INPUT_HASH=$(echo -n "$SALT$CURRENT_PASSWORD" | sha256sum | awk '{print $1}')
    if [ "$INPUT_HASH" != "$STORED_HASH" ]; then
        zenity --error --title="Authentication Failed" --text="Incorrect current password."
        continue
    fi

    # Get new password and double check
    NEW_PASSWORD=$(zenity --password --title="Enter New Password")
    CONFIRM_PASSWORD=$(zenity --password --title="Confirm New Password")

    if [ -z "$NEW_PASSWORD" ] || [ -z "$CONFIRM_PASSWORD" ]; then
        zenity --error --text="Password fields cannot be empty."
        continue
    fi

    if [ "$NEW_PASSWORD" != "$CONFIRM_PASSWORD" ]; then
        zenity --error --text="Passwords do not match. Please try again."
        continue
    fi

    # Create new salted hash and update line
    NEW_SALT=$(openssl rand -hex 8)
    NEW_HASH=$(echo -n "$NEW_SALT$NEW_PASSWORD" | sha256sum | awk '{print $1}')
    ROLE=$(echo "$STORED_LINE" | cut -d: -f4)

    # Replace old line with updated credentials
    grep -v "^$CURRENT_USER:" "$USER_FILE" > temp_users.txt
    echo "$CURRENT_USER:$NEW_SALT:$NEW_HASH:$ROLE" >> temp_users.txt
    mv temp_users.txt "$USER_FILE"

    zenity --info --title="Password Changed" --text="Your password was successfully updated."
    ;;

        
        
        
            "Add an Admin")
    if [ "$CURRENT_ROLE" != "admin" ]; then
        zenity --error --title="Permission Denied" \
            --text="Only Admins can add new users."
        continue
    fi

    NEW_USERNAME=$(zenity --entry --title="Add Admin" --text="Enter a username for the new admin:")
    if [ -z "$NEW_USERNAME" ]; then
        zenity --error --text="Username cannot be empty."
        continue
    fi

    # Check if user already exists
    if grep -q "^$NEW_USERNAME:" "$USER_FILE"; then
        zenity --error --text="This username already exists."
        continue
    fi

    NEW_PASSWORD=$(zenity --password --title="New Admin Password")
    CONFIRM_PASSWORD=$(zenity --password --title="Confirm Password")

    if [ -z "$NEW_PASSWORD" ] || [ -z "$CONFIRM_PASSWORD" ]; then
        zenity --error --text="Password fields cannot be empty."
        continue
    fi

    if [ "$NEW_PASSWORD" != "$CONFIRM_PASSWORD" ]; then
        zenity --error --text="Passwords do not match."
        continue
    fi

    SALT=$(openssl rand -hex 8)
    HASH=$(echo -n "$SALT$NEW_PASSWORD" | sha256sum | awk '{print $1}')
    echo "$NEW_USERNAME:$SALT:$HASH:admin" >> "$USER_FILE"
    zenity --info --text="Admin user '$NEW_USERNAME' created successfully."
    ;;

            "Add an Analyst")
    if [ "$CURRENT_ROLE" != "admin" ]; then
        zenity --error --title="Permission Denied" \
            --text="Only Admins can add new users."
        continue
    fi

    NEW_USERNAME=$(zenity --entry --title="Add Analyst" --text="Enter a username for the new analyst:")
    if [ -z "$NEW_USERNAME" ]; then
        zenity --error --text="Username cannot be empty."
        continue
    fi

    # Check if user already exists
    if grep -q "^$NEW_USERNAME:" "$USER_FILE"; then
        zenity --error --text="This username already exists."
        continue
    fi

    NEW_PASSWORD=$(zenity --password --title="New Analyst Password")
    CONFIRM_PASSWORD=$(zenity --password --title="Confirm Password")

    if [ -z "$NEW_PASSWORD" ] || [ -z "$CONFIRM_PASSWORD" ]; then
        zenity --error --text="Password fields cannot be empty."
        continue
    fi

    if [ "$NEW_PASSWORD" != "$CONFIRM_PASSWORD" ]; then
        zenity --error --text="Passwords do not match."
        continue
    fi

    SALT=$(openssl rand -hex 8)
    HASH=$(echo -n "$SALT$NEW_PASSWORD" | sha256sum | awk '{print $1}')
    echo "$NEW_USERNAME:$SALT:$HASH:analyst" >> "$USER_FILE"
    zenity --info --text="Analyst user '$NEW_USERNAME' created successfully."
    ;;

            "Remove a User")
    if [ "$CURRENT_ROLE" != "admin" ]; then
        zenity --error --title="Permission Denied" \
            --text="Only Admins can remove users."
        continue
    fi

    # List all usernames except the current user
    USER_LIST=$(cut -d: -f1 "$USER_FILE" | grep -v "^$CURRENT_USER")

    if [ -z "$USER_LIST" ]; then
        zenity --info --text="No users available to remove (other than yourself)."
        continue
    fi

    USER_TO_REMOVE=$(zenity --list --title="Select User to Remove" \
        --width=400 --height=400 \
        --column="Username" $USER_LIST)

    if [ -z "$USER_TO_REMOVE" ]; then
        continue
    fi

    # Count total number of admins
    ADMIN_COUNT=$(awk -F: '$4 == "admin"' "$USER_FILE" | wc -l)

    # Get the role of the user selected for removal
    USER_ROLE=$(grep "^$USER_TO_REMOVE:" "$USER_FILE" | cut -d: -f4)

    # Prevent deletion of the last remaining admin
    if [[ "$USER_ROLE" == "admin" && "$ADMIN_COUNT" -eq 1 ]]; then
        zenity --error --text="You cannot remove the last remaining admin account."
        continue
    fi

    # Prompt for current user's password
    VERIFY_PASS=$(zenity --password --title="Authenticate Admin Action")
    CURRENT_SALT=$(grep "^$CURRENT_USER:" "$USER_FILE" | cut -d: -f2)
    CURRENT_HASH=$(grep "^$CURRENT_USER:" "$USER_FILE" | cut -d: -f3)
    INPUT_HASH=$(echo -n "$CURRENT_SALT$VERIFY_PASS" | sha256sum | awk '{print $1}')

    if [[ "$INPUT_HASH" != "$CURRENT_HASH" ]]; then
        zenity --error --text="Authentication failed. Cannot proceed with removal."
        continue
    fi

    # Final confirmation
    zenity --question --title="Confirm Removal" \
        --text="Are you sure you want to remove user '$USER_TO_REMOVE'?"

    if [ $? -eq 0 ]; then
        grep -v "^$USER_TO_REMOVE:" "$USER_FILE" > temp_users.txt && mv temp_users.txt "$USER_FILE"
        zenity --info --text="User '$USER_TO_REMOVE' has been removed."
    fi
    ;;


            "Back" | "") break ;;
        esac
    done
    ;;

            "Back to Main Menu" | "" )
                break
                ;;
        esac
    done
    ;;

	
	
        "Exit")
            break
            ;;

        *)
            zenity --warning --text="Please select the 'Exit' Option to exit the application."
            ;;
    esac
done
