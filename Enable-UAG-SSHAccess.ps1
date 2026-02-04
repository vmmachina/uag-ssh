param(
    [string]$vCenter,
    [string]$vmName,
    [string]$guestPassword
)

# --- 0. Pre-requisites ---
# Ignore invalid SSL certificates
Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false -Scope Session | Out-Null

# --- 1. vCenter Authentication (Text-Based) ---
if (-not $vCenter) {
    $vCenter = Read-Host "Enter vCenter hostname/IP"
}

# Check if already connected
$currentSession = $global:DefaultVIServer | Where-Object { $_.Name -eq $vCenter -and $_.IsConnected }

if (-not $currentSession) {
    Write-Host "`n--- vCenter Login ($vCenter) ---" -ForegroundColor Yellow
    
    # 1. Ask for Username
    $vcUser = Read-Host "Enter Username (Press Enter for 'administrator@vsphere.local')"
    if (-not $vcUser) { $vcUser = "administrator@vsphere.local" }

    # 2. Ask for Password securely in the console
    $vcPass = Read-Host "Enter Password for $vcUser" -AsSecureString
    
    # 3. Create the credential object manually
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

# --- 2. UAG Guest Credentials ---
$guestUser = "root"
if (-not $guestPassword) {
    Write-Host "`n--- UAG Guest Login ---" -ForegroundColor Yellow
    $securePassword = Read-Host "Enter UAG root password" -AsSecureString
    $guestPassword = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword)
    )
}

# --- 3. Get VM & Check Health ---
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

# --- 4. Execution Logic ---
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
