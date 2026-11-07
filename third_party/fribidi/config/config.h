/* config.h do GNU FriBidi no larperCord: o que o meson do pacote geraria aqui,
 * escrito à mão (ver ../README). Só o que lib/ usa. */
#ifndef LARPER_FRIBIDI_CONFIG_H
#define LARPER_FRIBIDI_CONFIG_H

#define HAVE_MEMMOVE 1
#define HAVE_MEMSET 1
#define HAVE_STDLIB_H 1
#define HAVE_STRING_H 1
#define HAVE_MEMORY_H 0
#define STDC_HEADERS 1
#define HAVE_STRINGIZE 1

/* As listas de trechos que o algoritmo monta saem de uma arena fixa do
 * src/ui/bidi.zig, zerada a cada linha: desenhar texto árabe não chama o
 * malloc a cada quadro. Passou do tamanho da arena, cai no malloc. */
#include <stddef.h>
void *larper_fribidi_malloc(size_t size);
void larper_fribidi_free(void *ptr);
#define fribidi_malloc larper_fribidi_malloc
#define fribidi_free larper_fribidi_free

#endif
