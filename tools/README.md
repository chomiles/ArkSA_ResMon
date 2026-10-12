# Build tools

Run from the repository root with Python and Pillow installed:

```powershell
python tools/build_portable.py
python tools/build_exe.py
```

`ArkResmon.cs` hosts the Windows PowerShell engine and embeds the runtime and GIFs. `CpuSampler.cs` reads total CPU usage using Windows `GetSystemTimes`.
