$ips = @("172.23.245.176","172.23.246.112","172.23.249.121")
foreach ($ip in $ips) {
    Write-Host "Testing SSH on $ip..." -NoNewline
    $result = Test-NetConnection $ip -Port 22 -WarningAction SilentlyContinue
    if ($result.TcpTestSucceeded) {
        Write-Host " OK!" -ForegroundColor Green
    } else {
        Write-Host " FAIL" -ForegroundColor Red
    }
}
