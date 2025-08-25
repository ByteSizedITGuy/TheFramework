# The Framework (DPAPI)

> Secure, minimal, **RMM-friendly** PowerShell framework + setter to download and execute scripts from a **private GitHub repo** using a **read-only PAT**, with secrets stored locally via **Windows DPAPI** (machine + per-user). No vaults. No env vars.

---

## What’s in this repo?

- **`Framework.ps1`** – The runner. Must be launched **as SYSTEM**.  
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
