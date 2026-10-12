"""Build a readable, minimal Windows portable ZIP without an executable packer."""
from pathlib import Path
from io import BytesIO
import hashlib
import json
import re
import zipfile
from PIL import Image

root = Path(__file__).resolve().parents[1]
dist = root / 'dist'
package = dist / 'ARK_RESMON_Portable'
package.mkdir(parents=True, exist_ok=True)
(package / 'gifs').mkdir(exist_ok=True)

source = (root / 'monitor.ps1').read_text(encoding='utf-8-sig')
runtime = source[source.index("$ErrorActionPreference = 'Stop'"):]
runtime = runtime[:runtime.index('function Get-ConsoleCodePage')] + runtime[runtime.index('Add-Type -AssemblyName System.Windows.Forms'):]
start = runtime.index('function Invoke-MemoryLogicTests')
end = runtime.index('\nInitialize-Counters\n', start)
runtime = runtime[:start] + runtime[end + 1:]
for name in ('SelfTest', 'SnapshotPath'):
    runtime, count = re.subn(rf'(?ms)^if \(\${name}\) \{{\n.*?^\}}\n', '', runtime, count=1)
    assert count == 1, name
runtime, count = re.subn(r'(?ms)^function Get-CounterSum\([^\n]*\) \{\n.*?^\}\n', '', runtime, count=1)
assert count == 1
runtime = '\n'.join(line.rstrip() for line in runtime.splitlines() if not line.lstrip().startswith('#') and not any(token in line for token in ('$script:BrushSwapOk', '$script:BrushSwapBad', '$script:ColorSwapOk', '$script:SwapBaselineSamples')))
runtime = re.sub(r'\n{3,}', '\n\n', runtime).strip() + '\n'
runtime = '# ARK Resmon portable runtime. Source: monitor.ps1\n' + runtime
(package / 'monitor.ps1').write_text(runtime, encoding='utf-8-sig', newline='\r\n')

launcher = r'''@echo off
setlocal
title ARK Resmon
pushd "%~dp0"
chcp 65001 >nul
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0monitor.ps1"
set "ERR=%ERRORLEVEL%"
if not "%ERR%"=="0" (
    echo ARK Resmon exited with code %ERR%.
    pause
)
popd
exit /b %ERR%
'''
(package / 'run.bat').write_text(launcher, encoding='ascii', newline='\r\n')
assert not any(byte < 32 and byte not in (9, 10, 13) for byte in (package / 'run.bat').read_bytes())

readme = '''ARK Resmon · 포터블

1. ZIP 전체를 원하는 폴더에 압축 해제합니다.
2. run.bat을 실행합니다. 추가 설치 없이 동작합니다.
3. 우측 상단 KOR / JPN / ENG 버튼으로 언어를 변경합니다. 기본값은 영어입니다.
4. 종료는 창의 X 또는 Esc입니다. 삭제는 폴더를 지우면 됩니다.

지원 환경: Windows 10/11, Windows PowerShell 5.1, .NET Framework,
Windows GPU 성능 카운터와 NVIDIA 드라이버의 nvidia-smi.
NVIDIA가 아닌 GPU에서는 일부 GPU 측정이 지원되지 않습니다.
조직의 보안 정책이나 성능 카운터 권한 제한이 있으면 실행/측정이 제한될 수 있습니다.

캐릭터: gifs 폴더의 64x64 애니메이션 GIF
fun = 대기 / cheer = 실행 중 / sick = 메모리 압박 / dizzy = 스왑 의심
측정 불가 시에는 cheer와 상태 글자가 표시됩니다.
GIF를 교체하려면 모니터를 닫고 교체한 후 재실행하세요.

스왑은 최근 메모리 변화 추세로 추정합니다. 실제 페이징 이벤트를 직접 측정하지 않습니다.
GPU 외부 값의 ≈ 표시는 전체/ARK 측정값 차이로 계산한 추정치입니다.

파일은 읽을 수 있는 PowerShell 소스와 GIF이며 일반 ZIP Deflate로 압축했습니다.
실행 정책 옵션은 실행되는 PowerShell 프로세스에만 적용됩니다.
설치 프로그램, 실행 파일 패커, 난독화, 백신 예외 설정은 포함하지 않습니다.
모든 백신과 모든 버전에서 오탐이 없음을 보증할 수는 없습니다.
'''
(package / 'README.txt').write_text(readme, encoding='utf-8-sig', newline='\r\n')

def fingerprint_animation(data):
    with Image.open(BytesIO(data)) as image:
        frames = []
        loop = image.info.get('loop', None)
        for index in range(image.n_frames):
            image.seek(index)
            rgba = bytearray(image.convert('RGBA').tobytes())
            # RGB values of fully transparent pixels have no visual meaning.
            for offset in range(0, len(rgba), 4):
                if rgba[offset + 3] == 0:
                    rgba[offset:offset + 3] = b'\x00\x00\x00'
            frames.append((image.size, image.info.get('duration', 0), hashlib.sha256(rgba).hexdigest()))
        return (loop, frames)

def optimize_gif(data):
    with Image.open(BytesIO(data)) as image:
        loop = image.info.get('loop', None)
        frames, durations = [], []
        for index in range(image.n_frames):
            image.seek(index)
            assert image.size == (64, 64)
            frames.append(image.convert('RGBA').copy())
            durations.append(image.info.get('duration', 0))
        options = dict(format='GIF', save_all=True, append_images=frames[1:], duration=durations, disposal=2, optimize=True)
        if loop is not None:
            options['loop'] = loop
        out = BytesIO()
        frames[0].save(out, **options)
        candidate = out.getvalue()
        if len(candidate) < len(data) and fingerprint_animation(candidate) == fingerprint_animation(data):
            return candidate, True
        return data, False

report = {'assets': []}
for name in ('fun_64x64.gif', 'cheer_64x64.gif', 'sick_64x64.gif', 'dizzy_64x64.gif'):
    original = (root / 'gifs' / name).read_bytes()
    output, optimized = optimize_gif(original)
    assert fingerprint_animation(output) == fingerprint_animation(original), name
    (package / 'gifs' / name).write_bytes(output)
    report['assets'].append({'name': name, 'original_bytes': len(original), 'portable_bytes': len(output), 'lossless_optimized': optimized, 'frames': len(fingerprint_animation(output)[1])})

archive = dist / 'ARK_RESMON_Portable.zip'
files = [package / name for name in ('run.bat', 'monitor.ps1', 'README.txt')]
files += sorted((package / 'gifs').glob('*.gif'))
assert len(files) == 7
with zipfile.ZipFile(archive, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=9) as zipped:
    for path in files:
        zipped.write(path, path.relative_to(dist).as_posix())
with zipfile.ZipFile(archive) as zipped:
    assert zipped.testzip() is None
    assert len(zipped.namelist()) == 7

report.update({'archive': str(archive), 'zip_bytes': archive.stat().st_size, 'unpacked_bytes': sum(path.stat().st_size for path in files), 'runtime_original_bytes': (root / 'monitor.ps1').stat().st_size, 'runtime_portable_bytes': (package / 'monitor.ps1').stat().st_size, 'zip_sha256': hashlib.sha256(archive.read_bytes()).hexdigest(), 'files': [path.relative_to(dist).as_posix() for path in files]})
(dist / 'build-report.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
print(json.dumps(report, ensure_ascii=False, indent=2))
