#requires -version 5.1
param([switch]$Preview)
$ErrorActionPreference='Stop'
$suite=Join-Path (Split-Path $PSScriptRoot -Parent) 'Toolkit.Run.ps1'
& $suite -Preview:$Preview
