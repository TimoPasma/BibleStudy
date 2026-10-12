$ErrorActionPreference = 'Stop'
[xml]$doc = Get-Content -Raw -Encoding utf8 (Join-Path $PSScriptRoot '..\bbox.html')
$ns = [Xml.XmlNamespaceManager]::new($doc.NameTable)
$ns.AddNamespace('h', 'http://www.w3.org/1999/xhtml')

function Line-Text($group) {
  (($group.Group | Sort-Object x | ForEach-Object t) -join ' ').Trim()
}

function Is-Noise([string]$text) {
  $text = $text.Trim()
  return $text -match '^\d+\s+:\d+$' -or
         $text -match '^[\d\s|~]+$' -or
         $text -match '^\([a-z]+\)$' -or
         $text -match '^(?:(?:id\.|c)\s*)+$'
}

function Assign-Words($groups, [double[]]$starts) {
  $cells = [object[]]::new($starts.Count)
  for ($ci = 0; $ci -lt $starts.Count; $ci++) { $cells[$ci] = [Collections.Generic.List[string]]::new() }
  foreach ($group in $groups) {
    foreach ($word in ($group.Group | Sort-Object x)) {
      $best = 0
      for ($i = 0; $i -lt $starts.Count; $i++) {
        if ($word.x -ge ($starts[$i] - 2.2)) { $best = $i } else { break }
      }
      $cells[$best].Add($word.t)
    }
  }
  return @($cells | ForEach-Object { (($_ | ForEach-Object { $_ }) -join ' ').Trim() })
}

$verseMap = @{}
$currentVerse = 0
$pageNumber = 0
foreach ($page in $doc.SelectNodes('//h:page', $ns)) {
  $pageNumber++
  $words = @($page.SelectNodes('.//h:word', $ns) | ForEach-Object {
    [pscustomobject]@{
      y = [Math]::Round([double]$_.yMin, 1)
      x = [double]$_.xMin
      t = $_.InnerText
    }
  })
  $groups = @($words | Group-Object y | Sort-Object { [double]$_.Name })
  for ($gi = 0; $gi -lt $groups.Count; $gi++) {
    $greekText = Line-Text $groups[$gi]
    if ($greekText -notmatch '\p{IsGreek}') { continue }

    $strongIndex = $gi + 1
    while ($strongIndex -lt $groups.Count -and (Line-Text $groups[$strongIndex]) -notmatch '\[?G\d+') { $strongIndex++ }
    if ($strongIndex -ge $groups.Count) { continue }

    for ($ri = $gi; $ri -lt $strongIndex; $ri++) {
      $ref = Line-Text $groups[$ri]
      if ($ref -match '^1\s+:(\d+)$') { $currentVerse = [int]$Matches[1] }
    }
    if ($currentVerse -lt 1) { continue }

    $greekWords = @($groups[$gi].Group | Where-Object { $_.t -ne 'Mt' } | Sort-Object x)
    $starts = [double[]]@($greekWords | ForEach-Object x)
    if (-not $starts.Count) { continue }

    $middle = @()
    for ($mi = $gi + 1; $mi -lt $strongIndex; $mi++) {
      $txt = Line-Text $groups[$mi]
      if (-not (Is-Noise $txt)) { $middle += $groups[$mi] }
    }
    if ($middle.Count -lt 4) { continue }

    $translitGroup = $middle[0]
    $morphAt = -1
    for ($mi = $middle.Count - 1; $mi -gt 1; $mi--) {
      $candidate = Line-Text $middle[$mi]
      if ($candidate -match '(?:^|\s)(zn|vgw|wa|wd|wv|wo|vp|bn|l_|vzt|bijw|part|zo|vr|va|wg|vw)(?:\s|$)') { $morphAt = $mi; break }
    }
    if ($morphAt -lt 0) { $morphAt = $middle.Count - 1 }
    $glossAt = $morphAt - 1
    while ($glossAt -gt 1 -and (Line-Text $middle[$glossAt]) -match '^(?:(?:id\.|c)\s*)+$') { $glossAt-- }

    $dutchGroups = @($middle[1..($glossAt - 1)])
    $glossGroups = @($middle[$glossAt..($morphAt - 1)] | Where-Object { (Line-Text $_) -notmatch '^(id\.|c)$' })
    $translit = Assign-Words @($translitGroup) $starts
    $dutch = Assign-Words $dutchGroups $starts
    $gloss = Assign-Words $glossGroups $starts
    $morph = Assign-Words @($middle[$morphAt]) $starts
    $strong = Assign-Words @($groups[$strongIndex]) $starts

    $tokens = @()
    for ($ti = 0; $ti -lt $greekWords.Count; $ti++) {
      $tokens += [ordered]@{
        gr = $greekWords[$ti].t
        tr = $translit[$ti]
        nl = $dutch[$ti]
        gloss = $gloss[$ti]
        morph = $morph[$ti]
        strong = $strong[$ti]
      }
    }
    $key = "v$currentVerse"
    if (-not $verseMap.Contains($key)) { $verseMap[$key] = [Collections.Generic.List[object]]::new() }
    $verseMap[$key].Add(@($tokens))
    $gi = $strongIndex
  }
}

$verses = foreach ($entry in ($verseMap.GetEnumerator() | Sort-Object { [int]$_.Key.Substring(1) })) {
  [ordered]@{ n = [int]($entry.Key.Substring(1)); segments = @($entry.Value) }
}
$json = $verses | ConvertTo-Json -Depth 8 -Compress
"const verses=$json;"
