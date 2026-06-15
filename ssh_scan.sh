#!/bin/bash
for ip in 172.23.241.74 172.23.246.121 172.23.246.167 172.23.247.95 172.23.247.221 172.23.249.94 172.23.251.56 172.23.252.0 172.23.255.118; do
    echo -n "Trying $ip... "
    result=$(sshpass -p mbos ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=3 mbuser@$ip 'echo OK' 2>&1)
    if echo "$result" | grep -q OK; then
        echo "CONNECTED!"
        sshpass -p mbos ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null mbuser@$ip '
            echo "=== UNAME ==="
            uname -a
            echo "=== GUI LOG ==="
            cat /tmp/mb-gui.log 2>/dev/null || echo "no gui log"
            echo "=== SHELL ERROR ==="
            cat /tmp/mb-shell-error.log 2>/dev/null || echo "no error log"
            echo "=== LDD CHECK ==="
            ldd /usr/local/bin/mb-os-shell 2>&1 | grep -i "not found" || echo "All deps OK!"
            echo "=== DONE ==="
        ' 2>&1
        exit 0
    else
        echo "nope"
    fi
done
echo "Keine VM gefunden"
