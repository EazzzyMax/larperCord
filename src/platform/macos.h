#ifndef LARPERCORD_MACOS_H
#define LARPERCORD_MACOS_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

void larper_macos_init(void);
bool larper_macos_executable_path(char *buffer, size_t capacity);
uint64_t larper_macos_resident_kb(void);

/// Enfileira uma notificação local do macOS. Fora de um app bundle, não faz
/// nada: a versão de linha de comando não deve pedir permissão ao usuário.
void larper_macos_notify(const char *title, const char *body);

/// Pede ao app para mostrar a janela quando o Dock reabrir o aplicativo.
void larper_macos_install_reopen(void (*show_window)(void));

#ifdef __cplusplus
}
#endif

#endif
