param(
    [string]$vCenter,
    [string]$vmName,
    [string]$guestPassword
)

# Prompt only if values not passed
if (-not $vCenter) {
    $vCenter = Read-Host "Enter vCenter hostname/IP"
}
if (-not $vmName) {
    $vmName = Read-Host "Enter UAG VM name"
}
$guestUser = "root"
if (-not $guestPassword) {
    $securePassword = Read-Host "Enter root password (will not be displayed)" -AsSecureString
    $guestPassword = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword)
    )
}

# Connect to vCenter
Write-Host "`nConnecting to vCenter $vCenter..." -ForegroundColor Cyan
Connect-VIServer -Server $vCenter | Out-Null

# Get the VM
$uagVM = Get-VM -Name $vmName
if (-not $uagVM) {
    Write-Error "❌ VM $vmName not found in vCenter."
    exit 1
}

# Commands to enable SSH and root login
$cmds = @(
  "sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config",
  "systemctl enable sshd || systemctl enable ssh",
  "systemctl start sshd || systemctl start ssh"
)

Write-Host "`nEnabling SSH access on $vmName..." -ForegroundColor Cyan
foreach ($cmd in $cmds) {
    $result = Invoke-VMScript -VM $uagVM -ScriptText $cmd -GuestUser $guestUser -GuestPassword $guestPassword -ScriptType Bash
    if ($result.ExitCode -ne 0) {
        Write-Warning "⚠️ Command failed: $cmd"
    }
}

Write-Host "`n✅ SSH is now enabled and running. Root login is permitted." -ForegroundColor Green
