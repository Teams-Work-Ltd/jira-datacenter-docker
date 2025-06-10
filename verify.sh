#!/bin/bash

# -------- CONFIG --------
JIRA_USER="admin"
JIRA_PASS="admin"
HAPROXY_URL="http://localhost"  # Accessible HAProxy frontend
NODE1_URL="http://localhost:9090"
NODE2_URL="http://localhost:9091"
LOGIN_PATH="/login.jsp"
DASHBOARD_PATH="/secure/Dashboard.jspa"
# ------------------------

# Function to clean up temp files
cleanup() {
  if [ -f "$COOKIE_JAR" ]; then
    rm -f "$COOKIE_JAR"
  fi
}

# Setup trap to ensure cleanup on exit
trap cleanup EXIT

# Create temp file for cookies
COOKIE_JAR=$(mktemp)

# Check if nodes are reachable
check_node() {
    echo "[*] Testing connection to $1"
    # First check basic connectivity
    if ! curl -s --head --connect-timeout 5 --max-time 10 --fail "$1" >/dev/null 2>&1; then
        # If HEAD fails, try GET with verbose output
        echo "[!] Basic connection check failed. Running detailed check..."
        if ! curl -v --connect-timeout 5 --max-time 10 "$1" 2>&1 | grep -q "HTTP/1.1 200"; then
            echo "[!] Node $1 is not reachable or not returning a successful response."
            echo "    Please check:"
            echo "    1. Is Jira running? (docker ps to check containers)"
            echo "    2. Is the port correct? (trying to reach $1)"
            echo "    3. Can you access it from your browser? (tried: $1)"
            echo "    4. Check Jira logs with: docker compose logs node1"
            return 1
        fi
    fi
    echo "[✓] Successfully connected to $1"
    return 0
}

echo "[*] Checking node availability..."
check_node "$NODE1_URL" || exit 1
check_node "$NODE2_URL" || exit 1

echo "[*] Step 1: Logging in via HAProxy ($HAPROXY_URL)"

# Log in and capture cookie
if ! curl -s -c "$COOKIE_JAR" \
  -d "os_username=$JIRA_USER&os_password=$JIRA_PASS&login=Log+In" \
  "$HAPROXY_URL$LOGIN_PATH" > /dev/null; then
  echo "[!] Failed to log in to Jira"
  exit 1
fi

JSESSIONID=$(grep JSESSIONID "$COOKIE_JAR" | awk '{print $7}')
ROUTE=$(echo "$JSESSIONID" | cut -d '.' -f2)

if [[ -z "$JSESSIONID" || -z "$ROUTE" ]]; then
  echo "[!] Failed to retrieve a valid JSESSIONID. Check login credentials and HAProxy configuration."
  exit 1
fi

echo "[+] Got session: $JSESSIONID (from $ROUTE)"

# Test session on the same node first
echo "[*] Step 2: Verifying session on original node ($ROUTE)"
if ! curl -s -b "JSESSIONID=$JSESSIONID" "${!ROUTE^^}_URL$DASHBOARD_PATH" | grep -q "login-form"; then
  echo "[+] Session works on original node ($ROUTE)"
else
  echo "[-] Session not working on original node ($ROUTE)"
  exit 1
fi

# Test on the other node
if [[ "$ROUTE" == "node1" ]]; then
  ALT_NODE="NODE2"
  ALT_NODE_URL="$NODE2_URL"
else
  ALT_NODE="NODE1"
  ALT_NODE_URL="$NODE1_URL"
fi

echo "[*] Step 3: Testing session on alternate node (${ALT_NODE#NODE})"
RESPONSE=$(curl -s -b "JSESSIONID=$JSESSIONID" "$ALT_NODE_URL$DASHBOARD_PATH")

if echo "$RESPONSE" | grep -q "login-form"; then
  echo "[-] FAIL: Session NOT replicated. Login page returned from ${ALT_NODE#NODE}."
  exit 1
else
  echo "[+] PASS: Session replicated successfully to ${ALT_NODE#NODE}."
  exit 0
fi