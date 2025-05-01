<#
.SYNOPSIS
    Exports Microsoft 365 and Entra ID role names with YOUR_GROUP_ prefix to CSV.
.DESCRIPTION
    This script enumerates all available M365 and Entra ID roles and exports the proposed
    group names (with YOUR_GROUP_ prefix) to a CSV file without creating any groups.
.NOTES
    File Name      : Export-RoleNames.ps1
    Prerequisites  : Microsoft Graph PowerShell module
    Version        : 1.0
#>

#Requires -Module Microsoft.Graph.Identity.DirectoryManagement
#Requires -Module Microsoft.Graph.Identity.Governance

# Connect to Microsoft Graph with required permissions
function Connect-MgGraphWithPermissions {
    try {
        Write-Host "Connecting to Microsoft Graph..."
        Connect-MgGraph -Scopes "Directory.Read.All, RoleManagement.Read.Directory" -ErrorAction Stop
        Write-Host "Successfully connected to Microsoft Graph." -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to connect to Microsoft Graph: $_"
        exit
    }
}

# Get all directory roles (Entra ID roles)
function Get-DirectoryRoles {
    try {
        Write-Host "Retrieving directory roles..."
        $directoryRoles = Get-MgDirectoryRole -All -ErrorAction Stop
        Write-Host "Found $($directoryRoles.Count) directory roles." -ForegroundColor Green
        return $directoryRoles
    }
    catch {
        Write-Error "Failed to retrieve directory roles: $_"
        return $null
    }
}

# Get all privileged roles (M365 roles)
function Get-PrivilegedRoles {
    try {
        Write-Host "Retrieving privileged roles..."
        $privilegedRoles = Get-MgRoleManagementDirectoryRoleDefinition -All -ErrorAction Stop
        Write-Host "Found $($privilegedRoles.Count) privileged roles." -ForegroundColor Green
        return $privilegedRoles
    }
    catch {
        Write-Error "Failed to retrieve privileged roles: $_"
        return $null
    }
}

# Main script execution
Connect-MgGraphWithPermissions

# Prepare CSV output
$output = @()
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$outputFile = "TennCare_RoleNames_$timestamp.csv"

# Process directory roles (Entra ID)
$directoryRoles = Get-DirectoryRoles
if ($directoryRoles) {
    Write-Host "Processing directory roles..."
    foreach ($role in $directoryRoles) {
        $output += [PSCustomObject]@{
            "RoleType" = "Entra ID Role"
            "OriginalRoleName" = $role.DisplayName
            "ProposedGroupName" = "YOUR_GROUP_$($role.DisplayName.Replace(' ', '_'))"
            "Description" = "Group for assigning the $($role.DisplayName) directory role"
        }
    }
}

# Process privileged roles (M365)
$privilegedRoles = Get-PrivilegedRoles
if ($privilegedRoles) {
    Write-Host "Processing privileged roles..."
    foreach ($role in $privilegedRoles) {
        $output += [PSCustomObject]@{
            "RoleType" = "M365 Role"
            "OriginalRoleName" = $role.DisplayName
            "ProposedGroupName" = "YOUR_GROUP_$($role.DisplayName.Replace(' ', '_'))"
            "Description" = "Group for assigning the $($role.DisplayName) privileged role"
        }
    }
}

# Export to CSV
try {
    $output | Export-Csv -Path $outputFile -NoTypeInformation -Encoding UTF8
    Write-Host "Successfully exported $($output.Count) role names to $outputFile" -ForegroundColor Green
    Write-Host "Location: $((Get-Item $outputFile).FullName)" -ForegroundColor Cyan
}
catch {
    Write-Error "Failed to export CSV: $_"
}

# Display sample output
if ($output.Count -gt 0) {
    Write-Host "`nSample of exported data:" -ForegroundColor Yellow
    $output | Select-Object -First 5 | Format-Table -AutoSize
}