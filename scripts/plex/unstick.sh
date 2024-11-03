#!/bin/bash

# This script fixes Plex media stuck in the recently added list, by setting their added date to their updated date.

# If used in a non-Saltbox context, you can change the PLEX_URL value to the appropriate one for
# your use case, and supply the Plex token as a command-line argument when running the script.

# Read token from config file
if [ -f "/opt/saltbox/plex.ini" ]; then
    DEFAULT_TOKEN=$(awk -F "=" '/^token/ {print $2}' /opt/saltbox/plex.ini | tr -d ' ')
fi

# Use command line token if provided, otherwise use config token
PLEX_TOKEN="${1:-$DEFAULT_TOKEN}"

if [ -z "$PLEX_TOKEN" ]; then
    echo "No Plex token found in config and none provided as argument"
    echo "Usage: $0 [PLEX_TOKEN]"
    exit 1
fi

PLEX_URL="http://plex:32400"

# Get current Unix timestamp
NOW=$(date +%s)
echo "Current timestamp: $NOW"

echo "Checking all library items..."
response=$(curl -s "${PLEX_URL}/library/all?X-Plex-Token=${PLEX_TOKEN}" \
  -H "Accept: application/json")

future_items=$(echo "$response" | jq --arg now "$NOW" '.MediaContainer.Metadata[]
    | select(.addedAt > ($now|tonumber))
    | {
        id: .ratingKey,
        addedAt: .addedAt,
        updatedAt: .updatedAt,
        title: .title,
        librarySectionID: .librarySectionID,
        type: .type
      }')

if [ ! -z "$future_items" ]; then
    echo "Found items with future dates:"
    echo "$future_items" | jq -r '. | "- \(.title) (ID: \(.id), Type: \(.type))\n  Current addedAt: \(.addedAt)\n  Will set to: \(.updatedAt)"'

    echo -e "\nFixing dates..."
    echo "$future_items" | jq -c '.' | while read -r item; do
        id=$(echo "$item" | jq -r '.id')
        updated_at=$(echo "$item" | jq -r '.updatedAt')
        title=$(echo "$item" | jq -r '.title')
        added_at=$(echo "$item" | jq -r '.addedAt')
        section_id=$(echo "$item" | jq -r '.librarySectionID')
        item_type=$(echo "$item" | jq -r '.type')

        # Map content type to numeric type ID
        case "$item_type" in
            "movie") type_id=1 ;;
            "show") type_id=2 ;;
            "season") type_id=3 ;;
            "episode") type_id=4 ;;
            *) continue ;;
        esac

        echo "Setting '$title' (ID: $id, Type: $item_type)"
        echo "  From: $(date -d @${added_at} '+%Y-%m-%d %H:%M:%S')"
        echo "  To:   $(date -d @${updated_at} '+%Y-%m-%d %H:%M:%S')"

        curl -s -X PUT "${PLEX_URL}/library/sections/${section_id}/all?type=${type_id}&id=${id}&addedAt.value=${updated_at}&X-Plex-Token=${PLEX_TOKEN}"
    done

    echo -e "\nAll future dates have been fixed"
else
    echo "No items with future dates found"
fi

echo "Update complete"
