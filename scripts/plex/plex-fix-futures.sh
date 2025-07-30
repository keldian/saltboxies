#!/bin/bash

# Fixes Plex "recently added" items stuck in the future by setting their added date to their updated date
#
# Use cases:
# 1. Saltbox host mode:
#    - Run without arguments
#    - Automatically processes all Plex instances defined in Saltbox
#    - Example: `/opt/scripts/plex/plex-fix-futures.sh`
#
# 2. Single-instance mode:
#    - Non-Saltbox users or external access
#    - Must have the following packages installed:
#        - curl
#        - jq
#        - awk
#        - tr
#        - date
#        - grep
#    - Requires URL and token arguments
#    - Processes single specified Plex instance
#    - Example: `./plex-fix-futures.sh -u http://192.168.1.200:32400 -t y0_uRt0k3nv4Lu3h-3R3`
#    - Example: `./plex-fix-futures.sh -u https://plex.example.com -t y0_uRt0k3nv4Lu3h-3R3`

declare -A PLEX_INSTANCES

while getopts "t:u:" opt; do
    case $opt in
        t) CLI_TOKEN="$OPTARG" ;;
        u) CLI_URL="$OPTARG" ;;
        *) echo "Invalid option: -$OPTARG" >&2
           exit 1
           ;;
    esac
done

process_plex_instance() {
    local PLEX_URL="$1"
    local PLEX_TOKEN="$2"

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

    if [ -n "$future_items" ]; then
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
            echo "  From: $(date -d "@${added_at}" '+%Y-%m-%d %H:%M:%S')"
            echo "  To:   $(date -d "@${updated_at}" '+%Y-%m-%d %H:%M:%S')"

            curl -X PUT "${PLEX_URL}/library/sections/${section_id}/all?type=${type_id}&id=${id}&addedAt.value=${updated_at}&X-Plex-Token=${PLEX_TOKEN}"
        done

        echo -e "\nAll futures have been fixed"
    else
        echo "No futures found"
    fi
}
if [ -f "/srv/git/saltbox/inventories/host_vars/localhost.yml" ] && [ -z "$CLI_URL" ]; then
    if ! PLEX_LIST=$(yyq '.plex_instances[]' /srv/git/saltbox/inventories/host_vars/localhost.yml); then
        echo "Error reading Plex instances from inventory file"
        echo "The Saltbox inventory file appears to be malformed"
        echo "Location: /srv/git/saltbox/inventories/host_vars/localhost.yml"
        echo "Fix any YAML formatting issues and try again"
        exit 1
    fi

    # If no instances defined, use default 'plex'
    if [ -z "$PLEX_LIST" ]; then
        PLEX_LIST="plex"
    fi

    while read -r PLEX_INSTANCE; do
        if [ -f "/opt/saltbox/plex.ini" ]; then
            INSTANCE_TOKEN=$(awk -v section="$PLEX_INSTANCE" '
                BEGIN { in_section=0 }
                $0 ~ "^\\[" section "\\]" { in_section=1; next }
                $0 ~ "^\\[" { in_section=0 }
                in_section && /^token/ { gsub(/^token *= */, ""); print $0 }
            ' /opt/saltbox/plex.ini | tr -d ' ')

            if [ -n "$INSTANCE_TOKEN" ]; then
                PLEX_INSTANCES["http://${PLEX_INSTANCE}:32400"]="$INSTANCE_TOKEN"
            else
                echo "No token found for instance: $PLEX_INSTANCE"
            fi
        fi
    done <<< "$PLEX_LIST"
elif [ -n "$CLI_TOKEN" ] && [ -n "$CLI_URL" ]; then
    PLEX_INSTANCES["$CLI_URL"]="$CLI_TOKEN"
else
    echo "Usage: $0 [-t TOKEN] [-u URL]"
    echo "Options:"
    echo "  -t: Plex token"
    echo "  -u: Full Plex URL"
    echo "Examples:"
    echo "  $0                                                          # Saltbox host"
    echo "  $0 -u http://192.168.1.200:32400 -t y0_uRt0k3nv4Lu3h-3R3    # Local network"
    echo "  $0 -u https://plex.example.com -t y0_uRt0k3nv4Lu3h-3R3      # Domain name"
    exit 1
fi

for url in "${!PLEX_INSTANCES[@]}"; do
    if ! curl -s -f -I "$url" >/dev/null 2>&1 && ! curl -s -I "$url" 2>&1 | grep -q "401"; then
        echo "Error: Unable to connect to Plex instance at $url"
        echo "Ensure the instance is running and accessible"
        continue
    fi

    echo "Processing Plex instance at $url"
    process_plex_instance "$url" "${PLEX_INSTANCES[$url]}"
done
