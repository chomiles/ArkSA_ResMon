"""Build a single WinForms EXE; Windows' own PowerShell engine is hosted in process."""
from pathlib import Path
import hashlib
import json
import re
import subprocess
import zipfile
from PIL import Image

root = Path(__file__).resolve().parents[1]
dist = root / 'dist'
build = dist / 'exe-build'
build.mkdir(parents=True, exist_ok=True)
runtime = (dist / 'ARK_RESMON_Portable' / 'monitor.ps1').read_text(encoding='utf-8-sig')
runtime = runtime.replace('$script:CharacterRoot = $PSScriptRoot', '$script:CharacterRoot = [AppDomain]::CurrentDomain.BaseDirectory')
runtime = runtime.replace("$tips.SetToolTip($avatar, '64×64 상태 캐릭터 · gifs 폴더의 fun / cheer / sick / dizzy')", "$tips.SetToolTip($avatar, '64×64 상태 캐릭터 · fun / cheer / sick / dizzy')")
needle = '                    break\n                } catch { }\n            }\n        }\n    }\n}\n\nfunction Set-AvatarState'
replacement = '''                    break
                } catch { }
            }
        }
        if (-not $script:AvatarImages.ContainsKey($state)) {
            $asset = [ArkResmon.EmbeddedImages]::Load("${name}_64x64.gif")
            if ($asset) { $script:AvatarImages[$state] = $asset }
        }
    }
}

function Set-AvatarState'''
assert needle in runtime
runtime = runtime.replace(needle, replacement, 1)
runtime = runtime.replace("    $form.Text = 'ARK Resmon'", "    $form.Text = 'ARK Resmon'\n    $form.Icon = [Drawing.Icon]::ExtractAssociatedIcon([Reflection.Assembly]::GetEntryAssembly().Location)", 1)
runtime = re.sub(r'\nexit 0\s*$', '\n', runtime)
runtime_path = build / 'runtime.ps1'
runtime_path.write_text(runtime, encoding='utf-8-sig', newline='\r\n')

icon_path = build / 'ArkResmon.ico'
with Image.open(root / 'gifs' / 'fun_64x64.gif') as image:
    image.seek(0)
    image.convert('RGBA').save(icon_path, format='ICO', sizes=[(16, 16), (32, 32), (48, 48), (64, 64)], bitmap_format='png')

compiler = Path(r'C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe')
automation = Path(r'C:\Windows\Microsoft.NET\assembly\GAC_MSIL\System.Management.Automation\v4.0_3.0.0.0__31bf3856ad364e35\System.Management.Automation.dll')
assert compiler.is_file() and automation.is_file()
exe = dist / 'ARK_Resmon.exe'
command = [str(compiler), '/nologo', '/target:winexe', '/platform:x64', '/optimize+', '/debug-', '/utf8output', '/out:' + str(exe), '/win32icon:' + str(icon_path), '/reference:' + str(automation), '/reference:System.Drawing.dll', '/reference:System.Windows.Forms.dll', '/reference:System.Web.Extensions.dll', '/resource:' + str(runtime_path) + ',ArkResmon.Runtime.ps1']
for name in ('fun_64x64.gif', 'cheer_64x64.gif', 'sick_64x64.gif', 'dizzy_64x64.gif'):
    command.append('/resource:' + str(root / 'gifs' / name) + ',ArkResmon.Gifs.' + name)
command.append(str(root / 'tools' / 'ArkResmon.cs'))
command.append(str(root / 'tools' / 'CpuSampler.cs'))
result = subprocess.run(command, capture_output=True, encoding='utf-8', errors='replace')
if result.returncode:
    raise RuntimeError(result.stdout + result.stderr)

archive = dist / 'ARK_RESMON_EXE.zip'
with zipfile.ZipFile(archive, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=9) as zipped:
    zipped.write(exe, exe.name)
with zipfile.ZipFile(archive) as zipped:
    assert zipped.testzip() is None and zipped.namelist() == [exe.name]
report = {'exe': str(exe), 'exe_bytes': exe.stat().st_size, 'zip': str(archive), 'zip_bytes': archive.stat().st_size, 'exe_sha256': hashlib.sha256(exe.read_bytes()).hexdigest(), 'zip_sha256': hashlib.sha256(archive.read_bytes()).hexdigest(), 'subsystem': 'Windows GUI', 'resources': 'Readable runtime source and four project GIFs', 'architecture': 'x64', 'external_runtime': 'Windows .NET Framework and Windows PowerShell 5.1'}
(dist / 'exe-build-report.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
print(json.dumps(report, ensure_ascii=False, indent=2))
