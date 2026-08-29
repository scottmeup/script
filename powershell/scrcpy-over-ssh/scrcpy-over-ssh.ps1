# Inputs:
# - SSH_EXE, SCRCPY_EXE
# - SSH_HOST, SSH_PORT, SSH_USER
# - LOCAL_ADB_PORT, REMOTE_ADB_HOST, REMOTE_ADB_PORT
# - LOCAL_SCRCPY_PORT, REMOTE_SCRCPY_HOST, REMOTE_SCRCPY_PORT
# Outputs:
# - SSH tunnel, scrcpy session
#
# Requires SSH forwarding enabled on remote SSH server
# /etc/ssh/sshd_config
#
# AllowAgentForwarding yes
# AllowTcpForwarding yes
# ListenAddress 0.0.0.0 # or the specific IP address to listen on

$SSH_EXE = 'C:\Windows\System32\OpenSSH\ssh.exe'
$SCRCPY_EXE = 'C:\utils\scrcpy\scrcpy.exe'

$SSH_HOST = 'foo'
$SSH_PORT = 2222
$SSH_USER = 'bar'

$LOCAL_ADB_PORT = 5038
$REMOTE_ADB_HOST = 'localhost'
$REMOTE_ADB_PORT = 5037

$LOCAL_SCRCPY_PORT = 27183
$REMOTE_SCRCPY_HOST = 'localhost'
$REMOTE_SCRCPY_PORT = 27183

Get-NetTCPConnection -LocalPort $LOCAL_ADB_PORT -ErrorAction SilentlyContinue |
 Select-Object -ExpandProperty OwningProcess -Unique |
 ForEach-Object {
  try {
   $p=Get-Process -Id $_ -ErrorAction Stop
   if($p.ProcessName -eq 'adb'){ Stop-Process -Id $_ -Force }
  } catch {}
 }

$sshArgs = @(
 '-N',
 '-L', "$LOCAL_ADB_PORT`:$REMOTE_ADB_HOST`:$REMOTE_ADB_PORT",
 '-L', "$LOCAL_SCRCPY_PORT`:$REMOTE_SCRCPY_HOST`:$REMOTE_SCRCPY_PORT",
 "$SSH_USER@$SSH_HOST",
 '-p', "$SSH_PORT"
)

$sshProcess=Start-Process -FilePath $SSH_EXE -ArgumentList $sshArgs -PassThru -WindowStyle Hidden
Start-Sleep -Seconds 2

$env:ADB_SERVER_SOCKET = "tcp:localhost:$LOCAL_ADB_PORT"
& adb.exe -H localhost -P $LOCAL_ADB_PORT start-server | Out-Null
& $SCRCPY_EXE '--force-adb-forward'

if($sshProcess -and -not $sshProcess.HasExited){ Stop-Process -Id $sshProcess.Id -Force }
