# Install module if needed
# Install-Module Microsoft.Graph -Scope CurrentUser -Force

# Connect as Global Admin
Connect-MgGraph -Scopes "Application.Read.All AppRoleAssignment.ReadWrite.All"

# Get your app's service principal
$appSp = Get-MgServicePrincipal -Filter "displayName eq 'TA-P-AUTOMATION'"

# Get Microsoft Graph's service principal
$graphSp = Get-MgServicePrincipal -Filter "appId eq '00000003-0000-0000-c000-000000000000'"

# Get the AuditLog.Read.All app role ID
$appRole = $graphSp.AppRoles | Where-Object {$_.Value -eq "AuditLog.Read.All"}

# Create the app role assignment
$params = @{
    "principalId" = $appSp.Id
    "resourceId" = $graphSp.Id
    "appRoleId" = $appRole.Id
}

New-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $appSp.Id -BodyParameter $params

# Verify
Get-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $appSp.Id