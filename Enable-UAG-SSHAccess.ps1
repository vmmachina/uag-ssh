param(
    [string]$vCenter,
    [string]$vmName,
    [string]$guestPassword
)

# --- 0. Pre-requisites ---
# Ignore invalid SSL certificates
Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false -Scope Session | Out-Null

# --- 1. vCenter Authentication ---
if (-not $vCenter) {
    $vCenter = Read-Host "Enter vCenter hostname/IP"
}

# Check if already connected
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

# --- 2. Target VM Selection (FIXED) ---
# This was missing in the previous version!
if (-not $vmName) {
    $vmName = Read-Host "`nEnter UAG VM Name"
}

# --- 3. UAG Guest Credentials ---
$guestUser = "root"
if (-not $guestPassword) {
    Write-Host "`n--- UAG Guest Login ---" -ForegroundColor Yellow
    $securePassword = Read-Host "Enter UAG root password" -AsSecureString
    $guestPassword = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword)
