#include "codecs-lame-bridge.h"
#include <lame.h>
#include <stdio.h>
#include <stdlib.h>
#include <limits.h>

struct codecs_lame_handle {
    lame_t encoder;
    FILE *file;
    int channels;
    int finished;
};

void codecs_lame_destroy(codecs_lame_handle *handle) {
    if (!handle) return;
    if (handle->file) fclose(handle->file);
    if (handle->encoder) lame_close(handle->encoder);
    free(handle);
}

static codecs_lame_handle *codecs_lame_open_configured(
    const char *path, int sample_rate, int channels, int value, int use_cbr
) {
    if (!path || sample_rate <= 0 || (channels != 1 && channels != 2)) return NULL;
    codecs_lame_handle *handle = calloc(1, sizeof(*handle));
    if (!handle) return NULL;
    handle->encoder = lame_init();
    if (!handle->encoder) { codecs_lame_destroy(handle); return NULL; }
    handle->channels = channels;
    int encoding_status;
    if (use_cbr) {
        encoding_status = lame_set_VBR(handle->encoder, vbr_off) < 0
            || lame_set_brate(handle->encoder, value) < 0;
    } else {
        encoding_status = lame_set_VBR(handle->encoder, vbr_mtrh) < 0
            || lame_set_VBR_q(handle->encoder, value) < 0;
    }
    if (lame_set_num_channels(handle->encoder, channels) < 0 ||
        lame_set_in_samplerate(handle->encoder, sample_rate) < 0 ||
        encoding_status || lame_init_params(handle->encoder) < 0) {
        codecs_lame_destroy(handle);
        return NULL;
    }
    handle->file = fopen(path, "wb+");
    if (!handle->file) { codecs_lame_destroy(handle); return NULL; }
    return handle;
}

codecs_lame_handle *codecs_lame_open(const char *path, int sample_rate, int channels, int vbr_quality) {
    if (vbr_quality < 0 || vbr_quality > 9) return NULL;
    return codecs_lame_open_configured(path, sample_rate, channels, vbr_quality, 0);
}

codecs_lame_handle *codecs_lame_open_cbr(const char *path, int sample_rate, int channels, int bitrate_kbps) {
    if (bitrate_kbps != 320) return NULL;
    return codecs_lame_open_configured(path, sample_rate, channels, bitrate_kbps, 1);
}

int codecs_lame_append(codecs_lame_handle *handle, const float *interleaved, int frames) {
    if (!handle || !handle->file || handle->finished || !interleaved || frames < 0) return -1;
    for (int position = 0; position < frames;) {
        int count = frames - position;
        if (count > 4096) count = 4096;
        unsigned char bytes[16384];
        const float *pcm = interleaved + (size_t)position * handle->channels;
        int size = handle->channels == 1
            ? lame_encode_buffer_ieee_float(handle->encoder, pcm, pcm, count, bytes, sizeof(bytes))
            : lame_encode_buffer_interleaved_ieee_float(handle->encoder, pcm, count, bytes, sizeof(bytes));
        if (size < 0) return -2;
        if (size > 0 && fwrite(bytes, 1, (size_t)size, handle->file) != (size_t)size) return -3;
        position += count;
    }
    return 0;
}

int codecs_lame_finish(codecs_lame_handle *handle) {
    if (!handle || !handle->file || handle->finished) return -1;
    handle->finished = 1;
    unsigned char bytes[16384];
    int size = lame_encode_flush(handle->encoder, bytes, sizeof(bytes));
    if (size < 0) return -2;
    if (size > 0 && fwrite(bytes, 1, (size_t)size, handle->file) != (size_t)size) return -3;
    lame_mp3_tags_fid(handle->encoder, handle->file);
    int status = fflush(handle->file);
    if (ferror(handle->file)) status = -1;
    if (fclose(handle->file) != 0) status = -1;
    handle->file = NULL;
    return status == 0 ? 0 : -4;
}
