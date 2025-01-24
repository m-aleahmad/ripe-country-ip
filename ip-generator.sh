#!/bin/bash

# URL of the data
URL="ftp://ftp.ripe.net/pub/stats/ripencc/delegated-ripencc-extended-latest"

# Temporary file to store the downloaded data
TEMP_FILE="delegated-ripencc-latest.txt"

# Country code to filter (e.g., "IR" for Iran)
COUNTRY_CODE="IR"

# Output file for the IP prefixes of the specified country
OUTPUT_FILE="${COUNTRY_CODE}_ip_prefixes.txt"

# MikroTik script output file
MIKROTIK_SCRIPT="${COUNTRY_CODE}_address_list.rsc"

# Archive Path
ARCHIVE_FOLDER="/archive"

# Maximum retry attempts for wget
MAX_RETRIES=5
RETRY_DELAY=10

# Bogon IPs to include
BOGON_IPS=(
    "10.0.0.0/8"
    "172.16.0.0/12"
    "192.168.0.0/16"
)

# Function to download the file with retries and a timeout
download_file() {
    local attempt=1
    while [ $attempt -le $MAX_RETRIES ]; do
        echo "Attempt $attempt to download the file..."
        wget --timeout=20 -O "$TEMP_FILE" "$URL"
        if [ $? -eq 0 ]; then
            echo "File downloaded successfully."
            return 0
        else
            echo "Download failed. Retrying in $RETRY_DELAY seconds..."
            sleep $RETRY_DELAY
        fi
        attempt=$((attempt + 1))
    done
    echo "Failed to download the file after $MAX_RETRIES attempts."
    return 1
}

# Ensure the MikroTik script file does not exist
if [ -f "$MIKROTIK_SCRIPT" ]; then
    echo "Removing existing MikroTik script: $MIKROTIK_SCRIPT"
    rm "$MIKROTIK_SCRIPT"
fi

# Ensure the archive folder exists
mkdir -p "$ARCHIVE_FOLDER"

# Check if the log file exists
if [ -f "$OUTPUT_FILE" ]; then
    # Get the file's creation date
    CREATION_DATE=$(stat -c '%y' "$OUTPUT_FILE" | cut -d' ' -f1)

    # Move the log file to the archive folder with the creation date in the name
    mv "$OUTPUT_FILE" "$ARCHIVE_FOLDER/${COUNTRY_CODE}_ip_$CREATION_DATE.log"
    echo "Archived previous file"
fi

# Download the file
download_file
if [ $? -ne 0 ]; then
    exit 1
fi

# Extract IP prefixes for the specified country and calculate CIDR
grep "|${COUNTRY_CODE}|ipv4|" "$TEMP_FILE" | while IFS='|' read -r registry cc type ip size date status other; do
    # Calculate prefix length from size
    prefix_length=$(( 32 - $(echo "l($size)/l(2)" | bc -l | awk '{print int($1)}') ))
    echo "$ip/$prefix_length" >> "$OUTPUT_FILE"
done

echo "IP prefixes for country code '${COUNTRY_CODE}' saved to $OUTPUT_FILE."

# Create MikroTik script file and include cleanup command
echo "# MikroTik Address List for ${COUNTRY_CODE}" > "$MIKROTIK_SCRIPT"
echo "/ip firewall address-list" >> "$MIKROTIK_SCRIPT"
echo "remove [find list=${COUNTRY_CODE}]" >> "$MIKROTIK_SCRIPT"

# Add country-specific IP prefixes to MikroTik script
while read -r prefix; do
    echo "add address=${prefix} list=${COUNTRY_CODE}" >> "$MIKROTIK_SCRIPT"
done < "$OUTPUT_FILE"

# Add bogon IPs to MikroTik script
echo "# Adding bogon IPs to the address list" >> "$MIKROTIK_SCRIPT"
for bogon in "${BOGON_IPS[@]}"; do
    echo "add address=${bogon} list=${COUNTRY_CODE}" >> "$MIKROTIK_SCRIPT"
done

echo "MikroTik script generated: $MIKROTIK_SCRIPT"

# Cleanup: Remove the temporary file
if [ -f "$TEMP_FILE" ]; then
    rm "$TEMP_FILE"
    echo "Temporary file cleaned up."
fi

