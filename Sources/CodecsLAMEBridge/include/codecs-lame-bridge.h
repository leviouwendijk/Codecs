#ifndef CODECS_LAME_BRIDGE_H
#define CODECS_LAME_BRIDGE_H

#ifdef __cplusplus
extern "C" {
#endif

typedef struct codecs_lame_handle codecs_lame_handle;
codecs_lame_handle *codecs_lame_open(const char *path, int sample_rate, int channels, int vbr_quality);
int codecs_lame_append(codecs_lame_handle *handle, const float *interleaved, int frames);
int codecs_lame_finish(codecs_lame_handle *handle);
void codecs_lame_destroy(codecs_lame_handle *handle);

#ifdef __cplusplus
}
#endif
#endif
