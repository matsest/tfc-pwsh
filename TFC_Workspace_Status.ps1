<#
#### requires ps-version 7.0 ####
<#
.SYNOPSIS
Script to get TFE/TFC workspace info to check version and also to trigger the workpaces
.DESCRIPTION
The script will allow you to get you TFC/TFE Organizations workspace Information and 
trigger multiple workspaces in parallel  if required by making API calls 
.PARAMETER <org>
<Organization name>
.PARAMETER <TFE_TOKEN>
<Terraform Token>
.PARAMETER <Server>
<Terraform Cloud/Enterprise Sever name >
.NOTES
   Version:        0.1
   Author:         John Alfaro
   Creation Date:  Saturday, July 25th 2020, 11:10:44 pm
   File: tf.ps1
   Copyright (c) 2020 jalfaro
HISTORY:
Date      	          By	Comments
----------	          ---	----------------------------------------------------------

.LINK
   https://jalfaro.blog.com

.COMPONENT
 Required Modules: 

.LICENSE
Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the Software), to deal
in the Software without restriction, including without limitation the rights
to use copy, modify, merge, publish, distribute sublicense and /or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED AS IS, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
 
.EXAMPLE
.\tf.ps1 -Org  "CerocoolCorp" -Server "app.terraform.io" -tfe_token "fdsgfhfhtrhs4t546567egbgl"
#>
[cmdletBinding()]
Param(
    [Parameter(Mandatory = $true)]
    [string] $Org,
    [Parameter(Mandatory = $true)]
    [string] $Server,
    [Parameter(Mandatory = $true)]
    [string] $TF_TOKEN
)

$pag = 1
$wrk = $null
$workspaces = @()
$instances = @()


$headers = @{
    Authorization = "Bearer $TF_TOKEN"
}

try {
    Write-Verbose -Message "connecting and getting workspace info from TFC/TFE using token"
    #Getting the numnber of pages used in TFC/TFE
    $page = (Invoke-RestMethod  -Uri "https://$Server/api/v2/organizations/$Org/workspaces?page%5Bnumber=$pag%5D" -Method Get -ContentType "application/vnd.api+json" -Headers $headers -ErrorVariable $ErrorCredential).meta.pagination.'total-pages' 
    While ($pag -le $page) {
        #getting all the workspace information on the organization
        $data = (Invoke-RestMethod  -Uri "https://$Server/api/v2/organizations/$Org/workspaces?page%5Bnumber=$pag%5D" -Method Get -ContentType "application/vnd.api+json" -Headers $headers).data

        foreach ($workspace in $data) {
            $workspaceID = $workspace.id
            Write-Progress -Activity "getting Terraform Workspaces" -Status "Working on worksapce $workspace"  -PercentComplete ((($data.IndexOf($workspace)) / $data.Count) * 100)
            Write-Progress -Activity "Terraform Workspaces" -Status "Done" -PercentComplete 100 -Completed
            #This will get the state information of the workspaces
            $status = (Invoke-RestMethod  -Uri "https://$Server/api/v2/workspaces/$workspaceID/runs" -Method Get -ContentType "application/vnd.api+json" -Headers $headers).data.attributes.status[0]
            $wrk = new-object PSObject
            $wrk | add-member -MemberType NoteProperty -Name "WorkspaceID" -Value $workspace.id
            $wrk | add-member -MemberType NoteProperty -Name "WorkspaceName" -Value $workspace.attributes.name
            $wrk | add-member -MemberType NoteProperty -Name "Version" -Value $workspace.attributes.'terraform-version'
            $wrk | add-member -MemberType NoteProperty -Name "Status" -Value $status

            $workspaces += $wrk
        }
        $pag++
    }
}
catch {
    IF ($ErrorCredential) {
        Write-Warning -Message  "Review - Credentials to connect to TFC/TFE"
    }
    Write-Warning -Message $error[0].exception.message
    break
}
 
$instances = ($workspaces | Out-GridView -OutputMode Multiple -Title ‘Please select the workspace/worspaces to run.’).WorkspaceID 
$message = Read-Host "Message for this Workpsace run"
$instances | ForEach-Object -parallel {
    $body = @"
    {
        "data": {
            "attributes": {
                "is-destroy": false,
                "message": "$using:message"
            },
            "type": "runs",
            "relationships": {
                "workspace": {
                    "data": {
                        "type": "workspaces",
                        "id": "$_"
                    }
                }
            },
            "configuration-version": {}
        }
    }
"@
 
    #This will attempt to trigger the run on all selected workspaces
    try {
        Invoke-RestMethod  -Uri "https://$using:server/api/v2/runs" -Method POST -ContentType "application/vnd.api+json" -Headers $using:headers -Body $body -ErrorVariable $ErrorCredential | Out-Null
    }
    catch {
        IF ($ErrorCredential) {
            Write-Warning -Message  "Review - Credentials to connect to TFC/TFE"
        }
        Write-Warning -Message $error[0].exception.message
    }
}
