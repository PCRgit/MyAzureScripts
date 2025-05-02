<#
.SYNOPSIS
    Finds and updates whitelisted IP addresses across all subscriptions in a tenant
.DESCRIPTION
    This script searches across all subscriptions in your Azure tenant to:
    1. Discover all IP-based restrictions
    2. Allow reviewing current whitelisted IPs
    3. Update IPs across all found resources
.NOTES
    File Name      : Manage-AzureIPWhitelisting.ps1
    Prerequisites  : Azure PowerShell module (Az), authenticated session with tenant-level access
	
.EXAMPLE: 
	powershell.exe -ExecutionPolicy Bypass -File "PATH\Azure-FW-IP-Changer.ps1" -OldIP PUT_YOUR_OLD_IP -NewIP PUT_YOUR_NEW_IP
#>

param(
    [string]$OldIP,
    [string]$NewIP,
    [switch]$PreviewOnly,
    [switch]$SkipConfirmation
)

# Function to normalize IP addresses for comparison
function Normalize-IP {
    param([string]$IP)
    # Handle IP ranges (like SQL Server firewall rules)
    if ($IP -match '^(\d+\.\d+\.\d+\.\d+)-(\d+\.\d+\.\d+\.\d+)$') {
        if ($matches[1] -eq $matches[2]) {
            return $matches[1] # Return single IP if range start/end are same
        }
        return $IP
    }
    # Handle CIDR notation if needed
    return $IP
}

# Initialize variables
$report = [System.Collections.Generic.List[PSObject]]::new()
$ipRulesFound = 0
$subscriptionsProcessed = 0
$changesToMake = 0
$tenantId = (Get-AzContext).Tenant.Id

# Connect to Azure if not already connected
if (-not (Get-AzContext)) {
    Connect-AzAccount -TenantId $tenantId
}

# Get all subscriptions in the tenant
try {
    $subscriptions = Get-AzSubscription -TenantId $tenantId -ErrorAction Stop
    Write-Host "Found $($subscriptions.Count) subscriptions in tenant $tenantId" -ForegroundColor Cyan
}
catch {
    Write-Host "Error getting subscriptions: $($_.Exception.Message)" -ForegroundColor Red
    exit
}

