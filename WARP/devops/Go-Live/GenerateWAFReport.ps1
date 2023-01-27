﻿<#
.SYNOPSIS
  Creates a customer presentation PowerPoint deck using PowerShell.

.DESCRIPTION
  This script takes a Well-Architected Go-Live Assessment Report as input and generates a customer presentation PowerPoint deck.
  The report must be located in the same directory as the following files: 
    - GenerateWAFReport.ps1
    - PnP_PowerPointReport_Template.pptx
    - WAF Category Descriptions.csv

.PARAMETER <AssessmentReport>
    The path to the Well-Architected Assessment Report that was generated by the Microsoft Assessments platform in the following format: <pathttothereport.csv>.

.PARAMETER <AsessmentType>
    The type of Well-Architected Assessment that was performed.
    The value should be 'Go-Live' for a Go-Live Assessment.
    The value should be 'Core' for a Reliability, Security, Cost Optimization, Operational Excellence or Performance Efficiency Assessment.

.PARAMETER <YourName>
    Your name in the following format: <Firstname Lastname>.

.PARAMETER <YourTitle>
    Your title or function in your current organization in the following format: <Title>.

.PARAMETER <YourOrganization>
    The organization name you are currently part of in the following format: <Organization>.

.INPUTS
  This script takes a Well-Architected Assessment Report in a CSV format as input. 

.OUTPUTS
  A PowerPoint file will be created within the current directory with name in the format of: Azure Well-Architected $AssessmentType Review - Executive Summary - mmm-dd-yyyy hh.mm.ss.pptx

.NOTES
  Version:        1.0
  Author:         Farouk Friha
  Creation Date:  06/15/2022
  
.EXAMPLE
  .\GenerateWAFReport.ps1 
        -AssessmentReport ".\Go_Live_Well_Architected_Review_Jul_08_2022_4_35_46_PM.csv" 
        -AssessmentType Go-Live 
        -YourName "Farouk Friha" 
        -YourTitle "Cloud Solution Architect" 
        -YourOrganization "Customer Experience & Success"

  .\GenerateWAFReport.ps1 
        -AssessmentReport ".\Reliability_Well_Architected_Review_Jul_08_2022_4_35_46_PM.csv" 
        -AssessmentType Core
        -YourName "Farouk Friha" 
        -YourTitle "Cloud Solution Architect" 
        -YourOrganization "Customer Experience & Success"
#>

#---------------------------------------------------------[Initialisations]--------------------------------------------------------
[CmdletBinding()]
param 
(
    [Parameter(Mandatory=$True)]
    [ValidateScript({Test-Path $_ }, ErrorMessage = "Unable to find the selected file. Please select a valid Well-Architected Assessment report in the <filename>.csv format.")]
    [string] $AssessmentReport,

    [Parameter(Mandatory=$True)]
    [ValidateSet("Go-Live", "Core")]
    [string] $AssessmentType,

    [Parameter(Mandatory=$True)]
    [string] $YourName,

    [Parameter(Mandatory=$True)]
    [string] $YourTitle,

    [Parameter(Mandatory=$True)]
    [string] $YourOrganization
)

#----------------------------------------------------------[Declarations]----------------------------------------------------------

#Get the working directory from the script
$workingDirectory = (Get-Location).Path

#Get PowerPoint template and description file
$reportTemplate = "$workingDirectory\PnP_PowerPointReport_Template.pptx"
$descriptionsFile = Import-Csv "$workingDirectory\WAF Category Descriptions.csv"
$ratingDescription = @{
    "Critical" = "Based on the outcome of the assessment your workload seems to be in a critical state. Please review the recommendations for each service to resolve key deployment risks and improve your results."
    "Moderate" = "Almost there. You have some room to improve but you are on track. Review the recommendations to see what actions you can take to improve your results."
    "Excellent" = "Your workload is broadly following the principles of the Well-Architected framework. Review the recommendations to see where you can improve your results even further."
}

#Initialize variables
$summaryAreaIconX = 385.1129
$localReportDate = Get-Date -Format g
$reportDate = Get-Date -Format "yyyy-MM-dd-HHmm"
$summaryAreaIconY = @(180.4359, 221.6319, 262.3682, 303.1754, 343.8692, 386.6667)

#-----------------------------------------------------------[Functions]------------------------------------------------------------

