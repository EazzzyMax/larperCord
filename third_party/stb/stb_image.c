// Só os formatos que o Discord manda (WebP fica com a libwebp, em ui/images.zig).
#define STB_IMAGE_IMPLEMENTATION
#define STBI_ONLY_PNG
#define STBI_ONLY_JPEG
#define STBI_ONLY_GIF
#define STBI_ONLY_BMP
#define STBI_NO_STDIO
#define STBI_NO_LINEAR
#define STBI_NO_HDR
// Nada maior que 8192×8192: uma imagem pequena comprimida não pode pedir
// gigabytes ao decodificar (o padrão do stb é 2^24 por lado).
#define STBI_MAX_DIMENSIONS 8192
#include "stb_image.h"

// --- larperCord: GIF quadro a quadro -------------------------------------
// O stbi_load_gif_from_memory guarda todos os quadros em tamanho cheio (um
// GIF de 300 quadros passa fácil de 200 MB). Aqui cada quadro vai para o
// callback assim que sai, e só os dois últimos ficam guardados (o descarte
// "restaurar ao anterior" precisa do quadro de dois atrás).
typedef int (*larper_gif_cb)(void *ud, const unsigned char *rgba, int w, int h, int delay_ms);

// Um quadro por vez, retomável (para tocar decodificando aos poucos, em
// ui/gif_stream.zig). `data` precisa durar até o close.
typedef struct larper_gif {
   stbi__context s;
   stbi__gif g;
   stbi_uc *prev, *prev2;
   size_t stride;
   int comp, n;
} larper_gif;

larper_gif *larper_gif_open(const unsigned char *data, int len)
{
   larper_gif *it = (larper_gif *) STBI_MALLOC(sizeof(larper_gif));
   if (!it) return 0;
   memset(it, 0, sizeof(*it));
   stbi__start_mem(&it->s, data, len);
   if (!stbi__gif_test(&it->s)) {
      STBI_FREE(it);
      return 0;
   }
   return it;
}

// O próximo quadro (RGBA w×h, válido até a próxima chamada). NULL: acabou ou erro.
const unsigned char *larper_gif_next(larper_gif *it, int *w, int *h, int *delay_ms)
{
   stbi_uc *u = stbi__gif_load_next(&it->s, &it->g, &it->comp, 4, it->n >= 2 ? it->prev2 : 0);
   if (!u || u == (stbi_uc *) &it->s) return 0;
   if (!it->stride) {
      it->stride = (size_t) it->g.w * it->g.h * 4;
      it->prev = (stbi_uc *) STBI_MALLOC(it->stride);
      it->prev2 = (stbi_uc *) STBI_MALLOC(it->stride);
      if (!it->prev || !it->prev2) return 0;
   }
   {
      stbi_uc *t = it->prev2;
      it->prev2 = it->prev;
      it->prev = t;
      memcpy(it->prev, u, it->stride);
   }
   ++it->n;
   *w = it->g.w;
   *h = it->g.h;
   *delay_ms = it->g.delay;
   return u;
}

void larper_gif_close(larper_gif *it)
{
   if (!it) return;
   STBI_FREE(it->g.out);
   STBI_FREE(it->g.history);
   STBI_FREE(it->g.background);
   STBI_FREE(it->prev);
   STBI_FREE(it->prev2);
   STBI_FREE(it);
}

int larper_gif_frames(const unsigned char *data, int len, larper_gif_cb cb, void *ud)
{
   int w, h, delay, n = 0;
   const unsigned char *u;
   larper_gif *it = larper_gif_open(data, len);
   if (!it) return 0;
   while ((u = larper_gif_next(it, &w, &h, &delay)) != 0) {
      ++n;
      if (!cb(ud, u, w, h, delay)) break;
   }
   larper_gif_close(it);
   return n;
}
