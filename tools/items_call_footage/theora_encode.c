/* A minimal Ogg Theora encoder: raw I420 frames on stdin, an .ogv on the output file. ffmpeg here has no libtheora, so record.mjs pipes its frames through this (libtheora + libogg).
 *   theora_encode <width> <height> <fps_num> <fps_den> <quality 0-63> <out.ogv>   < frames.i420
 * Build: clang -O2 -o theora_encode theora_encode.c -I/opt/homebrew/include -L/opt/homebrew/lib -ltheoraenc -ltheoradec -logg   (brew install theora)
 * The structure follows libtheora's encoder_example; a frame is width*height luma then two (width/2)*(height/2) chroma planes, the picture is padded to a multiple of 16. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ogg/ogg.h>
#include <theora/theoraenc.h>

static int read_frame(FILE *in, int w, int h, unsigned char *planes[3], int pitch[3], int fh[3]) {
    int cw = w / 2, ch = h / 2;
    int sizes_w[3] = { w, cw, cw }, sizes_h[3] = { h, ch, ch };
    for (int p = 0; p < 3; p++) {
        for (int row = 0; row < sizes_h[p]; row++) {
            if (fread(planes[p] + (size_t)row * pitch[p], 1, sizes_w[p], in) != (size_t)sizes_w[p]) return 0;
            for (int x = sizes_w[p]; x < pitch[p]; x++) planes[p][(size_t)row * pitch[p] + x] = planes[p][(size_t)row * pitch[p] + sizes_w[p] - 1];
        }
        for (int row = sizes_h[p]; row < fh[p]; row++) memcpy(planes[p] + (size_t)row * pitch[p], planes[p] + (size_t)(sizes_h[p] - 1) * pitch[p], pitch[p]);
    }
    return 1;
}

static void write_page(FILE *out, ogg_page *page) {
    fwrite(page->header, 1, page->header_len, out);
    fwrite(page->body, 1, page->body_len, out);
}

int main(int argc, char **argv) {
    if (argc != 7) { fprintf(stderr, "usage: %s width height fps_num fps_den quality out.ogv\n", argv[0]); return 2; }
    int w = atoi(argv[1]), h = atoi(argv[2]), fps_n = atoi(argv[3]), fps_d = atoi(argv[4]), quality = atoi(argv[5]);
    if (w < 16 || h < 16 || (w & 1) || (h & 1)) { fprintf(stderr, "even sizes of at least 16 px, please\n"); return 2; }
    FILE *out = fopen(argv[6], "wb");
    if (!out) { perror(argv[6]); return 1; }

    int fw = (w + 15) & ~15, fh = (h + 15) & ~15;
    th_info info;
    th_info_init(&info);
    info.frame_width = fw; info.frame_height = fh; info.pic_width = w; info.pic_height = h; info.pic_x = 0; info.pic_y = 0;
    info.fps_numerator = fps_n; info.fps_denominator = fps_d; info.aspect_numerator = 1; info.aspect_denominator = 1;
    info.colorspace = TH_CS_UNSPECIFIED; info.pixel_fmt = TH_PF_420; info.target_bitrate = 0; info.quality = quality; info.keyframe_granule_shift = 6;
    th_enc_ctx *enc = th_encode_alloc(&info);
    th_info_clear(&info);
    if (!enc) { fprintf(stderr, "th_encode_alloc failed\n"); return 1; }
    int keyframe_max = 90; /* a keyframe at least every 3 s at 30 fps: the player can loop */
    th_encode_ctl(enc, TH_ENCCTL_SET_KEYFRAME_FREQUENCY_FORCE, &keyframe_max, sizeof(keyframe_max));

    ogg_stream_state stream;
    ogg_stream_init(&stream, 0x5eed);
    th_comment comment;
    th_comment_init(&comment);
    ogg_packet packet;
    ogg_page page;
    if (th_encode_flushheader(enc, &comment, &packet) <= 0) return 1;
    ogg_stream_packetin(&stream, &packet);
    if (ogg_stream_pageout(&stream, &page) != 1) return 1;
    write_page(out, &page);
    for (;;) {
        int more = th_encode_flushheader(enc, &comment, &packet);
        if (more < 0) return 1;
        if (more == 0) break;
        ogg_stream_packetin(&stream, &packet);
    }
    while (ogg_stream_flush(&stream, &page)) write_page(out, &page);

    int pitch[3] = { fw, fw / 2, fw / 2 }, rows[3] = { fh, fh / 2, fh / 2 };
    unsigned char *buffers[2][3];
    for (int b = 0; b < 2; b++)
        for (int p = 0; p < 3; p++) buffers[b][p] = calloc((size_t)pitch[p] * rows[p], 1);
    th_ycbcr_buffer ycbcr;
    int current = 0, frames = 0;
    int have = read_frame(stdin, w, h, buffers[current], pitch, rows);
    while (have) {
        int next = current ^ 1;
        int more = read_frame(stdin, w, h, buffers[next], pitch, rows);
        for (int p = 0; p < 3; p++) {
            ycbcr[p].width = pitch[p]; ycbcr[p].height = rows[p]; ycbcr[p].stride = pitch[p]; ycbcr[p].data = buffers[current][p];
        }
        if (th_encode_ycbcr_in(enc, ycbcr) != 0) { fprintf(stderr, "th_encode_ycbcr_in failed\n"); return 1; }
        while (th_encode_packetout(enc, !more, &packet) > 0) {
            ogg_stream_packetin(&stream, &packet);
            while (ogg_stream_pageout(&stream, &page)) write_page(out, &page);
        }
        frames++;
        current = next;
        have = more;
    }
    while (ogg_stream_flush(&stream, &page)) write_page(out, &page);
    th_encode_free(enc);
    ogg_stream_clear(&stream);
    th_comment_clear(&comment);
    fclose(out);
    fprintf(stderr, "theora_encode: %d frames\n", frames);
    return frames > 0 ? 0 : 1;
}
