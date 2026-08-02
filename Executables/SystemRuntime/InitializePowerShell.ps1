$windir = [Environment]::GetFolderPath('Windows')

# Add the playbook's local PowerShell modules
$env:PSModulePath += ";$windir\SystemRuntime\Scripts\Modules"
