<#
.SYNOPSIS
    Creates security groups for each Microsoft 365 license SKU with TennCare_DS_TCAP_ prefix.
.DESCRIPTION
    This script enumerates all available Microsoft 365 license SKUs in the tenant
    and creates corresponding security groups with the naming convention
    TennCare_DS_TCAP_[LicenseName]. These groups can then be used for license assignments.
.NOTES
    File Name      : Create-LicenseGroups.ps1
    Prerequisites  : Microsoft.Graph module
    Version        : 1.0
#>

#Requires -Module Microsoft.Graph.Identity.DirectoryManagement
#Requires -Module Microsoft.Graph.Identity.Governance

# Connect to Microsoft Graph with required permissions
function Connect-MgGraphWithPermissions {
    try {
        Write-Host "Connecting to Microsoft Graph..."
        Connect-MgGraph -Scopes "Directory.Read.All, Organization.Read.All, Group.ReadWrite.All" -ErrorAction Stop
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

# Create a security group for a license SKU
function New-LicenseGroup {
    param (
        [string]$licenseName,
        [string]$skuId,
        [string]$description
    )
    
    # Format group name according to requirements
    $groupName = "TennCare_DS_TCAP_$($licenseName.Replace(' ', '_').Replace('-', '_').Replace('.', ''))"
    $mailNickname = ($groupName -replace '[^a-zA-Z0-9]', '').Substring(0, [Math]::Min(64, ("TennCareDSTCAP$licenseName" -replace '[^a-zA-Z0-9]', '').Length))
    
    try {
        # Check if group already exists
        $existingGroup = Get-MgGroup -Filter "displayName eq '$groupName'" -ErrorAction SilentlyContinue
        
        if ($existingGroup) {
            Write-Host "Group '$groupName' already exists (ID: $($existingGroup.Id)). Skipping creation." -ForegroundColor Yellow
            return $existingGroup
        }
        
        Write-Host "Creating license group '$groupName'..."
        $newGroup = New-MgGroup -DisplayName $groupName `
                                -Description $description `
                                -MailEnabled:$false `
                                -SecurityEnabled:$true `
                                -MailNickname $mailNickname `
                                -ErrorAction Stop
        
        # Add license SKU ID as extension attribute for future reference
        $params = @{
            "@odata.type" = "#microsoft.graph.extensionAttribute"
            extensionAttribute1 = $skuId
        }
        Update-MgGroup -GroupId $newGroup.Id -AdditionalProperties $params -ErrorAction SilentlyContinue
        
        Write-Host "Successfully created group '$groupName' (ID: $($newGroup.Id))" -ForegroundColor Green
        return $newGroup
    }
    catch {
        Write-Error "Failed to create group '$groupName': $_"
        return $null
    }
}

# Main script execution
Connect-MgGraphWithPermissions

# Get all license SKUs
$licenseSKUs = Get-LicenseSKUs
if (-not $licenseSKUs) {
    Write-Error "No license SKUs found or failed to retrieve them."
    exit
}

# Create groups for each license SKU
$results = @()
foreach ($sku in $licenseSKUs) {
    $skuName = $sku.SkuPartNumber
    $description = "Group for assigning $($sku.SkuPartNumber) license (SKU ID: $($sku.SkuId))"
    
    $result = New-LicenseGroup -licenseName $skuName -skuId $sku.SkuId -description $description
    
    if ($result) {
        $results += [PSCustomObject]@{
            "LicenseSKU" = $sku.SkuPartNumber
            "GroupName" = $result.DisplayName
            "GroupId" = $result.Id
            "SKUId" = $sku.SkuId
            "Status" = "Created"
        }
    }
}

# Export results to CSV
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$outputFile = "TennCare_LicenseGroup_Creation_$timestamp.csv"
$results | Export-Csv -Path $outputFile -NoTypeInformation -Encoding UTF8

Write-Host "`nLicense group creation completed. Results exported to $outputFile" -ForegroundColor Green
Write-Host "Total licenses processed: $($licenseSKUs.Count)" -ForegroundColor Cyan
Write-Host "Groups created: $($results.Count)" -ForegroundColor Cyan

# Display summary
$results | Select-Object LicenseSKU, GroupName, Status | Format-Table -AutoSize