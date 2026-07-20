# Cathohde Run

A high-performance, low-level retro-style terminal arcade game written in Zig, utilizing procedural pseudo-random generation, custom mechanics and deterministic fixed-point integer math.

## Requirements

* Zig Compiler: Version 0.15.2 (or compatible)
* Build System Tools: Standard build utilities for your host OS (Xcode command-line tools / macOS SDK for macOS builds)

## Installation

Builds for Windows, Linux and Apple Sillicon MacOS are available on the [releases page](https://github.com/xgallom/cathode-run/releases).

## Building from source

```bash
git clone https://github.com/xgallom/cathode-run.git
cd cathode-run
zig build -Doptimize=ReleaseFast
./zig-out/bin/cathode-run
```
