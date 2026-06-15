# PowerShell Direct - VM Diagnose (Als Admin ausführen!)
$VMName = "MB-OS"
$password = ConvertTo-SecureString "mbos" -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential("mbuser", $password)

Write-Host ">>> Verbinde mit VM '$VMName' via PowerShell Direct..."

Invoke-Command -VMName $VMName -Credential $cred -ScriptBlock {
    echo "=== CONNECTED ==="
    echo "=== SHELL ERROR ==="
    cat /tmp/mb-shell-error.log 2>/dev/null
    echo "=== GUI LOG ==="
    cat /tmp/mb-gui.log 2>/dev/null
    echo "=== WHICH APPS ==="
    ls /usr/local/bin/mb-* 2>/dev/null
    ls /usr/local/bin/agy* 2>/dev/null
    echo "=== ANTIGRAVITY ==="
    which antigravity 2>/dev/null
    which agy 2>/dev/null
    cat /usr/local/bin/agy 2>/dev/null
    echo "=== PROCESSES ==="
    ps aux | grep -E 'mb-os|openbox|antigrav' | grep -v grep
    echo "=== DONE ==="
}
