# SecureFramework (DPAPI)

> Secure, minimal, **RMM-friendly** PowerShell framework + setter to download and execute scripts from a **private GitHub repo** using a **read-only PAT**, with secrets stored locally via **Windows DPAPI** (machine + per-user). No vaults. No env vars.

---

## What’s in this repo?

- **`Framework.ps1`** – The runner. Must be launched **as SYSTEM**.  
  - Set $originalScriptLocation = "URL to the script. Ex: https://github.com/ByteSizedITGuy/TheFramework/edit/main/script_name.ps1" either in your RMM's script/job, or at runtime.
  - Default: runs payload **as SYSTEM** using the **machine** secret.  
  - Optional: set `$runasuser = 'yes'` to launch the payload **as the logged-in user** using a **per-user** secret (seeded automatically from the machine secret).

- **`Setter.ps1`** – One-time machine secret installer. Must be launched **as SYSTEM**.  
  - Stores the PAT as `C:\ProgramData\SecureStore\Secrets\GITHUB_PAT.bin` (DPAPI: LocalMachine) with tight ACLs.

---

## Security model (in 60 seconds)

- **Machine secret**: DPAPI **LocalMachine**, stored under `C:\ProgramData\SecureStore\Secrets\GITHUB_PAT.bin`. Folder ACL: **Administrators + SYSTEM** only (no inheritance).  
- **User secret**: DPAPI **CurrentUser**, stored under `%APPDATA%\SecureStore\Secrets\GITHUB_PAT.bin`. Auto-seeded **by Framework** when `$runasuser = 'yes'` and an interactive user is present.  
- **No** secrets in environment variables or logs. **No** PATs on the command line.  
- DPAPI type loader included to survive minimal runspaces.

> You are solely responsible for any payload you execute with the Framework. See the disclaimer below.

---

## 1) Prepare your **private GitHub repo** + read-only PAT

### A. Make (or choose) a PRIVATE repo
- Put your **payload scripts** in that private repo.  
- Each script you want to run must have a **RAW** URL (e.g., from the “Raw” button on GitHub).

### B. Create a **read-only** token (fine-grained PAT is recommended)
- Go to **GitHub → Settings → Developer settings → Fine-grained personal access tokens**.
- Create a token **scoped to only the target repo(s)**.
- Permissions:
  - **Repository permissions → Contents: Read** (only).
- Save the token securely (you’ll inject it into the Setter via your RMM/automation).

> If you must use a classic PAT, the minimal scope is `repo` (broad). Prefer fine-grained PATs for least privilege.

---

## 2) Install the machine secret (run **Setter.ps1** as SYSTEM)

**Parameters (plaintext flags; injected by your RMM):**
- `$GitHubPAT` – **Required**. Your fine-grained read-only token.
- `$force_update` – `"yes"` to overwrite existing secret; default `"no"`.
- `$clear_variable` – `"yes"` to delete stored secret; default `"no"`.

**Example (pseudocode in RMM):**
```powershell
# SYSTEM context
$GitHubPAT = '<YOUR_FINE_GRAINED_PAT>'
$force_update = 'yes'        # only when rotating
$clear_variable = 'no'
.\Setter.ps1
```

Expected result:
- Secret written to `C:\ProgramData\SecureStore\Secrets\GITHUB_PAT.bin` (DPAPI LocalMachine).
- Folder ACL: Admins + SYSTEM only.

---

## 3) Run your payload with **Framework.ps1** (SYSTEM only)

### A. Common variables to set per job
Inside `Framework.ps1`, set:
```powershell
$RemoteScriptUrl = "https://raw.githubusercontent.com/<org>/<repo>/<branch>/path/to/payload.ps1"
$originalScriptLocation = "https://github.com/<org>/<repo>/blob/<branch>/path/to/payload.ps1" # optional
# Optional flag:
$runasuser = 'no'  # default; set to 'yes' to run payload as logged-in user
```

### B. Run **as SYSTEM** (normal case)
- The Framework uses the **machine** secret and executes the payload as SYSTEM.

