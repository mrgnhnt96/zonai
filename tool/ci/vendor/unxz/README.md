# Vendored static .xz decoders

Four tiny, dependency-free binaries that decode a `.xz` stream on stdin to
stdout, nothing else. `tool/ci/package_fat_binary.sh` embeds one of these
alongside each platform's compressed zonai binary in the fat file, so a user
running it never needs `xz` installed themselves -- only the CI machine that
*builds* the release needs `xz` (to produce the compressed payloads).

| file          | size     | linkage                                              |
|----------------|----------|-------------------------------------------------------|
| `linux-x64`    | ~300 KiB | fully static (musl, `-static -no-pie`, no `PT_INTERP`) |
| `linux-arm64`  | ~327 KiB | fully static (musl, `-static -no-pie`, no `PT_INTERP`) |
| `macos-arm64`  | ~72 KiB  | dynamic only against `/usr/lib/libSystem.B.dylib`      |
| `macos-x64`    | ~90 KiB  | dynamic only against `/usr/lib/libSystem.B.dylib`      |

`libSystem.B.dylib` ships on every macOS install (it's the base
syscall/libc layer) -- that's as close to "no dependency" as macOS static
linking gets; Apple does not support fully static Mach-O executables.
Verified: the two Linux binaries run unmodified on both musl (Alpine) and
glibc (Ubuntu) containers with no `xz`/`liblzma` installed on either.

## Build recipe

Source is `decode_xz.c` in this directory (also embedded verbatim above).
Built against `xz` (liblzma) 5.6.2 from
<https://github.com/tukaani-project/xz/releases/tag/v5.6.2>.

**Linux (either arch), via Alpine for musl static linking:**

```sh
docker run --rm -v "$PWD":/out alpine:latest sh -c '
  apk add --no-cache build-base wget tar
  cd /tmp
  wget -q https://github.com/tukaani-project/xz/releases/download/v5.6.2/xz-5.6.2.tar.gz
  tar xzf xz-5.6.2.tar.gz
  cd xz-5.6.2
  ./configure --disable-shared --enable-static --disable-nls --disable-doc
  make -j"$(nproc)"
  gcc -static -no-pie -O2 -o /out/decode_xz /path/to/decode_xz.c \
    -Isrc/liblzma/api src/liblzma/.libs/liblzma.a
'
```

Run the same command with `--platform linux/amd64` (or `linux/arm64`) to
target the other architecture; Docker's emulation handles the cross build.

**macOS (either arch), native clang, no Docker needed:**

```sh
curl -sL https://github.com/tukaani-project/xz/releases/download/v5.6.2/xz-5.6.2.tar.gz | tar xz
cd xz-5.6.2
# arm64 (native on Apple Silicon):
./configure --disable-shared --enable-static --disable-nls --disable-doc
make -j"$(sysctl -n hw.ncpu)"
clang -arch arm64 -O2 -Isrc/liblzma/api -o unxz-macos-arm64 \
  /path/to/decode_xz.c src/liblzma/.libs/liblzma.a

# x64 (cross-compiled, no Rosetta required to build):
make distclean
CC="clang -arch x86_64" ./configure --disable-shared --enable-static \
  --disable-nls --disable-doc --host=x86_64-apple-darwin
make -j"$(sysctl -n hw.ncpu)"
clang -arch x86_64 -O2 -Isrc/liblzma/api -o unxz-macos-x64 \
  /path/to/decode_xz.c src/liblzma/.libs/liblzma.a
```

## Verifying a rebuild matches

These aren't reproducible bit-for-bit across toolchain versions, so don't
diff a fresh build against the committed binary. Instead confirm behavior:

```sh
echo hello | xz -9 | ./linux-x64   # (or whichever platform) -> prints "hello"
```

and check linkage: `readelf -l <binary> | grep -i interp` should print
nothing for the Linux binaries (fully static); `otool -L <binary>` should
list only `libSystem.B.dylib` for the macOS ones.
