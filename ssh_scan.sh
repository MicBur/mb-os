#!/bin/bash
for ip in 172.23.241.74 172.23.246.121 172.23.247.95 172.23.247.221 172.23.249.94 172.23.251.56 172.23.252.0 172.23.255.118; do
    echo -n "$ip: "
    timeout 4 ssh -o StrictHostKeyChecking=no -o ConnectTimeout=3 -o PasswordAuthentication=no mbuser@$ip \
        'cat /tmp/mb-shell-error.log 2>/dev/null; echo "---LDD---"; ldd /usr/local/bin/mb-os-shell 2>&1 | grep -i "not found"' 2>&1 | head -10
    echo ""
done
