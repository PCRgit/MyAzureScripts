<#
.SYNOPSIS
    Lists all Azure resources the current user has access to across all subscriptions.
.DESCRIPTION
    This script connects to Azure, enumerates all accessible subscriptions,
    and lists every resource the user can access with resource group information.
.NOTES
    File Name      : Get-AzureUserAccessibleResources.ps1
    Prerequisites  : Az PowerShell module
    Version        : 1.1
#>

#Requires -Module Az.Accounts
#Requires -Module Az.Resources

function Connect-AzAccountAllSubscriptions {
    try {
        Write-Host "Connecting to Azure..."
        Connect-AzAccount -ErrorAction Stop
        Write-Host "Successfully connected to Azure." -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to connect to Azure: $_"
        exit
    }
}

function Get-AllAccessibleResources {
    [CmdletBinding()]
    param()

    # Get all accessible subscriptions
    $allSubscriptions = Get-AzSubscription -ErrorAction SilentlyContinue
    
    if (-not $allSubscriptions) {
        Write-Error "No subscriptions found or you don't have access to any subscriptions."
        return
    }

    $results = @()
    $totalSubscriptions = $allSubscriptions.Count
    $processed = 0

    foreach ($sub in $allSubscriptions) {
        $processed++
        Write-Progress -Activity "Processing subscriptions" -Status "$processed of $totalSubscriptions" -PercentComplete (($processed / $totalSubscriptions) * 100)
        
        try {
            Write-Host "Checking subscription: $($sub.Name) ($($sub.Id))" -ForegroundColor Cyan
            Set-AzContext -SubscriptionId $sub.Id -ErrorAction Stop | Out-Null

            # Get all resource groups in the subscription
            $resourceGroups = Get-AzResourceGroup -ErrorAction SilentlyContinue
            
            if (-not $resourceGroups) {
                Write-Host "  No resource groups found or no access to resource groups in this subscription." -ForegroundColor Yellow
                continue
            }

            foreach ($rg in $resourceGroups) {
                try {
                    # Get all resources in each resource group
                    $resources = Get-AzResource -ResourceGroupName $rg.ResourceGroupName -ErrorAction SilentlyContinue
                    
                    if ($resources) {
                        foreach ($resource in $resources) {
                            $results += [PSCustomObject]@{
                                SubscriptionName = $sub.Name
                                SubscriptionId = $sub.Id
                                ResourceGroupName = $rg.ResourceGroupName
                                ResourceName = $resource.Name
                                ResourceType = $resource.Type
                                Location = $resource.Location
                                ResourceId = $resource.ResourceId
                            }
                        }
                    }
                }
                catch {
                    Write-Warning "  Error processing resource group $($rg.ResourceGroupName): $_"
                }
            }
        }
        catch {
            Write-Warning "Error processing subscription $($sub.Name): $_"
            continue
        }
    }

    return $results
}

# Main execution
Connect-AzAccountAllSubscriptions

$output = Get-AllAccessibleResources

if ($output) {
    # Export to CSV
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $outputFile = "AzureAccessibleResources_$timestamp.csv"
    $output | Export-Csv -Path $outputFile -NoTypeInformation -Encoding UTF8

    # Display summary
    Write-Host "`nFound $($output.Count) accessible resources across $((Get-AzSubscription).Count) subscriptions." -ForegroundColor Green
    Write-Host "Results exported to: $((Get-Item $outputFile).FullName)" -ForegroundColor Cyan

    # Show sample output
    Write-Host "`nSample of accessible resources:" -ForegroundColor Yellow
    $output | Select-Object -First 10 | Format-Table -AutoSize SubscriptionName, ResourceGroupName, ResourceName, ResourceType
}
else {
    Write-Host "No accessible resources found." -ForegroundColor Yellow
}