foreach ($sub in $subscriptions) {
    try {
        Set-AzContext -Subscription $sub.Id -TenantId $tenantId -ErrorAction Stop | Out-Null
        Write-Host "`nProcessing subscription: $($sub.Name) ($($sub.Id))" -ForegroundColor Cyan
        $subscriptionsProcessed++

        # 1. App Services/Function Apps
        try {
            $webApps = Get-AzWebApp -ErrorAction Stop
            Write-Host "  Found $($webApps.Count) App Services" -ForegroundColor DarkGray
            foreach ($app in $webApps) {
                try {
                    $ipSec = Get-AzWebAppAccessRestrictionConfig -ResourceGroupName $app.ResourceGroup -Name $app.Name -ErrorAction Stop
                    foreach ($rule in $ipSec.MainSiteAccessRestrictions) {
                        if ($rule.Action -eq "Allow" -and $rule.IpAddress) {
                            $normalizedIP = Normalize-IP $rule.IpAddress
                            $report.Add([PSCustomObject]@{
                                Subscription    = $sub.Name
                                ResourceType   = "App Service"
                                ResourceName   = $app.Name
                                ResourceGroup = $app.ResourceGroup
                                RuleName      = $rule.Name
                                CurrentIP     = $rule.IpAddress
                                NormalizedIP  = $normalizedIP
                                RulePriority  = $rule.Priority
                                RuleAction    = $rule.Action
                            })
                            $ipRulesFound++
                            Write-Host "    Found IP rule: $($rule.IpAddress)" -ForegroundColor DarkGray
                        }
                    }
                }
                catch {
                    Write-Host "    [WARN] Error processing App Service $($app.Name): $($_.Exception.Message)" -ForegroundColor Yellow
                }
            }
        }
        catch {
            Write-Host "  [INFO] No App Services found or access denied" -ForegroundColor DarkGray
        }

        # 2. Storage Accounts
        try {
            $storageAccounts = Get-AzStorageAccount -ErrorAction Stop
            Write-Host "  Found $($storageAccounts.Count) Storage Accounts" -ForegroundColor DarkGray
            foreach ($sa in $storageAccounts) {
                try {
                    $networkRules = (Get-AzStorageAccountNetworkRuleSet -ResourceGroupName $sa.ResourceGroupName -Name $sa.StorageAccountName -ErrorAction Stop).IPRules
                    foreach ($rule in $networkRules) {
                        $normalizedIP = Normalize-IP $rule.IPAddressOrRange
                        $report.Add([PSCustomObject]@{
                            Subscription    = $sub.Name
                            ResourceType   = "Storage Account"
                            ResourceName   = $sa.StorageAccountName
                            ResourceGroup = $sa.ResourceGroupName
                            RuleName      = "IP Rule"
                            CurrentIP     = $rule.IPAddressOrRange
                            NormalizedIP  = $normalizedIP
                            RulePriority  = "N/A"
                            RuleAction    = "Allow"
                        })
                        $ipRulesFound++
                        Write-Host "    Found IP rule: $($rule.IPAddressOrRange)" -ForegroundColor DarkGray
                    }
                }
                catch {
                    Write-Host "    [WARN] Error processing Storage Account $($sa.StorageAccountName): $($_.Exception.Message)" -ForegroundColor Yellow
                }
            }
        }
        catch {
            Write-Host "  [INFO] No Storage Accounts found or access denied" -ForegroundColor DarkGray
        }

        # 3. SQL Servers
        try {
            $sqlServers = Get-AzSqlServer -ErrorAction Stop
            Write-Host "  Found $($sqlServers.Count) SQL Servers" -ForegroundColor DarkGray
            foreach ($server in $sqlServers) {
                try {
                    $firewallRules = Get-AzSqlServerFirewallRule -ResourceGroupName $server.ResourceGroupName -ServerName $server.ServerName -ErrorAction Stop
                    foreach ($rule in $firewallRules) {
                        $ipRange = "$($rule.StartIpAddress)-$($rule.EndIpAddress)"
                        $normalizedIP = Normalize-IP $ipRange
                        $report.Add([PSCustomObject]@{
                            Subscription    = $sub.Name
                            ResourceType   = "SQL Server"
                            ResourceName   = $server.ServerName
                            ResourceGroup = $server.ResourceGroupName
                            RuleName      = $rule.FirewallRuleName
                            CurrentIP     = $ipRange
                            NormalizedIP  = $normalizedIP
                            RulePriority  = "N/A"
                            RuleAction    = "Allow"
                        })
                        $ipRulesFound++
                        Write-Host "    Found IP rule: $ipRange" -ForegroundColor DarkGray
                    }
                }
                catch {
                    Write-Host "    [WARN] Error processing SQL Server $($server.ServerName): $($_.Exception.Message)" -ForegroundColor Yellow
                }
            }
        }
        catch {
            Write-Host "  [INFO] No SQL Servers found or access denied" -ForegroundColor DarkGray
        }

        # 4. Key Vaults
        try {
            $keyVaults = Get-AzKeyVault -ErrorAction Stop
            Write-Host "  Found $($keyVaults.Count) Key Vaults" -ForegroundColor DarkGray
            foreach ($kv in $keyVaults) {
                try {
                    $networkAcls = (Get-AzKeyVault -VaultName $kv.VaultName -ResourceGroupName $kv.ResourceGroupName -ErrorAction Stop).NetworkAcls
                    if ($networkAcls.IpAddressRanges) {
                        foreach ($ipRange in $networkAcls.IpAddressRanges) {
                            $normalizedIP = Normalize-IP $ipRange
                            $report.Add([PSCustomObject]@{
                                Subscription    = $sub.Name
                                ResourceType   = "Key Vault"
                                ResourceName   = $kv.VaultName
                                ResourceGroup = $kv.ResourceGroupName
                                RuleName      = "Network ACL"
                                CurrentIP     = $ipRange
                                NormalizedIP  = $normalizedIP
                                RulePriority  = "N/A"
                                RuleAction    = if ($networkAcls.DefaultAction -eq "Allow") { "Deny-Except" } else { "Allow-Only" }
                            })
                            $ipRulesFound++
                            Write-Host "    Found IP rule: $ipRange" -ForegroundColor DarkGray
                        }
                    }
                }
                catch {
                    Write-Host "    [WARN] Error processing Key Vault $($kv.VaultName): $($_.Exception.Message)" -ForegroundColor Yellow
                }
            }
        }
        catch {
            Write-Host "  [INFO] No Key Vaults found or access denied" -ForegroundColor DarkGray
        }

        # 5. Cosmos DB Accounts
        try {
            $cosmosAccounts = Get-AzCosmosDBAccount -ErrorAction Stop
            Write-Host "  Found $($cosmosAccounts.Count) Cosmos DB Accounts" -ForegroundColor DarkGray
            foreach ($account in $cosmosAccounts) {
                try {
                    $ipRules = (Get-AzCosmosDBAccount -ResourceGroupName $account.ResourceGroup -Name $account.Name -ErrorAction Stop).IpRules
                    if ($ipRules) {
                        foreach ($rule in $ipRules) {
                            $normalizedIP = Normalize-IP $rule.IpAddressOrRange
                            $report.Add([PSCustomObject]@{
                                Subscription    = $sub.Name
                                ResourceType   = "Cosmos DB"
                                ResourceName   = $account.Name
                                ResourceGroup = $account.ResourceGroup
                                RuleName      = "IP Rule"
                                CurrentIP     = $rule.IpAddressOrRange
                                NormalizedIP  = $normalizedIP
                                RulePriority  = "N/A"
                                RuleAction    = "Allow"
                            })
                            $ipRulesFound++
                            Write-Host "    Found IP rule: $($rule.IpAddressOrRange)" -ForegroundColor DarkGray
                        }
                    }
                }
                catch {
                    Write-Host "    [WARN] Error processing Cosmos DB $($account.Name): $($_.Exception.Message)" -ForegroundColor Yellow
                }
            }
        }
        catch {
            Write-Host "  [INFO] No Cosmos DB Accounts found or access denied" -ForegroundColor DarkGray
        }

        # 6. Container Registries
        try {
            $registries = Get-AzContainerRegistry -ErrorAction Stop
            Write-Host "  Found $($registries.Count) Container Registries" -ForegroundColor DarkGray
            foreach ($acr in $registries) {
                try {
                    $networkRuleSet = Get-AzContainerRegistryNetworkRuleSet -RegistryName $acr.Name -ResourceGroupName $acr.ResourceGroupName -ErrorAction Stop
                    if ($networkRuleSet.IpRule) {
                        foreach ($rule in $networkRuleSet.IpRule) {
                            $normalizedIP = Normalize-IP $rule.IpAddressOrRange
                            $report.Add([PSCustomObject]@{
                                Subscription    = $sub.Name
                                ResourceType   = "Container Registry"
                                ResourceName   = $acr.Name
                                ResourceGroup = $acr.ResourceGroupName
                                RuleName      = "IP Rule"
                                CurrentIP     = $rule.IpAddressOrRange
                                NormalizedIP  = $normalizedIP
                                RulePriority  = "N/A"
                                RuleAction    = "Allow"
                            })
                            $ipRulesFound++
                            Write-Host "    Found IP rule: $($rule.IpAddressOrRange)" -ForegroundColor DarkGray
                        }
                    }
                }
                catch {
                    Write-Host "    [WARN] Error processing Container Registry $($acr.Name): $($_.Exception.Message)" -ForegroundColor Yellow
                }
            }
        }
        catch {
            Write-Host "  [INFO] No Container Registries found or access denied" -ForegroundColor DarkGray
        }
    }
    catch {
        Write-Host "  [ERROR] Failed to process subscription $($sub.Name): $($_.Exception.Message)" -ForegroundColor Red
        continue
    }
}

