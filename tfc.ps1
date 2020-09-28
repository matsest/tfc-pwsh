<#
#### requires ps-version 7.0 ####
<#
.SYNOPSIS
API experiment to get TFC workspaces info and trigger a workspace run
.DESCRIPTION
Lists the workspace information and allows you to interactively trigger a run.
.PARAMETER <org>
<Organization name>
.PARAMETER <TFE_TOKEN>
<Terraform Token> - defaults to the $TF_TOKEN environment variable
.PARAMETER <Server>
<Terraform Cloud/Enterprise Server name > - defaults to app.terraform.io
.NOTES
   Version:        0.2
   Author:         Mats Estensen
   Creation Date:  Tuesday, September 28th 2020
   File: tfc.ps1

   Version:        0.1
   Author:         John Alfaro
   Creation Date:  Saturday, July 25th 2020, 11:10:44 pm
   File: tf.ps1
   Copyright (c) 2020 jalfaro
HISTORY:
Date      	          By	          Comments
----------	          ---	          ----------------------------------------------------------
28.09.2020            Mats Estensen   See github.com/matsest/tfc-pwsh for changes
25.07.2020            John Alfaro     Initial version

.LINK
   https://jalfaro.blog.com
   https://github.com/matsest/tfc-pwsh

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
# Using the default org (app.terraform.io) and having TF_TOKEN set as an env variable
.\tfc.ps1 -Org "myorg"

.EXAMPLE
# Passing all the variables explictily (not recommended)
.\tfc.ps1 -Org "myorg" -Server "app.terraform.io" -TF_TOKEN $MY_TF_TOKEN
#>

[cmdletBinding()]
Param(
    [Parameter(Mandatory = $true)]
    [string] $Org,
    [Parameter(Mandatory = $false)]
    [string] $Server = "app.terraform.io",
    [Parameter(Mandatory = $false)]
    [string] $TF_TOKEN = $env:TF_TOKEN
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
    $pages = (Invoke-RestMethod  -Uri "https://$Server/api/v2/organizations/$Org/workspaces?page%5Bnumber=$pag%5D" -Method Get -ContentType "application/vnd.api+json" -Headers $headers -ErrorVariable $ErrorCredential).meta.pagination.'total-pages' 
    While ($pag -le $pages) {
        #getting all the workspace information on the organization
        $data = (Invoke-RestMethod  -Uri "https://$Server/api/v2/organizations/$Org/workspaces?page%5Bnumber=$pag%5D" -Method Get -ContentType "application/vnd.api+json" -Headers $headers).data

        Write-Verbose "Getting Terraform Workspaces"
        foreach ($workspace in $data) {
            $workspaceID = $workspace.id
            Write-Verbose (@("Getting workspace {0}/{1} on page {2}/{3}" -f $data.Indexof($workspace), $data.Count, $pag, $pages) | Out-String)
            #This will get the state information of the workspaces
            $status = (Invoke-RestMethod  -Uri "https://$Server/api/v2/workspaces/$workspaceID/runs" -Method Get -ContentType "application/vnd.api+json" -Headers $headers).data.attributes.status
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
 
$workspaces | Out-Host
$selectedWorkspaceID = Read-Host "Enter a workspace ID to trigger a run for"
$selectedWorkspaceName = ($workspaces | Where-Object -Property WorkSpaceID -eq $selectedWorkspaceID).WorkspaceName
$selectedWorkspaceID | ForEach-Object -Parallel {
    $body = @"
    {
        "data": {
            "attributes": {
                "is-destroy": false,
                "message": "triggered from Powershell"
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
 
    # Trigger run for selected workspace
    try {
        $runId = (Invoke-RestMethod  -Uri "https://$using:Server/api/v2/runs" -Method POST -ContentType "application/vnd.api+json" -Headers $using:headers -Body $body -ErrorVariable $ErrorCredential).data.id
        "Success! See the run here: https://$using:Server/app/$using:Org/workspaces/$using:selectedWorkspaceName/runs/$runId"
    }
    catch {
        IF ($ErrorCredential) {
            Write-Warning -Message  "Review - Credentials to connect to TFC/TFE"
        }
        Write-Warning -Message $error[0].exception.message
    }
}