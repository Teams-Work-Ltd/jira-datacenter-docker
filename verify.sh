#!/bin/bash

# -------- CONFIG --------
JIRA_USER="admin"
JIRA_PASS="admin"
HAPROXY_URL="http://localhost"                     # Accessible HAProxy frontend
NODE1_URL="http://172.21.0.3:8080"
NODE2_URL="http://172.21.0.4:8080"
LOGIN_PATH="/login.jsp"
DASHBOARD_PATH="/secure/Dashboard.jspa"
# ------------------------

echo "[*] Step 1: Logging in via HAProxy ($HAPROXY_URL)"

# Log in and capture cookie
COOKIE_JAR=$(mktemp)
curl -s -c "$COOKIE_JAR" \
  -d "os_username=$JIRA_USER&os_password=$JIRA_PASS&login=Log+In" \
  "$HAPROXY_URL$LOGIN_PATH" > /dev/null

JSESSIONID=$(grep JSESSIONID "$COOKIE_JAR" | awk '{print $7}')
ROUTE=$(echo "$JSESSIONID" | cut -d '.' -f2)

if [[ -z "$JSESSIONID" || -z "$ROUTE" ]]; then
  echo "[!] Failed to retrieve a valid JSESSIONID. Aborting."
  rm "$COOKIE_JAR"
  exit 1
fi

echo "[+] Got session: $JSESSIONID (from $ROUTE)"

# Flip to other node
if [[ "$ROUTE" == "node1" ]]; then
  ALT_NODE="node2"
  ALT_NODE_URL="$NODE2_URL"
else
  ALT_NODE="node1"
  ALT_NODE_URL="$NODE1_URL"
fi

echo "[*] Step 2: Accessing dashboard on $ALT_NODE ($ALT_NODE_URL)"

RESPONSE=$(curl -s -b "JSESSIONID=$JSESSIONID" "$ALT_NODE_URL$DASHBOARD_PATH")

if echo "$RESPONSE" | grep -q "login-form"; then
  echo "[-] FAIL: Session NOT replicated. Login page returned from $ALT_NODE."
else
  echo "[+] PASS: Session replicated. Got dashboard from $ALT_NODE."
fi

rm "$COOKIE_JAR"