#Read input file content
function Read-File($File)
{
    #Get report content
    $content = Get-Content $File

    #Get findings
    $findingsStartIdentifier = $content | Where-Object { $_.Contains("Category,Link-Text,Link,Priority,ReportingCategory,ReportingSubcategory,Weight,Context") } | Select-Object -Unique -First 1
    $findingsStart = $content.IndexOf($findingsStartIdentifier)
    $endStringIdentifier = $content | Where-Object{$_.Contains("--,,")} | Select-Object -Unique -First 1
    $findingsEnd = $content.IndexOf($endStringIdentifier) - 1
    $findings = $content[$findingsStart..$findingsEnd] | Out-String | ConvertFrom-CSV -Delimiter ","
    $null = $findings | ForEach-Object { $_.Weight = [int]$_.Weight }

    #Get pillars
    $pillars = $findings | ForEach-Object { $_.Category.Split(":")[1].Trim() } | Select-Object -Unique

    #Get scores
    $scoresStart = $content.IndexOf("Recommendations for your workload,,,,,,,") + 2
    $scoresEnd = $findingsStart - 5
    $scores = $content[$scoresStart..$scoresEnd] | Out-String | ConvertFrom-Csv -Delimiter "," -Header 'Category', 'Criticality', 'Score'
    $null = $scores | ForEach-Object { $_.Score = $_.Score.Trim("'").Replace("/100", ""); $_.Score = [int]$_.Score}
   
    #Get score per pillar and weight per service
    [System.Collections.ArrayList]$scorecard = @{}
    
    foreach($pillar in $pillars)
    {
        #Get services per pillar
        $servicesPerPillar = $scores | Where-Object Category -like "*$pillar*" | Select-Object -Property Category, Score

        #Get score per pillar
        [int]$scorePerPillar = ($servicesPerPillar.Score | Measure-Object -Sum).Sum / ($servicesPerPillar.Score | Measure-Object -Sum).Count

        #Get recommendations per service
        $recommendationsPerService = $findings | Where-Object Category -like "*$pillar*" | Select-Object -Property Category, Weight, Link-Text | Group-Object -Property Category
        
        #Get weight per service
        [System.Collections.ArrayList]$weightPerService = @{}

        foreach($recommendationPerService in $recommendationsPerService)
        {
            $firstObject = $recommendationPerService.Group | Sort-Object -Property Weight -Descending | Select-Object -First 1

            $wObject = [PSCustomObject]@{
                "Service" = $recommendationPerService.Name.Split("-")[2].Split(":")[0].Trim()
                "Weight" = [int]($firstObject.Weight)
                "Recommendation" = $firstObject."Link-Text"
            }

            $null = $weightPerService.Add($wObject)
        }

        $sObject = [PSCustomObject]@{
            "Pillar" = $pillar;
            "Weights" = $weightPerService;
            "Score" = $scorePerPillar;
            "Description" = ($descriptionsFile | Where-Object{$_.Pillar -eq $pillar -and $_.Category -eq "Survey Level Group"}).Description;
            "Rating" = Get-Rating -WeightOrScore $scorePerPillar
        }

        $null = $scorecard.Add($sObject)
    }

    $scorecard = $scorecard | Sort-Object -Property Score
    $overallScore = $content[3].Split(',')[2].Trim("'").Split('/')[0]
    $overallRating = Get-Rating -WeightOrScore $overallScore

    return $scorecard, $overallScore, $overallRating
}

function Get-Rating($WeightOrScore)
{
    if($WeightOrScore -lt 33)
    { 
        $rating = "Critical"
    }
    elseif($WeightOrScore -ge 33 -and $WeightOrScore -lt 67)
    { 
        $rating = "Moderate" 
    }
    elseif($WeightOrScore -ge 67)
    { 
        $rating = "Excellent" 
    }

    return $rating
}

function Edit-Slide($Slide, $StringToFindAndReplace, $Gauge, $Counter)
{
    $StringToFindAndReplace.GetEnumerator() | ForEach-Object { 

        if($_.Key -like "*Threshold*")
        {
            $Slide.Shapes[$_.Key].Left = [single]$_.Value
        }
        else
        {
            $Slide.Shapes[$_.Key].TextFrame.TextRange.Text = $_.Value
        }

        if($Gauge)
        {
            $Slide.Shapes[$Gauge].Duplicate() | Out-Null
            $Slide.Shapes[$Slide.Shapes.Count].Left = [single]$summaryAreaIconX
            $Slide.Shapes[$Slide.Shapes.Count].Top = $summaryAreaIconY[$Counter]
        }
    }
}

function Clear-Presentation($Slide)
{
    $slideToRemove = $Slide.Shapes | Where-Object {$_.TextFrame.TextRange.Text -match '^\[Pillar\]$'}
    $shapesToRemove = $Slide.Shapes | Where-Object {$_.TextFrame.TextRange.Text -match '^\[(W|Resource_Type_|Recommendation_)?[0-9]\]$'}

    if($slideToRemove)
    {
        $Slide.Delete()
    }
    elseif ($shapesToRemove)
    {
        foreach($shapeToRemove in $shapesToRemove)
        {
            $shapeToRemove.Delete()
        }
    }
}

