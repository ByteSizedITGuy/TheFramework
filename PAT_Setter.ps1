Import-Module $env:SyncroModule

<#
.SYNOPSIS
  Store a GitHub PAT securely on the endpoint using DPAPI (LocalMachine).

.DESCRIPTION
  - Encrypts the PAT with DPAPI LocalMachine and writes to C:\ProgramData\SecureStore\Secrets\GITHUB_PAT.bin
  - Locks the secrets directory to Administrators and SYSTEM only (no inheritance).
  - Supports plaintext flags: force_update ("yes"/"no") and clear_variable ("yes"/"no").
  - Does NOT seed a per-user secret. The Framework will handle per-user seeding when $runasuser = 'yes'.

.REQUIREMENTS
  Must be run as SYSTEM (LocalSystem).

.NOTES
  Version: 1.3-generic
  Revised: 2025-08-25
#>

# ====== INJECTED VARIABLES (examples; your RMM will set real values) ======
if (-not $force_update)   { $force_update   = "no" }
if (-not $clear_variable) { $clear_variable = "no" }
# $GitHubPAT should be injected by your RMM, e.g.:
# $GitHubPAT = "GITHUB_PAT_GOES_HERE"

# ====== CONSTANTS (generic) ======
$SECRET_NAME = 'GITHUB_PAT'
$BASE_DIR    = 'C:\ProgramData\SecureStore\Secrets'
$BLOB_PATH   = Join-Path $BASE_DIR "$SECRET_NAME.bin"
$ENTROPY     = [Text.Encoding]::UTF8.GetBytes("Org-Secret-v1:$SECRET_NAME")
$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'

# ====== HELPERS ======
function Test-IsSystem {
    try {
        $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
        return ($sid -eq 'S-1-5-18') # LocalSystem
    } catch { return $false }
}
function Ensure-DpapiTypes {
    try { $null = [System.Security.Cryptography.ProtectedData]; $null = [System.Security.Cryptography.DataProtectionScope]; return } catch {}
    $loaded = $false
    foreach($asm in 'System.Security','System.Security.Cryptography.ProtectedData','System.Security.Cryptography.Algorithms'){
        try { Add-Type -AssemblyName $asm -ErrorAction Stop; $loaded = $true; break } catch {}
    }
    if(-not $loaded){ try { [Reflection.Assembly]::Load('System.Security') | Out-Null } catch {} }
    try { $null = [System.Security.Cryptography.ProtectedData]; $null = [System.Security.Cryptography.DataProtectionScope] }
    catch { throw "DPAPI types unavailable (ProtectedData/DataProtectionScope)." }
}
function Ensure-SecureFolder {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path $Path)) { New-Item -ItemType Directory -Path $Path -Force | Out-Null }
    # Lock down ACLs: Admins + SYSTEM, no inheritance
    $inherit = [System.Security.AccessControl.InheritanceFlags]"ContainerInherit, ObjectInherit"
    $prop    = [System.Security.AccessControl.PropagationFlags]"None"
    $acl     = New-Object System.Security.AccessControl.DirectorySecurity
    $acl.SetAccessRuleProtection($true, $false)  # disable inheritance
    $acl.AddAccessRule( (New-Object System.Security.AccessControl.FileSystemAccessRule('BUILTIN\Administrators','FullControl',$inherit,$prop,'Allow')) )
    $acl.AddAccessRule( (New-Object System.Security.AccessControl.FileSystemAccessRule('SYSTEM','FullControl',$inherit,$prop,'Allow')) )
    Set-Acl -Path $Path -AclObject $acl
    try { (Get-Item $Path).Attributes = 'Hidden','System' } catch {}
}
function Save-MachineSecret {
    param([Parameter(Mandatory)][string]$Token)
    Ensure-SecureFolder -Path $BASE_DIR
    Ensure-DpapiTypes

    if ((Test-Path $BLOB_PATH) -and ($force_update -ne 'yes')) {
        Write-Host "Machine PAT already exists. Skipping. (Use force_update='yes' to overwrite.)"
        return
    }
    if ([string]::IsNullOrWhiteSpace($Token)) { throw "GitHub PAT is empty or whitespace. Cannot proceed." }

    $bytes = [Text.Encoding]::UTF8.GetBytes($Token)
    $enc   = [System.Security.Cryptography.ProtectedData]::Protect($bytes, $ENTROPY, [System.Security.Cryptography.DataProtectionScope]::LocalMachine)
    [System.IO.File]::WriteAllBytes($BLOB_PATH, $enc)

    $Token=$null; $bytes=$null; $enc=$null
    [GC]::Collect(); [GC]::WaitForPendingFinalizers()
    Write-Host "Saved encrypted machine PAT to $BLOB_PATH"
}

# ====== MAIN ======
if (-not (Test-IsSystem)) {
    Write-Error "This setter must be run as SYSTEM (LocalSystem). It does not seed per-user secrets. The Framework will handle per-user seeding when `$runasuser = 'yes'."
    exit 1
}

if ($clear_variable -eq 'yes') {
    if (Test-Path $BLOB_PATH) { Remove-Item -Path $BLOB_PATH -Force; Write-Host "Cleared machine-scoped PAT at $BLOB_PATH." }
    else { Write-Host "No machine-scoped PAT found to clear." }
    exit 0
}

Save-MachineSecret -Token $GitHubPAT
exit 0