# Display summary
Write-Host "`nScan Complete:" -ForegroundColor Green
Write-Host "  Tenant ID: $tenantId"
Write-Host "  Subscriptions Processed: $subscriptionsProcessed of $($subscriptions.Count)"
Write-Host "  Individual IP Rules Found: $ipRulesFound" -ForegroundColor Cyan

# Export findings to CSV
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$reportFile = "$env:USERPROFILE\Downloads\AzureIPWhitelistingReport_$timestamp.csv"
$report | Export-Csv -Path $reportFile -NoTypeInformation -Encoding UTF8
Write-Host "`nReport exported to: $reportFile" -ForegroundColor Green

# IP Update Functionality
if ($OldIP -and $NewIP) {
    # Normalize the old IP for comparison
    $normalizedOldIP = Normalize-IP $OldIP
    
    # Find matching rules (compare both original and normalized IPs)
    $matchingRules = $report | Where-Object { 
        $_.CurrentIP -eq $OldIP -or 
        $_.NormalizedIP -eq $OldIP -or
        $_.CurrentIP -eq $normalizedOldIP -or
        $_.NormalizedIP -eq $normalizedOldIP
    }
    
    $changesToMake = $matchingRules.Count
    
    if ($changesToMake -eq 0) {
        Write-Host "`nNo rules found matching IP: $OldIP (Normalized: $normalizedOldIP)" -ForegroundColor Yellow
        Write-Host "  Note: Check if the IP exists in different formats (single IP vs range)" -ForegroundColor DarkGray
        return
    }

    Write-Host "`nFound $changesToMake rules matching IP $OldIP (Normalized: $normalizedOldIP):" -ForegroundColor Cyan
    $matchingRules | Format-Table -Property Subscription, ResourceType, ResourceName, ResourceGroup, CurrentIP -AutoSize

    if (-not $SkipConfirmation -and -not $PreviewOnly) {
        $confirmation = Read-Host "`nAre you sure you want to update these $changesToMake rules from $OldIP to $NewIP? (y/n)"
        if ($confirmation -ne 'y') {
            Write-Host "Update cancelled." -ForegroundColor Yellow
            return
        }
    }

    # Process updates
    $updatedCount = 0
    foreach ($rule in $matchingRules) {
        try {
            Set-AzContext -Subscription (Get-AzSubscription -SubscriptionName $rule.Subscription).Id -TenantId $tenantId | Out-Null
            Write-Host "Updating $($rule.ResourceType) $($rule.ResourceName) in subscription $($rule.Subscription)..." -NoNewline
            
            if ($PreviewOnly) {
                Write-Host " [Preview Only - No changes made]" -ForegroundColor DarkGray
                continue
            }

            switch ($rule.ResourceType) {
                "App Service" {
                    $config = Get-AzWebAppAccessRestrictionConfig -ResourceGroupName $rule.ResourceGroup -Name $rule.ResourceName
                    $ruleToUpdate = $config.MainSiteAccessRestrictions | Where-Object { 
                        $_.IpAddress -eq $rule.CurrentIP -or 
                        (Normalize-IP $_.IpAddress) -eq $normalizedOldIP
                    }
                    if ($ruleToUpdate) {
                        $ruleToUpdate.IpAddress = $NewIP
                        $config = Set-AzWebAppAccessRestrictionConfig -ResourceGroupName $rule.ResourceGroup -Name $rule.ResourceName -AccessRestriction $config
                    }
                }
                "Storage Account" {
                    $networkRuleSet = Get-AzStorageAccountNetworkRuleSet -ResourceGroupName $rule.ResourceGroup -Name $rule.ResourceName
                    $ruleToUpdate = $networkRuleSet.IPRules | Where-Object { 
                        $_.IPAddressOrRange -eq $rule.CurrentIP -or 
                        (Normalize-IP $_.IPAddressOrRange) -eq $normalizedOldIP
                    }
                    if ($ruleToUpdate) {
                        $ruleToUpdate.IPAddressOrRange = $NewIP
                        Update-AzStorageAccountNetworkRuleSet -ResourceGroupName $rule.ResourceGroup -Name $rule.ResourceName -IPRule $networkRuleSet.IPRules
                    }
                }
                "SQL Server" {
                    $firewallRules = Get-AzSqlServerFirewallRule -ResourceGroupName $rule.ResourceGroup -ServerName $rule.ResourceName
                    if ($rule.CurrentIP -match '^(\d+\.\d+\.\d+\.\d+)-(\d+\.\d+\.\d+\.\d+)$') {
                        $startIP = $matches[1]
                        $endIP = $matches[2]
                        $ruleToUpdate = $firewallRules | Where-Object { 
                            ($_.StartIpAddress -eq $startIP -and $_.EndIpAddress -eq $endIP) -or
                            ($_.StartIpAddress -eq $OldIP -and $_.EndIpAddress -eq $OldIP)
                        }
                        if ($ruleToUpdate) {
                            Set-AzSqlServerFirewallRule -ResourceGroupName $rule.ResourceGroup -ServerName $rule.ResourceName `
                                -FirewallRuleName $ruleToUpdate.FirewallRuleName -StartIpAddress $NewIP -EndIpAddress $NewIP
                        }
                    }
                }
                "Key Vault" {
                    $vault = Get-AzKeyVault -VaultName $rule.ResourceName -ResourceGroupName $rule.ResourceGroup
                    $networkAcls = $vault.NetworkAcls
                    $updatedIpRanges = $networkAcls.IpAddressRanges | ForEach-Object { 
                        if ($_ -eq $rule.CurrentIP -or (Normalize-IP $_) -eq $normalizedOldIP) { $NewIP } else { $_ } 
                    }
                    Update-AzKeyVaultNetworkRuleSet -VaultName $rule.ResourceName -ResourceGroupName $rule.ResourceGroup -IpAddressRange $updatedIpRanges
                }
                "Cosmos DB" {
                    $account = Get-AzCosmosDBAccount -ResourceGroupName $rule.ResourceGroup -Name $rule.ResourceName
                    $ipRules = $account.IpRules | ForEach-Object { 
                        if ($_.IpAddressOrRange -eq $rule.CurrentIP -or (Normalize-IP $_.IpAddressOrRange) -eq $normalizedOldIP) { 
                            @{IpAddressOrRange=$NewIP} 
                        } else { $_ } 
                    }
                    Update-AzCosmosDBAccount -ResourceGroupName $rule.ResourceGroup -Name $rule.ResourceName -IpRule $ipRules
                }
                "Container Registry" {
                    $networkRuleSet = Get-AzContainerRegistryNetworkRuleSet -RegistryName $rule.ResourceName -ResourceGroupName $rule.ResourceGroup
                    $ipRules = $networkRuleSet.IpRule | ForEach-Object { 
                        if ($_.IpAddressOrRange -eq $rule.CurrentIP -or (Normalize-IP $_.IpAddressOrRange) -eq $normalizedOldIP) { 
                            @{IpAddressOrRange=$NewIP; Action="Allow"} 
                        } else { $_ } 
                    }
                    Update-AzContainerRegistryNetworkRuleSet -RegistryName $rule.ResourceName -ResourceGroupName $rule.ResourceGroup -IpRule $ipRules
                }
            }
            
            Write-Host " [Updated]" -ForegroundColor Green
            $updatedCount++
        }
        catch {
            Write-Host " [Error: $($_.Exception.Message)]" -ForegroundColor Red
        }
    }

    Write-Host "`nUpdate Complete:" -ForegroundColor Green
    Write-Host "  Rules identified for update: $changesToMake"
    Write-Host "  Successfully updated: $updatedCount" -ForegroundColor Cyan
    if ($changesToMake -gt $updatedCount) {
        Write-Host "  Failed updates: $($changesToMake - $updatedCount)" -ForegroundColor Yellow
    }
}

# Open the report file
if (Test-Path $reportFile) {
    Invoke-Item -Path (Split-Path -Path $reportFile -Parent)
}