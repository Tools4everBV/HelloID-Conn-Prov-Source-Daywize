##################################################
# HelloID-Conn-Prov-Source-Daywize-Departments
#
# Version: 1.0.0
##################################################
# Initialize default value's
$config = $configuration | ConvertFrom-Json

function Resolve-DaywizeError {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [object]
        $ErrorObject
    )
    process {
        $httpErrorObj = [PSCustomObject]@{
            ScriptLineNumber = $ErrorObject.InvocationInfo.ScriptLineNumber
            Line             = $ErrorObject.InvocationInfo.Line
            ErrorDetails     = $ErrorObject.Exception.Message
            FriendlyMessage  = $ErrorObject.Exception.Message
        }
        if (-not [string]::IsNullOrEmpty($ErrorObject.ErrorDetails.Message)) {
            $httpErrorObj.ErrorDetails = $ErrorObject.ErrorDetails.Message
        } elseif ($ErrorObject.Exception.GetType().FullName -eq 'System.Net.WebException') {
            if ($null -ne $ErrorObject.Exception.Response) {
                $streamReaderResponse = [System.IO.StreamReader]::new($ErrorObject.Exception.Response.GetResponseStream()).ReadToEnd()
                if (-not [string]::IsNullOrEmpty($streamReaderResponse)) {
                    $httpErrorObj.ErrorDetails = $streamReaderResponse
                }
            }
        }
        try {
            $errorDetailsObject = ($httpErrorObj.ErrorDetails | ConvertFrom-Json)
            $httpErrorObj.FriendlyMessage = $errorDetailsObject.error.message
        } catch {
            $httpErrorObj.FriendlyMessage = $httpErrorObj.ErrorDetails
        }
        Write-Output $httpErrorObj
    }
}

function Invoke-DaywizeRequest {
    [CmdletBinding()]
    param (
        [parameter(Mandatory)]
        [string]
        $Uri,

        [parameter(Mandatory)]
        $Headers,

        [parameter()]
        [string]
        $pageSize = 1000,

        [parameter()]
        [switch]
        $RunOnePage
    )
    try {
        $skip = 0
        $returnValue = [System.Collections.Generic.List[Object]]::new()
        do {
            if ($Uri.Contains('?')) {
                $uriWithOffSet = "$($Uri)&`$top=$($pageSize)&`$skip=$($skip)"
            } else {
                $uriWithOffSet = "$($Uri)?`$top=$($pageSize)&`$skip=$($skip)"
            }
            Write-Information "Invoking command '$($MyInvocation.MyCommand)' to endpoint '$uriWithOffSet'"
            $splatGet = @{
                Uri     = $uriWithOffSet
                Method  = 'GET'
                Headers = $Headers
            }
            $partialResponse = Invoke-RestMethod @splatGet
            if ($partialResponse.value.count -ne 0) {
                $returnValue.AddRange($partialResponse.value)
            }
            $skip += $pageSize
        } while ($partialResponse.value.count -eq $pageSize -and -not $RunOnePage.IsPresent)

        Write-Output $returnValue
    } catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }
}
#endregion

try {
    $encodedCreds = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes("$($config.userName):$($config.password)"))
    $basicAuthValue = "Basic $encodedCreds"
    $headers = @{
        Authorization = $basicAuthValue
        Accept        = 'application/json'
    }

    Write-Information 'Starting to get Daywize Departments'
    $expandProperties = 'SD_BovenliggendeAfdeling, ManagersList'
    $splatDepartments = @{
        Uri     = "$($config.baseUrl)/odata/POS_Provisioning/SD_AfdelingList?`$expand=$($expandProperties)"
        Headers = $headers
    }
    $departmentList = Invoke-DaywizeRequest @splatDepartments
    Write-Information "Departments Found: $($departmentList.count)"
    $activeDepartments = $departmentList | Where-Object { $_._actief -eq $true }
    Write-Information "Active Departments Found: $($activeDepartments.count)"
    foreach ($department in $activeDepartments) {
        if ($department.ManagersList.count -gt 1) {
            $manager = $department.ManagersList | Sort-Object Nummer | Select-Object -First 1
        } else {
            $manager = $department.ManagersList | Select-Object -First 1
        }
        Write-Output (
            @{
                DisplayName       = $department.AfdelingsNaam
                ExternalId        = $department.AutoID_Afdeling
                ManagerExternalId = $manager.Nummer
                ParentExternalId  = $department.SD_BovenliggendeAfdeling.AutoID_Afdeling
            }
        ) | ConvertTo-Json -Depth 10
    }
} catch {
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException') ) {
        $errorObj = Resolve-DaywizeError -ErrorObject $ex
        Write-Warning "Could not import Daywize Departments. Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
        Write-Error "Could not import Daywize Departments. Error: $($errorObj.FriendlyMessage)"
    } else {
        Write-Warning "Could not import Daywize Departments. Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
        Write-Error "Could not import Daywize Departments. Error: $($ex.Exception.Message)"
    }
}