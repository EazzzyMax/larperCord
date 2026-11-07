#include <mach/mach.h>
#include <mach-o/dyld.h>
#include <stdint.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <limits.h>
#include <unistd.h>
#include <signal.h>
#include "macos.h"

bool larper_macos_executable_path(char *buffer, size_t capacity) {
    if (capacity > UINT32_MAX || capacity == 0) return false;
    uint32_t size = (uint32_t)capacity;
    return _NSGetExecutablePath(buffer, &size) == 0;
}

uint64_t larper_macos_resident_kb(void) {
    mach_task_basic_info_data_t info;
    mach_msg_type_number_t count = MACH_TASK_BASIC_INFO_COUNT;
    if (task_info(mach_task_self(), MACH_TASK_BASIC_INFO,
                  (task_info_t)&info, &count) != KERN_SUCCESS) return 0;
    return info.resident_size / 1024;
}

void larper_macos_init(void) {
    // SIG_IGN é um ponteiro de função no Darwin; fica em C para o translate-c.
    (void)signal(SIGPIPE, SIG_IGN);
    // Usa a configuração do bundle, sem substituir a escolhida pelo usuário.
    if (getenv("FONTCONFIG_FILE")) return;
    char executable[PATH_MAX], resolved[PATH_MAX], config[PATH_MAX];
    uint32_t size = sizeof(executable);
    if (_NSGetExecutablePath(executable, &size) || !realpath(executable, resolved)) return;
    char *slash = strrchr(resolved, '/');
    if (!slash) return;
    *slash = '\0';
    int n = snprintf(config, sizeof(config), "%s/../Resources/fonts.conf", resolved);
    if (n <= 0 || (size_t)n >= sizeof(config) || access(config, R_OK)) return;
    setenv("FONTCONFIG_FILE", config, 0);
}
