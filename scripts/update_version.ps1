param(
    [string]$src_dir, # ソースディレクトリのパス
    [string]$repo_list_csv, # リポジトリ一覧のファイルパス
    [int]$update_unit # アップデートの単位
)


$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# リポジトリ一覧の読み込み(後々のためにハッシュ化する)
$repositories_csv = Import-Csv $repo_list_csv
$repositories_hash = $repositories_csv |  Group-Object -AsHashTable -AsString -Property PackageName

# cprojファイルのバージョン情報の更新
Push-Location $src_dir
foreach ($dir in $(Get-ChildItem * | ? { $_.PSIsContainer }))
{
    Push-Location $dir
    foreach ($file in $(Get-ChildItem *.csproj -Recurse))
    {
        if($file | Test-Path)
        {
            $xml_doc = [xml](cat $file -enc utf8)
            $xml_nav = $xml_doc.CreateNavigator()
            # ライブラリバージョンの更新
            $libver = $xml_nav.Select("/Project/PropertyGroup/Version")
            $majVer,$minVer,$bldVer,$patchVer = ([string]$libver).Split(".")
            if ($update_unit -band 8)
            {
                $majVer = [string]([int]$majVer + 1);
            }
            if ($update_unit -band 4)
            {
                $minVer = "." + [string]([int]$minVer + 1);
            }
            if ($update_unit -band 2)
            {
                $bldVer = "." + [string]([int]$bldVer + 1);
            }
            if ($update_unit -band 1)
            {
                $patchVer = "." + [string](Get-Date -UFormat "%y%m%d");
            }
            $newver = [string]$majVer + $minVer + $bldVer + $patchVer
            $libver.SetValue($newver);

            # 参照パッケージのバージョン情報の更新
            $nodes = $xml_nav.Select("/Project/ItemGroup/PackageReference")
            While ($nodes.MoveNext()) # MoveNext()メソッドによる値の取り出し
            {
                try
                {
                    $libName = $nodes.Current.getattribute("Include", "")
                    $v=[string](gh release view -R ($repositories_hash[$libName].Repository))
                    $v -match 'tag:\s(?<version>.*?)\s' >> $null
                    $version = $nodes.Current.Select("./@Version")
                    if ($Matches.version)
                    {
                        $version.SetValue($Matches.version)
                        Write-Host [M]$libName reference version: $Matches.version;
                    }
                }
                catch
                {
                
                }
            }
            $xml_doc.Save($file)
        }
        Write-Host ""
    }
    Pop-Location
}
Pop-Location

return $newver