### C. Run **as logged-in user** (when needed)
- Set `$runasuser = 'yes'` **and** still launch the Framework **as SYSTEM**.
- The Framework:
  1. Seeds a per-user secret from the machine secret (only if missing).
  2. Creates a one-shot scheduled task to run a tiny bootstrap **as the user**, which:
     - decrypts the per-user secret with DPAPI **CurrentUser**,
     - downloads the payload using the PAT,
     - executes it in the user session.

> If no interactive user is logged in and `$runasuser='yes'`, the Framework fails with a clear error.

---

## 4) Testing quickly

**Test payload** in your private repo (`payloads/Test-WhoAmI.ps1`):
```powershell
Write-Host "Payload ran as: $env:USERNAME"
```

Set in Framework:
```powershell
$RemoteScriptUrl = "https://raw.githubusercontent.com/<org>/<repo>/<branch>/payloads/Test-WhoAmI.ps1"
$runasuser = 'no'  # expect SYSTEM
# run as SYSTEM → expect "Payload ran as: SYSTEM"

$runasuser = 'yes' # expect logged-in user
# run as SYSTEM again → expect "Payload ran as: <logged-in-user>"
```

---

## 5) Rotation & removal

- **Rotate**: re-run **Setter.ps1** with a new PAT and `$force_update = 'yes'`.  
- **Remove**: run **Setter.ps1** with `$clear_variable = 'yes'` to delete the machine secret.  
- **Per-user** secrets are created on demand (when `$runasuser='yes'`). To purge those, remove `%APPDATA%\SecureStore\Secrets\GITHUB_PAT.bin` for each user.

---

## 6) Troubleshooting

- **“DPAPI types unavailable”**: Your host/runspace didn’t auto-load `System.Security`. Both scripts include a loader, but constrained environments may still block `Add-Type`. Check:
  - `$PSVersionTable.PSVersion`
  - `$ExecutionContext.SessionState.LanguageMode` (should not be `ConstrainedLanguage`).
- **“Framework must be run as SYSTEM”**: That’s by design. Always run Framework as SYSTEM. Use `$runasuser = 'yes'` for user-context payloads.
- **“runasuser='yes' but no interactive user”**: Ensure someone is actually logged in (console/RDP) when you trigger the job.
- **“No stored PAT found for user or machine”**: Run **Setter.ps1** as SYSTEM first; confirm the file exists at `C:\ProgramData\SecureStore\Secrets\GITHUB_PAT.bin`.

---

## 7) Design choices

- **DPAPI over env vars/secrets managers**: avoids vault dependencies and keeps secret material local to the endpoint, bound to machine/user keys.  
- **Fine-grained PAT**: least privilege; repo-scoped; **Contents: Read** only.  
- **No PATs on CLI**: All secret use is in-memory headers; headers are nulled after use.  
- **Tight ACLs**: Secret files are readable only by Admins/SYSTEM. Per-user blobs live under the user’s `%APPDATA%`.

---

## 8) Example RMM usage (pseudo)

**Job 1 — Install secret (once per device)**
```powershell
# Run as SYSTEM
$GitHubPAT = '<fine-grained-readonly-token>'
$force_update = 'no'
$clear_variable = 'no'
powershell -ExecutionPolicy Bypass -File .\Setter.ps1
```

**Job 2 — Run payload (SYSTEM)**
```powershell
# Run as SYSTEM
# Edit Framework.ps1: set $RemoteScriptUrl to your raw payload URL; leave $runasuser='no'
powershell -ExecutionPolicy Bypass -File .\Framework.ps1
```

**Job 3 — Run payload (as user)**
```powershell
# Run as SYSTEM
# Edit Framework.ps1: set $RemoteScriptUrl; set $runasuser='yes'
powershell -ExecutionPolicy Bypass -File .\Framework.ps1
```

---

## License & responsibility

```
Secure Framework and Setter Scripts
Copyright (C) 2025 ROI Technology Inc. and contributors
Licensed under GPLv3: https://www.gnu.org/licenses/gpl-3.0.html

USE AT YOUR OWN RISK:
These scripts are provided as-is.
You are solely responsible for how you use them, including any
payloads you deploy with the Framework. By using these scripts,
you accept full responsibility for any outcomes, intended or not.
No warranty is expressed or implied.
```

