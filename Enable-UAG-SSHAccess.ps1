param(
    [string]$vCenter,
    [string]$vmName,
    [string]$guestPassword
)

# --- 0. Pre-requisites ---
# Automatically ignore invalid SSL certificates
Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false -Scope Session | Out-Null

# --- 1. vCenter Authentication ---
# Only prompt if vCenter was NOT passed as a parameter
if (-not $vCenter) {
    $vCenter = Read-Host "Enter vCenter hostname/IP"
}

# Check existing connection
$currentSession = $global:DefaultVIServer | Where-Object { $_.Name -eq $vCenter -and $_.IsConnected }

if (-not $currentSession) {
    Write-Host "`n--- vCenter Login ($vCenter) ---" -ForegroundColor Yellow
    
    $vcUser = Read-Host "Enter Username (Press Enter for 'administrator@vsphere.local')"
    if (-not $vcUser) { $vcUser = "administrator@vsphere.local" }

    $vcPass = Read-Host "Enter Password for $vcUser" -AsSecureString
    $vcCred = New-Object System.Management.Automation.PSCredential ($vcUser, $vcPass)

    Write-Host "Connecting..." -ForegroundColor Cyan
    try {
        Connect-VIServer -Server $vCenter -Credential $vcCred -ErrorAction Stop | Out-Null
        Write-Host "Successfully connected to vCenter." -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to connect to vCenter."
        Write-Error "Details: $($_.Exception.Message)"
        exit 1
    }
}

# --- 2. Target VM Selection ---
# Only prompt if vmName was NOT passed as a parameter
if (-not $vmName) {
    $vmName = Read-Host "`nEnter UAG VM Name"
}

# --- 3. UAG Guest Credentials ---
$guestUser = "root"
# Only prompt if guestPassword was NOT passed as a parameter
if (-not $guestPassword) {
    Write-Host "`n--- UAG Guest Login ---" -ForegroundColor Yellow
    $securePassword = Read-Host "Enter UAG root password" -AsSecureString
    
    # FIXED: Conversion is now on a single line to avoid parser errors
    $guestPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword))
}

# --- 4. Get VM & Check Health ---
Write-Host "`nLooking for VM: $vmName..." -ForegroundColor Cyan
$uagVM = Get-VM -Name $vmName -ErrorAction SilentlyContinue

if (-not $uagVM) {
    Write-Error "VM '$vmName' not found in vCenter $vCenter."
    exit 1
}

if ($uagVM.Guest.RuntimeGuestState -ne "guestRunning") {
    Write-Warning "VMware Tools is NOT running on $vmName."
    Write-Warning "Invoke-VMScript relies on VMware Tools. The commands below will likely fail."
}

# --- 5. Execution Logic ---
$cmds = @(
  "sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config",
  "systemctl enable sshd",
  "systemctl restart sshd"
)

Write-Host "Enabling SSH access on $vmName..." -ForegroundColor Cyan

foreach ($cmd in $cmds) {
    try {
        $result = Invoke-VMScript -VM $uagVM -ScriptText $cmd -GuestUser $guestUser -GuestPassword $guestPassword -ScriptType Bash -ErrorAction Stop
        
        if ($result.ExitCode -eq 0) {
            Write-Host "  [OK] $cmd" -ForegroundColor Gray
        } else {
            Write-Warning "  [FAIL] $cmd (Exit Code: $($result.ExitCode))"
            Write-Host "  Output: $($result.ScriptOutput)" -ForegroundColor Red
        }
    }
    catch {
        Write-Error "  Failed to execute command via VMware Tools."
        Write-Error "  Details: $($_.Exception.Message)"
    }
}

Write-Host "`nScript Complete. SSH should now be enabled." -ForegroundColor Green
