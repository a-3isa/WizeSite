$cloudFirestoreVersion = "6.6.0"
$src = "$env:APPDATA\..\Local\Pub\Cache\hosted\pub.dev\cloud_firestore-$cloudFirestoreVersion"
$dst = "$PSScriptRoot\..\packages\cloud_firestore"

Write-Host "Copying cloud_firestore $cloudFirestoreVersion from pub cache..."
if (Test-Path $dst) { Remove-Item $dst -Recurse -Force }
Copy-Item $src $dst -Recurse

Write-Host "cloud_firestore $cloudFirestoreVersion copied. Now run: flutter pub get"
