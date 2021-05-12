<#
This sample script is not supported under any Microsoft standard support program or service. 
The sample script is provided AS IS without warranty of any kind. Microsoft further disclaims 
all implied warranties including, without limitation, any implied warranties of merchantability 
or of fitness for a particular purpose. The entire risk arising out of the use or performance of 
the sample scripts and documentation remains with you. In no event shall Microsoft, its authors, 
or anyone else involved in the creation, production, or delivery of the scripts be liable for any 
damages whatsoever (including, without limitation, damages for loss of business profits, business 
interruption, loss of business information, or other pecuniary loss) arising out of the use of or 
inability to use the sample scripts or documentation, even if Microsoft has been advised of the 
possibility of such damages.
#>

<#
.SYNOPSIS
Check for any Azure AD registered applications with attached client certificates or secrets 
that will expire in the selected time period (default 60 days).

.DESCRIPTION
This Azure Automation runbook connects to the Azure AD Tenant that its Azure Run As account belongs
to, gets a list of all registered applications in the AAD Tenant, and filters down to applications 
with expiring client certificates or secrets.

Prerequisites: an Azure Automation account with an Azure Run As account credential. 
Run As Service Principal must be assigned the "Global Reader" or "Application Administrator" Azure AD RBAC role.

Thanks to Arindam Hazra for the heavy lifting in walking through how to collect and parse AAD App information.
https://arindamhazra.com/azure-ad-application-client-secret-expiration-report/
https://arindamhazra.com/azure-ad-application-certificate-expiration-report/

.PARAMETER RemainingDays
(Optional) The maximum number of days before a certificate or secret expires for an app 
registration to be in-scope for this report. 
Default: 60

.PARAMETER AzureEnvironment
(Optional) Azure environment name.
Default: AzureCloud

.PARAMETER Login
(Optional) If $false, do not login to Azure/Azure AD.

#>

[Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseApprovedVerbs", "")]
param(
    [int] $RemainingDays = 60,
    [string] $AzureEnvironment = 'AzureCloud',
    [bool] $Login = $true
)

$ErrorActionPreference = "Continue"
$ExpiringDate = (Get-Date).AddDays($RemainingDays).Date

#region Main body

#region Login
if ($Login) {
    try {
        $RunAsConnection = Get-AutomationConnection -Name "AzureRunAsConnection"
        Write-Output "Logging in to Azure ($AzureEnvironment)..."
        
        if (!$RunAsConnection.ApplicationId) {
            $ErrorMessage = "Connection 'AzureRunAsConnection' is incompatible type."
            throw $ErrorMessage            
        }
        
        Connect-AzureAD `
            -ApplicationId $RunAsConnection.ApplicationId `
            -TenantId $RunAsConnection.TenantId `
            -CertificateThumbprint $RunAsConnection.CertificateThumbprint `
            -AzureEnvironmentName $AzureEnvironment
        
    } catch {
        if (!$RunAsConnection) {
            $RunAsConnection | fl | Write-Output
            Write-Output $_.Exception
            $ErrorMessage = "Connection 'AzureRunAsConnection' not found."
            throw $ErrorMessage
        }

        throw $_.Exception
    }
}
#endregion Login

#region Check Azure AD and generate list of apps with expiring secrets and certs
$allApplications = @()
$AadApps = Get-AzureADApplication -All $true 
foreach ($app in $AadApps) {
    $ownerName = "None"
    $ownerObject = (Get-AzureADApplicationOwner -ObjectId $app.objectId)
    if ($null -ne $ownerObject) {
        $ownerName = $ownerObject.DisplayName
    }
    
    # Check Secrets
    foreach ($appPwCred in $app.PasswordCredentials) {

        if ($appPwCred.EndDate -le $ExpiringDate) {
            $objSecret = New-Object PsObject 
            $objSecret | Add-Member ApplicationName $app.DisplayName
            $objSecret | Add-Member ApplicationId $app.AppId
            $objSecret | Add-Member ObjectType $app.ObjectType
            $objSecret | Add-Member ObjectId $app.ObjectId
            $objSecret | Add-Member Owner $ownerName
            $objSecret | Add-Member KeyId $appPwCred.KeyId
            $objSecret | Add-Member CredType "Secret"
            $objSecret | Add-Member ExpirationDate $appPwCred.EndDate
            $allApplications += $objSecret
        }
    }

    # Check Certs
    foreach ($appCertCred in $app.KeyCredentials) {
        
        if($appCertCred.EndDate -le $ExpiringDate) {
            $objCert = New-Object PsObject
            $objCert | Add-Member ApplicationName $app.DisplayName
            $objCert | Add-Member ApplicationId $app.AppId
            $objCert | Add-Member ObjectType $app.ObjectType
            $objCert | Add-Member ObjectId $app.ObjectId
            $objCert | Add-Member Owner $ownerName
            $objCert | Add-Member KeyId $appCertCred.KeyId
            $objCert | Add-Member CredType "Certificate"
            $objCert | Add-Member ExpirationDate $appCertCred.EndDate
            $allApplications += $objCert
        }
    }
}
#endregion Check Azure AD and generate list of apps with expiring secrets and certs

#region Results
Write-Output "Applications with credentials expiring in next $RemainingDays day(s), as of $ExpiringDate"
Write-Output "Number of credentials retrieved: $($allApplications.Length)"
foreach ($line in $($allApplications | ConvertTo-Csv -NoTypeInformation)) {
    Write-Output $line
}
#endregion Results

#endregion Main body
