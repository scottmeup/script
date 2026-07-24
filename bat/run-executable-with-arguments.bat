# 2>NUL & @CLS & SETLOCAL DisableDelayedExpansion & PUSHD "%~dp0" & SET "__SELF=%~f0" & "%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -nol -nop -ep bypass "[IO.File]::ReadAllText($env:__SELF)|iex" & POPD & ENDLOCAL & EXIT /B

# Runs an executable, asking the user for files to pass to the executable as arguments

# Set the executable path
$exePath = "C:\apps\glslviewer\bin\glslViewer.exe"

# Import the necessary namespaces for the File Open Dialog
Add-Type -AssemblyName "System.Windows.Forms"

# Open a dialogue window to select one or multiple files
$openFileDialog = New-Object System.Windows.Forms.OpenFileDialog
$openFileDialog.Filter = "All Files (*.*)|*.*"  # Filter can be adjusted for specific types
$openFileDialog.Multiselect = $true  # Allow multiple file selection
$openFileDialog.Title = "Select Files"


# Show the dialog and check if the user selects files
if ($openFileDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
    $selectedFiles = $openFileDialog.FileNames

    # Quote each complete path so whitespace and other valid filename characters remain part of one argument.
    $arguments = $selectedFiles | ForEach-Object { '"' + $_ + '"' }

    # Run the executable with the selected files as separate quoted arguments.
    Start-Process -FilePath $exePath -ArgumentList $arguments
} else {
    Start-Process -FilePath $exePath
}