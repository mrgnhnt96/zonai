/*
 * Minimal streaming .xz decoder: reads a .xz stream on stdin, writes the
 * decoded bytes to stdout. Nothing else -- no CLI flags, no encoding.
 *
 * This exists so tool/ci/package_fat_binary.sh can embed a decompressor
 * for each platform inside the zonai fat binary itself, instead of relying
 * on the end user having `xz` installed. See README.md in this directory
 * for the exact build recipe used to produce the committed binaries
 * (linux-x64, linux-arm64, macos-arm64, macos-x64) and how to verify or
 * regenerate them.
 */
#include <lzma.h>
#include <stdio.h>
#include <stdint.h>

int main(void) {
    lzma_stream strm = LZMA_STREAM_INIT;
    if (lzma_stream_decoder(&strm, UINT64_MAX, 0) != LZMA_OK) {
        fprintf(stderr, "decode_xz: failed to init decoder\n");
        return 1;
    }

    static uint8_t inbuf[65536];
    static uint8_t outbuf[65536];
    lzma_action action = LZMA_RUN;

    strm.next_in = NULL;
    strm.avail_in = 0;
    strm.next_out = outbuf;
    strm.avail_out = sizeof(outbuf);

    for (;;) {
        if (strm.avail_in == 0) {
            size_t n = fread(inbuf, 1, sizeof(inbuf), stdin);
            strm.next_in = inbuf;
            strm.avail_in = n;
            if (feof(stdin)) {
                action = LZMA_FINISH;
            }
        }

        lzma_ret ret = lzma_code(&strm, action);

        if (strm.avail_out == 0 || ret == LZMA_STREAM_END) {
            fwrite(outbuf, 1, sizeof(outbuf) - strm.avail_out, stdout);
            strm.next_out = outbuf;
            strm.avail_out = sizeof(outbuf);
        }

        if (ret == LZMA_STREAM_END) {
            break;
        }
        if (ret != LZMA_OK) {
            fprintf(stderr, "decode_xz: decode error %d\n", ret);
            return 1;
        }
    }

    return 0;
}
