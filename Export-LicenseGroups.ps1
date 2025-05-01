<#
.SYNOPSIS
    Exports Microsoft 365 license SKUs with proposed TennCare_DS_TCAP_ group names to CSV.
.DESCRIPTION
    This script lists all available Microsoft 365 license SKUs in the tenant
    and exports the proposed group names (with TennCare_DS_TCAP_ prefix) to CSV
    without creating any groups in Azure AD.
.NOTES
    File Name      : Export-LicenseGroups.ps1
    Prerequisites  : Microsoft.Graph module
    Version        : 1.0
#>

#Requires -Module Microsoft.Graph.Identity.DirectoryManagement

# Connect to Microsoft Graph with required permissions
function Connect-MgGraphWithPermissions {
    try {
        Write-Host "Connecting to Microsoft Graph..."
        Connect-MgGraph -Scopes "Directory.Read.All, Organization.Read.All" -ErrorAction Stop
        Write-Host "Successfully connected to Microsoft Graph." -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to connect to Microsoft Graph: $_"
        exit
    }
}

# Get all available license SKUs
function Get-LicenseSKUs {
    try {
        Write-Host "Retrieving available license SKUs..."
        $subscribedSkus = Get-MgSubscribedSku -All -ErrorAction Stop
        Write-Host "Found $($subscribedSkus.Count) license SKUs." -ForegroundColor Green
        return $subscribedSkus
    }
    catch {
        Write-Error "Failed to retrieve license SKUs: $_"
        return $null
    }
}

# Format group name according to naming convention
function Get-FormattedGroupName {
    param (
        [string]$licenseName
    )
    return "TennCare_DS_TCAP_$($licenseName.Replace(' ', '_').Replace('-', '_').Replace('.', ''))"
}

# Main script execution
Connect-MgGraphWithPermissions

# Get all license SKUs
$licenseSKUs = Get-LicenseSKUs
if (-not $licenseSKUs) {
    Write-Error "No license SKUs found or failed to retrieve them."
    exit
}

# Prepare output data
$output = foreach ($sku in $licenseSKUs) {
    [PSCustomObject]@{
        "LicenseSKUName" = $sku.SkuPartNumber
        "ProposedGroupName" = Get-FormattedGroupName -licenseName $sku.SkuPartNumber
        "SKUId" = $sku.SkuId
        "EnabledUnits" = $sku.PrepaidUnits.Enabled
        "ConsumedUnits" = $sku.ConsumedUnits
        "ServicePlans" = ($sku.ServicePlans | ForEach-Object { "$($_.ServicePlanName) ($($_.ServicePlanId))" }) -join "; "
        "Status" = "Not Created"
    }
}

# Export to CSV
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$outputFile = "TennCare_LicenseGroup_Proposals_$timestamp.csv"
$output | Export-Csv -Path $outputFile -NoTypeInformation -Encoding UTF8

Write-Host "`nLicense SKU export completed. Results saved to:" -ForegroundColor Green
Write-Host $outputFile -ForegroundColor Cyan
Write-Host "Total license SKUs found: $($licenseSKUs.Count)" -ForegroundColor Cyan

# Display sample output
if ($output.Count -gt 0) {
    Write-Host "`nSample of exported data:" -ForegroundColor Yellow
    $output | Select-Object -First 5 | Format-Table -AutoSize LicenseSKUName, ProposedGroupName, EnabledUnits, ConsumedUnits
}