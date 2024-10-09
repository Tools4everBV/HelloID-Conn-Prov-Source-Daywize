##################################################
# HelloID-Conn-Prov-Source-Daywize-Persons
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

function Add-FlattedObject {
    [cmdletbinding()]
    param(
        [Parameter(
            Position = 0,
            Mandatory = $true,
            ValueFromPipeline = $true)]
        $InputObject,

        [Parameter()]
        $ObjectToAdd,

        [Parameter(Mandatory)]
        $Prefix
    )
    try {
        foreach ($property in $ObjectToAdd.PSObject.Properties) {
            $InputObject | Add-Member @{
                "$($Prefix)_$($property.Name)" = $property.Value
            }
        }
    } catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }
}
#endregion

try {
    # Setup Authorization Headers
    $encodedCreds = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes("$($config.userName):$($config.password)"))
    $basicAuthValue = "Basic $encodedCreds"
    $headers = @{
        Authorization = $basicAuthValue
        Accept        = 'application/json'
    }

    # Get Source information
    Write-Information 'Starting to get Daywize Employees'
    $expandProperties = 'Medewerker_Samenvatting_Medewerker,Medewerker_Samenvatting_SD_TypeMedewerker, Medewerker_Samenvatting_SD_GebruikvanNaam'
    $splatPersons = @{
        Uri     = "$($config.baseUrl)/odata/POS_Provisioning/Medewerker_SamenvattingList?`$expand=$($expandProperties)"
        Headers = $headers
    }
    if (-Not($dryRun -eq $true)) {
        $personList = Invoke-DaywizeRequest @splatPersons
    } else {
        $personList = Invoke-DaywizeRequest @splatPersons -pageSize 500 -RunOnePage
    }
    Write-Information "Employees Found: $($personList.count)"


    Write-Information 'Starting to get Daywize Contracts'
    $expandProperties = 'Medewerker, SD_Standplaats'
    $splatContracts = @{
        Uri     = "$($config.baseUrl)/odata/POS_Provisioning/ContractList?`$expand=$($expandProperties)"
        Headers = $headers
    }
    if (-Not($dryRun -eq $true)) {
        $contractList = Invoke-DaywizeRequest @splatContracts
    } else {
        $contractList = Invoke-DaywizeRequest @splatContracts -pageSize 1000 -RunOnePage
    }
    Write-Information "Contracts Found: $($contractList.count)"


    Write-Information 'Starting to get Daywize Formations'
    $expandProperties = 'Contract, SD_Afdeling, SD_Functie'
    $splatFormations = @{
        Uri     = "$($config.baseUrl)/odata/POS_Provisioning/FormatieList?`$expand=$($expandProperties)"
        Headers = $headers
    }
    if (-Not($dryRun -eq $true)) {
        $formationList = Invoke-DaywizeRequest @splatFormations
    } else {
        $formationList = Invoke-DaywizeRequest @splatFormations -pageSize 1500 -RunOnePage
    }
    Write-Information "Formations Found: $($formationList.count)"

    Write-Information 'Starting to get Daywize Departments'
    $expandProperties = 'SD_OrganisatieOnderdeel, SD_Kostenplaats'
    $splatDepartments = @{
        Uri     = "$($config.baseUrl)/odata/POS_Provisioning/SD_AfdelingList?`$expand=$($expandProperties)"
        Headers = $headers
    }
    $departmentList = Invoke-DaywizeRequest @splatDepartments
    Write-Information "Departments Found: $($departmentList.count)"


    # Join Source Daywize information to HelloId person and contract model
    Write-Information 'Join the Contracts with the Formations'
    Write-Information "Contracts without a Formation : $(([int[]][Linq.Enumerable]::Except([int[]]$contractlist.contractId, [int[]]$formationList.Contract.ContractID))-join ", ")"
    $contractsGrouped = $contractList | Group-Object ContractID -AsHashTable -AsString
    $departmentGrouped = $departmentList | Group-Object AutoID_Afdeling -AsHashTable -AsString
    $contractListFormatted = [System.Collections.Generic.List[object]]::new()
    foreach ($formation in $formationList) {
        if ($null -eq $formation.Contract ) {
            Write-Information "Formation without a Contract: $($formation.FormatieID)"
        } else {
            $contract = $null
            $contract = ($contractsGrouped["$($formation.Contract.ContractID)"]) | Select-Object * -First 1
            if ($null -ne $contract ) {
                $contract | Add-Member @{
                    Formation  = $formation | Select-Object * -ExcludeProperty SD_Functie, SD_Afdeling
                    ExternalId = $formation.FormatieID
                }

                $contract | Add-FlattedObject -ObjectToAdd $contract.SD_Standplaats -Prefix 'SD_Standplaats'
                $contract = $contract | Select-Object * -ExcludeProperty SD_Standplaats

                $contract | Add-FlattedObject -ObjectToAdd $formation.SD_Functie -Prefix 'SD_Functie'
                $contract | Add-FlattedObject -ObjectToAdd $formation.SD_Afdeling -Prefix 'SD_Afdeling'

                $departmentInformation = $departmentGrouped["$($contract.SD_Afdeling_AutoID_Afdeling)"] | Select-Object * -First 1
                $contract | Add-FlattedObject -ObjectToAdd $departmentInformation.SD_OrganisatieOnderdeel -Prefix 'Department_SD_Org_Ond'
                $contract | Add-FlattedObject -ObjectToAdd $departmentInformation.SD_Kostenplaats -Prefix 'Department_SD_Kost'

                $contractListFormatted.Add($contract)
            }
        }
    }

    $contractListFormattedGrouped = $contractListFormatted | Group-Object { $_.Medewerker.Nummer } -AsHashTable -AsString
    foreach ($person in $personList ) {
        $person | Add-Member @{
            DisplayName = $person.VolledigeNaam
            ExternalId  = $person.Nummer
            Contracts   = [System.Collections.Generic.List[object]]::new()
        }

        $contracts = [array]($contractListFormattedGrouped["$($person.Nummer)"])
        foreach ($c in $contracts) {
            $person.contracts.Add($c)
        }
        Write-Output ($person | ConvertTo-Json -Depth 20)
    }
} catch {
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException') ) {
        $errorObj = Resolve-DaywizeError -ErrorObject $ex
        Write-Warning "Could not import Daywize persons. Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
        Write-Error "Could not import Daywize persons. Error: $($errorObj.FriendlyMessage)"
    } else {
        Write-Warning "Could not import Daywize persons. Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
        Write-Error "Could not import Daywize persons. Error: $($ex.Exception.Message)"
    }
}