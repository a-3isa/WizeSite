$src = "$env:APPDATA\..\Local\Pub\Cache\hosted\pub.dev\cloud_firestore-6.2.0"
$dst = "$PSScriptRoot\..\packages\cloud_firestore"

Write-Host "Copying cloud_firestore 6.2.0 from pub cache..."
if (Test-Path $dst) { Remove-Item $dst -Recurse -Force }
Copy-Item $src $dst -Recurse

$file = "$dst\android\src\main\java\io\flutter\plugins\firebase\firestore\GeneratedAndroidFirebaseFirestore.java"
Write-Host "Patching Pigeon type IDs in $file"

$content = Get-Content $file -Raw

# Fix readValueOfType: shift PigeonQueryParameters/Snapshot/SnapshotMetadata/TransactionCommand
# from old IDs 137-140 to new IDs 139-142 (Dart 7.2.0 inserted PipelineResult/PipelineSnapshot at 137-138)
$content = $content -replace `
  'case \(byte\) 137:\s+return PigeonQueryParameters\.fromList\(\(ArrayList<Object>\) readValue\(buffer\)\);' ,
  'case (byte) 139:' + "`r`n" + '          return PigeonQueryParameters.fromList((ArrayList<Object>) readValue(buffer));'

$content = $content -replace `
  'case \(byte\) 138:\s+return PigeonQuerySnapshot\.fromList\(\(ArrayList<Object>\) readValue\(buffer\)\);' ,
  'case (byte) 140:' + "`r`n" + '          return PigeonQuerySnapshot.fromList((ArrayList<Object>) readValue(buffer));'

$content = $content -replace `
  'case \(byte\) 139:\s+return PigeonSnapshotMetadata\.fromList\(\(ArrayList<Object>\) readValue\(buffer\)\);' ,
  'case (byte) 141:' + "`r`n" + '          return PigeonSnapshotMetadata.fromList((ArrayList<Object>) readValue(buffer));'

$content = $content -replace `
  'case \(byte\) 140:\s+return PigeonTransactionCommand\.fromList\(\(ArrayList<Object>\) readValue\(buffer\)\);' ,
  'case (byte) 142:' + "`r`n" + '          return PigeonTransactionCommand.fromList((ArrayList<Object>) readValue(buffer));'

# Fix writeValue: shift write codes 137-140 to 139-142
$content = $content -replace 'value instanceof PigeonQueryParameters\) \{(\s+)stream\.write\(137\)',
  'value instanceof PigeonQueryParameters) {$1stream.write(139)'

$content = $content -replace 'value instanceof PigeonQuerySnapshot\) \{(\s+)stream\.write\(138\)',
  'value instanceof PigeonQuerySnapshot) {$1stream.write(140)'

$content = $content -replace 'value instanceof PigeonSnapshotMetadata\) \{(\s+)stream\.write\(139\)',
  'value instanceof PigeonSnapshotMetadata) {$1stream.write(141)'

$content = $content -replace 'value instanceof PigeonTransactionCommand\) \{(\s+)stream\.write\(140\)',
  'value instanceof PigeonTransactionCommand) {$1stream.write(142)'

Set-Content $file $content -Encoding UTF8
Write-Host "Patch applied. Now run: flutter pub get"
