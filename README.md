# Video Rotate Portable

Video Rotate Portable is a small Windows GUI for adding video rotation metadata without re-encoding.

![Video Rotate Portable icon](RotateIcon.png)

## Features

- Portable Windows app
- Batch file queue
- Per-file rotation assignment: 0, 90, 270, 180
- English/Korean UI toggle
- Output beside each original file or to a selected folder
- Stream copy operation, so video/audio are not re-encoded
- Includes FFmpeg in the portable release package

## Usage

1. Add video files or a folder.
2. Select rows manually or click **Select/Clear All**.
3. Click **90 / 270 / 180** to assign rotation to selected files.
4. Choose the output location.
5. Click **Start**.

Files left at rotation `0` are skipped. Completed files are skipped if you click Start again.

## Rotation Hints

The app shows separate hints for MKV and MP4 because rotation metadata can be interpreted differently:

- `90`: MKV left, MP4 right
- `270`: MKV right, MP4 left
- `180`: both down

## Build

On Windows with .NET Framework compiler available:

```powershell
$base = "C:\path\to\VideoRotatePortable"
& "C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe" `
  /nologo /target:winexe /platform:anycpu `
  /win32icon:"$base\RotateIcon.ico" `
  /out:"$base\VideoRotatePortable.exe" `
  /reference:System.Windows.Forms.dll `
  "$base\VideoRotatePortable.cs"
```

The executable is a small launcher for `RotateTagTool.ps1`.

## FFmpeg

The source repository does not vendor FFmpeg. The portable release package includes `tools\ffmpeg.exe`.

FFmpeg is a separate open-source project:

- https://ffmpeg.org/
- https://www.gyan.dev/ffmpeg/builds/

## License

This project is released under the MIT License. FFmpeg is distributed under its own license.