#-----------------------------------------------------------[Execution]------------------------------------------------------------
#Read input file
$scorecard, $overallScore, $overallRating = Read-File -File $AssessmentReport

#Instantiate PowerPoint variables
$application = New-Object -ComObject PowerPoint.Application
$reportTemplateObject = $application.Presentations.Open($reportTemplate)
$slides = @{
    "Cover" = $reportTemplateObject.Slides[1];
    "Summary" = $reportTemplateObject.Slides[8];
    "Detail" = $reportTemplateObject.Slides[9];
    "End" = $reportTemplateObject.Slides[10]
}

#Edit cover slide
$coverSlide = $slides.Cover
$stringsToReplaceInCoverSlide = @{ "Cover - Assessment_Type" = "Well-Architected $AssessmentType Review"; "Cover - Your_Name" = $YourName; "Cover - Your_Title" = $YourTitle; "Cover - Your_Organization" = $YourOrganization; "Cover - Report_Date" = "Report generated: $localReportDate" }
Edit-Slide -Slide $coverSlide -StringToFindAndReplace $stringsToReplaceInCoverSlide

#Edit summary slide
$stringsToReplaceInSummarySlide = @{ "Summary - Score_Overall" = $overallScore; "Summary - Rating_Description" = $ratingDescription.$overallRating; "Summary - Threshold" = [int]$overallScore*2.47+56 }
Edit-Slide -Slide $slides.Summary -StringToFindAndReplace $stringsToReplaceInSummarySlide

$i = 0

#Duplicate, move and edit summary and detail slides for each pillar
foreach($pillar in $scorecard.Pillar)
{
    $i++
    $scoreForCurrentPillar = $scorecard | Where-Object{$_.Pillar -contains $pillar}
    
    #Add score per pillar
    $stringsToReplaceInSummarySlide = @{ "Summary - Pillar_$i" = $pillar; "Summary - Score_$i" = [string]$scoreForCurrentPillar.score }
    Edit-Slide -Slide $slides.Summary -StringToFindAndReplace $stringsToReplaceInSummarySlide -Gauge "Summary - $($scoreForCurrentPillar.Rating)_Gauge" -Counter $i
    
    #Add services that need attention
    $newDetailSlide = $slides.Detail.Duplicate()
    $newDetailSlide.MoveTo($reportTemplateObject.Slides.Count-1)
    $stringsToReplaceInDetailSlide = @{ "Detail - Pillar" = $pillar; "Detail - Pillar_Description" = $scoreForCurrentPillar.Description; "Detail - Pillar_Score" = [string]$scoreForCurrentPillar.Score; "Detail - Threshold" = [int]$scoreForCurrentPillar.Score*2.47+56}
    Edit-Slide -Slide $newDetailSlide -StringToFindAndReplace $stringsToReplaceInDetailSlide

    if(($scoreForCurrentPillar.Weights."Service" | Measure-Object).Count -lt 5)
    {
        $servicesPerPillar = $scoreForCurrentPillar.Weights | Sort-Object -Property "Weight" -Descending | Select-Object -First ($scoreForCurrentPillar.Weights."Service" | Measure-Object).Count
    }
    else 
    {
        $servicesPerPillar = $scoreForCurrentPillar.Weights | Sort-Object -Property "Weight" -Descending | Select-Object -First 5
    }

    $j = 0

    foreach($servicePerPillar in $servicesPerPillar)
    {
        $j++
        $stringsToReplaceInDetailSlide = @{ "Detail - Resource_Type_$j" = [string]$servicePerPillar."Service"; "Detail - Weight_$j" = [string]$servicePerPillar.Weight; "Detail - Recommendation_$j" = [string]$servicePerPillar."Recommendation"}
        Edit-Slide -Slide $newDetailSlide -StringToFindAndReplace $stringsToReplaceInDetailSlide
    }

    #Remove empty shapes from detail slides
    Clear-Presentation -Slide $newDetailSlide
}

#Remove empty detail slides
Clear-Presentation -Slide $slides.Detail

#Save presentation and close object
$reportTemplateObject.SavecopyAs(“$workingDirectory\Azure Well-Architected $AssessmentType Review - Executive Summary - $reportDate.pptx”)
$reportTemplateObject.Close()

$application.quit()
$application = $null
[gc]::collect()
[gc]::WaitForPendingFinalizers()