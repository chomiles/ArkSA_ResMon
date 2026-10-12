# ArkSA ResMon

[English](README.md) · [한국어](README.ko.md) · [日本語](README.ja.md)

A compact resource monitor for **ARK: Survival Ascended (ASA)** on Windows.

For more headroom in ARK: Survival Ascended, a GPU with **12 GB or more of VRAM is preferable**. The game can also run on an 8 GB GPU, provided graphics settings are adjusted and enough VRAM remains available after background applications are taken into account. Actual requirements vary with settings and the scene being rendered.

Mods, cosmetics, and large bases or crowded mega-tribe environments can substantially increase VRAM demand. If dedicated VRAM becomes insufficient and GPU memory starts spilling into system RAM, frame rates can drop even when GPU core utilization is not particularly high.

**ArkSA ResMon visualizes CPU, RAM, GPU, and VRAM usage, separating ARK's usage from other applications where the available measurements allow.** It helps you see how much of your system is occupied by background workloads and spot signs of memory pressure while playing.

The memory status is an estimate based on usage trends. The tool does not directly measure paging events or frame rates.

![ArkSA ResMon](docs/git.gif)

## Download and run

1. Download [ARK_Resmon.exe](dist/ARK_Resmon.exe) using GitHub's **Download raw file** button, or use the EXE attached to a release when available.
2. Double-click it. Installation, Python, and separate GIF files are not required.
3. Start ARK: Survival Ascended. The monitor connects automatically and reconnects if the game restarts.

Use **KOR / JPN / ENG** in the upper-right corner to change language. Each launch starts in **English**. **Always on top** keeps the monitor visible; close the window or press **Esc** to exit.

## Requirements

- Windows 10/11 x64, .NET Framework, and Windows PowerShell 5.1.
- GPU measurements use Windows GPU performance counters and NVIDIA's `nvidia-smi` from the installed driver. Support for other GPU vendors is limited.
- If a measurement source is unavailable, the corresponding value is shown as **Unavailable**.

## Reading the display

- **Gold:** ARK usage. **Blue-gray:** usage by other applications. Empty space means idle capacity or free memory.
- CPU/GPU percentages refer to the whole device. ARK system RAM is its process working set.
- GPU and VRAM external values marked **≈** are estimates calculated from total usage minus ARK usage. Shared allocations and different sampling sources can affect accuracy.
- Large memory values use GiB, displayed as `GB`; detailed values use MiB, displayed as `MB`.
- Memory states: **Waiting**, **Warming up**, **No signs**, **Memory pressure**, **Swap suspected**, and **Unavailable**. Shared GPU memory alone does not prove swapping.

## Source and build

`monitor.ps1` contains the monitoring logic and multilingual WinForms UI. `run.bat` runs it directly. `gifs/` contains the four status animations.

To build the portable package and single-file EXE, install Python and the development dependency, then run:

```powershell
python -m pip install -r requirements-dev.txt
python tools/build_portable.py
python tools/build_exe.py
```

The EXE uses the Windows PowerShell engine in process and embeds the runtime source and GIFs. The build uses the Windows .NET Framework C# compiler; no executable packer or obfuscation is used.

Verification:

```powershell
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\monitor.ps1 -LogicTest
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\tests\Test-Ui.ps1
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\tests\Test-Portable.ps1
```

These cover memory-state logic, language switching and layout, portable extraction, live measurements, and GIF playback. The portable test requires NVIDIA measurements to be available.
