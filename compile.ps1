$scriptPath = "./addons/sourcemod/scripting"

foreach ($file in Get-ChildItem -Path $scriptPath -Filter *.sp) {
    Write-Host "Compiling $($file.Name)..."
    & $scriptPath/sourcemod/spcomp -E -w234 -w217 -O2 -v2 -i "$scriptPath/include" $file.FullName -o 
}