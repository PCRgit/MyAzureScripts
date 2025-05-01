<#
.SYNOPSIS
    Exports all Azure built-in RBAC role definitions to CSV
.DESCRIPTION
    This script retrieves all built-in role definitions across all subscriptions,
    extracts their permissions, and exports to a CSV file.
.NOTES
    File Name      : Export-AzureBuiltInRoles.ps1
    Prerequisites  : Azure PowerShell module (Az), authenticated session
#>

# Initialize variables
$outputPath = "$env:USERPROFILE\Downloads\AzureBuiltInRoles_Export_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
$allRoles = @()

# Connect to Azure if not already connected
if (-not (Get-AzContext)) {
    Connect-AzAccount
}

# Get all built-in role definitions (where IsCustom = false)
$roles = Get-AzRoleDefinition | Where-Object { $_.IsCustom -eq $false }

foreach ($role in $roles) {
    # Process Actions
    $actions = if ($role.Actions) { $role.Actions -join "`n" } else { "N/A" }
    $notActions = if ($role.NotActions) { $role.NotActions -join "`n" } else { "N/A" }
    $dataActions = if ($role.DataActions) { $role.DataActions -join "`n" } else { "N/A" }
    $notDataActions = if ($role.NotDataActions) { $role.NotDataActions -join "`n" } else { "N/A" }
    
    # Create custom object with role details
    $roleDetails = [PSCustomObject]@{
        RoleName            = $role.Name
        RoleId             = $role.Id
        Description        = $role.Description
        AssignableScopes   = ($role.AssignableScopes -join "`n")
        Actions           = $actions
        NotActions        = $notActions
        DataActions      = $dataActions
        NotDataActions   = $notDataActions
        CreatedOn        = $role.CreatedOn
        UpdatedOn        = if ($role.UpdatedOn) { $role.UpdatedOn } else { "N/A" }
        IsCustom         = $role.IsCustom
    }

    $allRoles += $roleDetails
}

# Export to CSV
$allRoles | Sort-Object RoleName | Export-Csv -Path $outputPath -NoTypeInformation -Encoding UTF8

Write-Host "`nBuilt-in RBAC roles exported to: $outputPath" -ForegroundColor Green
Write-Host "Total roles found: $($allRoles.Count)" -ForegroundColor Green

# Open the output folder
Invoke-Item -Path (Split-Path -Path $outputPath -Parent)