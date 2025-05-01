<#
.SYNOPSIS
    Creates security groups for each Microsoft 365 and Entra ID role with TennCare_DS_TCAP_ prefix.
.DESCRIPTION
    This script enumerates all available M365 and Entra ID roles and creates corresponding security groups
    with the naming convention TennCare_DS_TCAP_[RoleName]. The groups can then be used for role assignments.
.NOTES
    File Name      : Create-RoleGroups.ps1
    Prerequisites  : Microsoft Graph PowerShell module
    Version        : 1.0
#>

#Requires -Module Microsoft.Graph.Identity.DirectoryManagement
#Requires -Module Microsoft.Graph.Identity.Governance

# Connect to Microsoft Graph with required permissions
function Connect-MgGraphWithPermissions {
    try {
        Write-Host "Connecting to Microsoft Graph..."
        Connect-MgGraph -Scopes "Directory.Read.All, RoleManagement.Read.Directory, Group.ReadWrite.All" -ErrorAction Stop
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

# Create a security group for a role
function New-RoleGroup {
    param (
        [string]$roleName,
        [string]$description
    )
    
    $groupName = "TennCare_DS_TCAP_$($roleName.Replace(' ', '_'))"
    $mailNickname = $groupName.Replace(' ', '').Replace('_', '').Substring(0, [Math]::Min($groupName.Length, 64))
    
    try {
        # Check if group already exists
        $existingGroup = Get-MgGroup -Filter "displayName eq '$groupName'" -ErrorAction SilentlyContinue
        
        if ($existingGroup) {
            Write-Host "Group '$groupName' already exists. Skipping creation." -ForegroundColor Yellow
            return $existingGroup
        }
        
        Write-Host "Creating group '$groupName'..."
        $newGroup = New-MgGroup -DisplayName $groupName `
                                -Description $description `
                                -MailEnabled:$false `
                                -SecurityEnabled:$true `
                                -MailNickname $mailNickname `
                                -ErrorAction Stop
        
        Write-Host "Successfully created group '$groupName'" -ForegroundColor Green
        return $newGroup
    }
    catch {
        Write-Error "Failed to create group '$groupName': $_"
        return $null
    }
}

# Main script execution
Connect-MgGraphWithPermissions

# Create groups for directory roles (Entra ID)
$directoryRoles = Get-DirectoryRoles
if ($directoryRoles) {
    Write-Host "Creating groups for directory roles..."
    foreach ($role in $directoryRoles) {
        $description = "Group for assigning the $($role.DisplayName) directory role"
        $null = New-RoleGroup -roleName $role.DisplayName -description $description
    }
}

# Create groups for privileged roles (M365)
$privilegedRoles = Get-PrivilegedRoles
if ($privilegedRoles) {
    Write-Host "Creating groups for privileged roles..."
    foreach ($role in $privilegedRoles) {
        $description = "Group for assigning the $($role.DisplayName) privileged role"
        $null = New-RoleGroup -roleName $role.DisplayName -description $description
    }
}

Write-Host "Group creation process completed." -ForegroundColor Green