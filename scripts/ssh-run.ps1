# Run a command on the project's VPS over SSH, or upload a file to it.
#
#   ./scripts/ssh-run.ps1 "docker compose ps"
#   ./scripts/ssh-run.ps1 -Upload .\dist.tar.gz -Remote /tmp/dist.tar.gz
#
# Exists so the Claude Code permission rule can match one stable command
# prefix ("PowerShell(./scripts/ssh-run.ps1*)") instead of a different inline
# plink invocation every time - and so the password never appears in a command
# line, in the transcript, or in shell history: it is read from a file that is
# git-ignored.
#
# Upload streams the file over the same SSH connection (`cat > remote`), so it
# needs no scp/pscp and no second permission rule.
#
# Set SSH_HOST / SSH_USER / SSH_PWFILE to point at a different machine.

[CmdletBinding(DefaultParameterSetName = 'Run')]
param(
    [Parameter(ParameterSetName = 'Run', Mandatory = $true, Position = 0, ValueFromRemainingArguments = $true)]
    [string[]] $Command,

    [Parameter(ParameterSetName = 'Upload', Mandatory = $true)]
    [string] $Upload,

    [Parameter(ParameterSetName = 'Upload', Mandatory = $true)]
    [string] $Remote
)

$ErrorActionPreference = 'Stop'

$sshHost = if ($env:SSH_HOST) { $env:SSH_HOST } else { '185.97.144.179' }
$sshUser = if ($env:SSH_USER) { $env:SSH_USER } else { 'root' }
$pwFile  = if ($env:SSH_PWFILE) { $env:SSH_PWFILE } else { 'D:\Courses\ai-regulation-rag\back-end\.secrets\vps-password.txt' }

$plink = 'C:\Program Files\PuTTY\plink.exe'
if (-not (Test-Path $plink)) {
    throw "plink not found at $plink - install PuTTY, or switch this script to ssh with key auth."
}
if (-not (Test-Path $pwFile)) {
    throw "Password file not found at $pwFile. Create it (one line, no trailing newline) or set SSH_PWFILE."
}

if ($PSCmdlet.ParameterSetName -eq 'Upload') {
    if (-not (Test-Path $Upload)) { throw "No such file: $Upload" }
    $source = (Resolve-Path $Upload).Path
    # Binary-safe: raw bytes in, `cat` writes them out on the far side. Routed
    # through cmd.exe because PowerShell's pipeline re-encodes binary data.
    cmd /c "`"$plink`" -ssh $sshUser@$sshHost -pwfile `"$pwFile`" -batch `"cat > '$Remote'`" < `"$source`""
    exit $LASTEXITCODE
}

# Accept the host key on first connect, then run the command.
'y' | & $plink -ssh "$sshUser@$sshHost" -pwfile $pwFile ($Command -join ' ')
exit $LASTEXITCODE
