# Optimize-WindowsDisk

A safe, transparent PowerShell tool for freeing up disk space on Windows — and, just as importantly, for **understanding where your space actually went** before you delete anything.

It's built around a simple truth most "PC cleaner" apps ignore: on a nearly-full drive, temp-file junk is usually a rounding error. The real space is sitting in a handful of large files and folders you forgot about. So this tool measures first, cleans the safe stuff automatically, and helps you find and remove the big stuff yourself — with confirmations and a Recycle Bin safety net.

## Why this exists

This started as a real cleanup of a 237 GB drive that was down to 18 GB free. Running a standard junk cleanup recovered only ~1.4 GB. The drive wasn't full of junk — it was full of *stuff*: duplicate project folders, forgotten virtual machine disk images, and app caches. Finding and clearing those recovered **~65 GB**.

The lesson baked into this script: **diagnose before you delete.**

## The methodology

The tool follows the same five-step process that actually worked, in order:

1. **Measure.** Check how much space is free vs. total. This tells you how much you need to recover.
2. **Clean the safe junk.** Empty well-known throwaway locations — temp folders, thumbnail cache, the Windows Update download cache, and the Recycle Bin. This is always safe and fully automatic.
3. **Analyze.** Scan the drive and list the biggest folders and the largest individual files. This is **read-only** — it deletes nothing. It's how you find the real culprits (large media, VM disks, duplicate folders, bloated caches).
4. **Remove the big stuff, deliberately.** Delete specific folders you've identified — one at a time, with a size preview, a typed confirmation, and (where possible) a move to the Recycle Bin instead of a permanent delete.
5. **Reclaim system files.** Optionally turn off hibernation to delete `hiberfil.sys` for a few extra gigabytes.

## Features

| Menu option | What it does | Safety |
|---|---|---|
| Show free space | Reports free / total on the target drive | Read-only |
| Clean junk files | Clears user temp, Windows temp, thumbnail cache, Windows Update cache; empties Recycle Bin | Automatic, only touches known junk |
| Analyze disk | Lists top-level folders by size and the 25 largest files | Read-only, deletes nothing |
| Delete a folder | Deletes a folder you specify, after a size preview and a typed `YES` | Sent to Recycle Bin when possible |
| Turn off hibernation | Runs `powercfg /hibernate off` to remove `hiberfil.sys` | Requires confirmation; reversible |

## Requirements

- Windows 10 or 11
- Windows PowerShell 5.1 (built in) or PowerShell 7+
- **Administrator** rights for a few actions (Windows temp, Windows Update cache, hibernation). Without admin, those steps are simply skipped — the rest still runs.

## Usage

1. Download `Optimize-WindowsDisk.ps1`.
2. Open PowerShell — as **Administrator** for the full feature set (right-click Start → *Windows PowerShell (Admin)* / *Terminal (Admin)*).
3. If scripts are blocked, allow them for this one session only:

   ```powershell
   Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
   ```

4. Run it:

   ```powershell
   .\Optimize-WindowsDisk.ps1
   ```

5. Work through the menu. A typical first run is: **1** (measure) → **2** (clean junk) → **3** (analyze) → **4** (delete what you found).

To target a drive other than C:

```powershell
.\Optimize-WindowsDisk.ps1 -Drive D
```

## What it does NOT do (by design)

Some things are better handled by their own applications, and doing them with a blunt script can leave software in a broken state. This tool deliberately leaves these to you:

- **Virtual machines (VirtualBox / VMware / Hyper-V).** VM disk images are often the single biggest space users, but deleting the `.vdi` / `.vhdx` files directly can leave the hypervisor pointing at missing disks. Remove VMs from inside the hypervisor's manager (e.g. VirtualBox → right-click VM → *Remove* → *Delete all files*), then uninstall the app if you're done with it.
- **Docker / WSL disks.** The `ext4.vhdx` behind Docker can balloon to tens of GB. Reclaim it with `docker system prune -a` while Docker is running, rather than deleting the file.
- **Windows.old / update backups.** Use the built-in **Disk Cleanup** (`cleanmgr`) → *Clean up system files* to remove previous Windows installations safely.

The analyzer (option 3) will *point you at* these so you know they exist — it just won't delete them for you.

## Safety notes

- Destructive actions require typing a confirmation word; nothing dangerous happens silently.
- Folder deletion goes to the **Recycle Bin** when possible. Note that Windows may permanently delete folders too large for the bin — the script warns you when that applies.
- The junk cleanup only ever clears the **contents** of temp/cache locations. It does not touch Documents, Desktop, Downloads, or installed programs.
- Always glance at the analyzer output before deleting, and make sure any "original" you're keeping is intact before removing duplicates.

## A worked example

On the drive this was built from:

| Step | Action | Recovered |
|---|---|---|
| Junk cleanup | temp, cache, update files, recycle bin | ~1.4 GB |
| Delete duplicates | two redundant copies of a project folder | ~22 GB |
| Remove VMs | three unused VirtualBox disk images | ~54 GB |
| **Total** | from 18 GB free to 83 GB free | **~65 GB** |

The junk cleanup alone would have been a disappointment. The analysis is what made the real difference.

## License

MIT — free to use, modify, and share. Provided as-is, with no warranty. You are responsible for what you delete on your own machine; when in doubt, run the analyzer and read before you remove.

## Contributing

Issues and pull requests welcome. Ideas that fit the spirit of the tool: safer detection of app caches, an optional CSV export of the analysis, or per-user-folder drill-down.
