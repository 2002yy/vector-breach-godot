"""Compile the diagnostic hook using an existing extracted VRF runtime, offline."""

import argparse
import subprocess
from pathlib import Path


def build(dotnet, compiler, references, output, source=None):
    if output.exists():
        raise FileExistsError("Existing bridge preserved")
    required = [
        references / name
        for name in (
            "System.Private.CoreLib.dll",
            "ValveResourceFormat.dll",
            "ValveKeyValue.dll",
            "SkiaSharp.dll",
        )
    ]
    if not all(path.is_file() for path in [dotnet, compiler, *required]):
        raise FileNotFoundError(
            "Expected existing .NET compiler and extracted Source2Viewer assemblies"
        )
    source = source or Path(__file__).resolve().parent / "native/SourceLightingDump.cs"
    libraries = sorted(references.glob("System.*.dll")) + required[1:]
    arguments = [
        str(dotnet),
        str(compiler),
        "/nologo",
        "/target:library",
        "/langversion:12",
        "/nostdlib+",
        "/out:" + str(output),
        *["/reference:" + str(path) for path in libraries],
        str(source),
    ]
    output.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(arguments, check=True, timeout=60)


def main():
    parser = argparse.ArgumentParser()
    for name in ("dotnet", "compiler", "references", "output"):
        parser.add_argument("--" + name, type=Path, required=True)
    parser.add_argument("--source", type=Path)
    args = parser.parse_args()
    build(
        **{key: value.resolve() if value else None for key, value in vars(args).items()}
    )
    print("SOURCE_LIGHTING_BRIDGE_BUILT", args.output)


if __name__ == "__main__":
    main()
