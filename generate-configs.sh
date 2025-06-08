#!/bin/bash
set -e

# Create config directory if it doesn't exist
mkdir -p ./configs

# Node 1 configuration
export JVM_ROUTE=node1
export NODE_IP=172.21.0.3  # Update with actual node1 IP if different
export OTHER_NODE_IP=172.21.0.4  # Update with actual node2 IP if different

envsubst < ./custom-entrypoint/server.xml.template > ./configs/server-node1.xml

# Node 2 configuration
export JVM_ROUTE=node2
export NODE_IP=172.21.0.4  # Update with actual node2 IP if different
export OTHER_NODE_IP=172.21.0.3  # Update with actual node1 IP if different

envsubst < ./custom-entrypoint/server.xml.template > ./configs/server-node2.xml

echo "Configuration files generated in ./configs/ directory"
