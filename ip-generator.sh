#!/bin/bash

# Static URL of the data
URL="ftp://ftp.ripe.net/pub/stats/ripencc/delegated-ripencc-extended-latest"

# Country code to filter (default is "IR" for Iran, can be overridden via argument)
COUNTRY_CODE="${1:-IR}"

# Temporary file to store the downloaded data
TEMP_FILE="delegated-ripencc-latest.txt"

# Output files
OUTPUT_FILE="${COUNTRY_CODE}_ip_prefixes.txt"
MIKROTIK_SCRIPT="${COUNTRY_CODE}_address_list.rsc"

# Backup folder (within the repository)
ARCHIVE_FOLDER="backup"

# Maximum retry attempts for wget
MAX_RETRIES=5
RETRY_DELAY=10

# Bogon IPs
BOGON_IPS=("10.0.0.0/8" "172.16.0.0/12" "192.168.0.0/16")

# Ensure required commands are installed
if ! command -v bc &>/dev/null || ! command -v awk &>/dev/null; then
    echo "Error: Required commands 'bc' or 'awk' are not installed."
    exit 1
fi

# Ensure backup folder exists
mkdir -p "$ARCHIVE_FOLDER"

# Function to download the file with retries
download_file() {
    local attempt=1
    while [ $attempt -le $MAX_RETRIES ]; do
        echo "Attempt $attempt to download the file..."
        wget --timeout=20 -O "$TEMP_FILE" "$URL"
        if [ $? -eq 0 ]; then
            echo "File downloaded successfully."
            return 0
        fi
        echo "Download failed. Retrying in $RETRY_DELAY seconds..."
        sleep $RETRY_DELAY
        attempt=$((attempt + 1))
    done
    echo "Failed to download the file after $MAX_RETRIES attempts."
    return 1
}

# Archive old output
if [ -f "$OUTPUT_FILE" ]; then
    CREATION_DATE=$(date '+%Y-%m-%d')
    mv "$OUTPUT_FILE" "$ARCHIVE_FOLDER/${COUNTRY_CODE}_ip_$CREATION_DATE.log"
    echo "Archived previous file to $ARCHIVE_FOLDER"
fi

# Download data
download_file || exit 1

# Extract IP prefixes
grep "|${COUNTRY_CODE}|ipv4|" "$TEMP_FILE" | while IFS='|' read -r registry cc type ip size date status other; do
    prefix_length=$(( 32 - $(echo "l($size)/l(2)" | bc -l | awk '{print int($1)}') ))
    echo "$ip/$prefix_length" >> "$OUTPUT_FILE"
done
echo "IP prefixes for '${COUNTRY_CODE}' saved to $OUTPUT_FILE."

# Generate MikroTik script
{
    echo "# MikroTik Address List for ${COUNTRY_CODE}"
    echo "/ip firewall address-list"
    echo "remove [find list=${COUNTRY_CODE}]"
    while read -r prefix; do
        echo "add address=${prefix} list=${COUNTRY_CODE}"
    done < "$OUTPUT_FILE"
    for bogon in "${BOGON_IPS[@]}"; do
        echo "add address=${bogon} list=${COUNTRY_CODE}"
    done
} > "$MIKROTIK_SCRIPT"
echo "MikroTik script generated: $MIKROTIK_SCRIPT"

# Cleanup
rm -f "$TEMP_FILE"
echo "Temporary file cleaned up."

