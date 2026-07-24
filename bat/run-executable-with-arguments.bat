# 2>NUL & @CLS & PUSHD "%~dp0" & "%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -nol -nop -ep bypass "[IO.File]::ReadAllText('%~f0')|iex" & POPD & EXIT /B

# Runs an executable, asking the user for files to pass to the executable as arguments

# Import the necessary namespaces for the File Open Dialog
Add-Type -AssemblyName "System.Windows.Forms"

# Open a dialogue window to select one or multiple files
$openFileDialog = New-Object System.Windows.Forms.OpenFileDialog
$openFileDialog.Filter = "All Files (*.*)|*.*"  # Filter can be adjusted for specific types
$openFileDialog.Multiselect = $true  # Allow multiple file selection
$openFileDialog.Title = "Select Files"

# Show the dialog and check if the user selects files
if ($openFileDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
    # Get the selected file paths
    $selectedFiles = $openFileDialog.FileNames

    # Set the executable path
    $exePath = "C:\apps\glslviewer\bin\glslViewer.exe"

    # Create a string with the executable and the selected files as arguments
    $arguments = $selectedFiles -join " "

    # Run the executable with the selected files as arguments
    Start-Process -FilePath $exePath -ArgumentList $arguments
} else {
    Start-Process -FilePath $exePath
}