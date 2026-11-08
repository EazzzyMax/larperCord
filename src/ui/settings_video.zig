//! Configurações → Chat → Vídeos: o FFmpeg que toca os vídeos aqui no app. Achado
//! sozinho, baixado (Windows) ou numa pasta escolhida à mão; sem ele, o porquê: os
//! nomes procurados, o ffmpeg estático do PATH sem as bibliotecas, uma versão que o
//! app não conhece (platform/ffmpeg.zig, platform/ffmpeg_busca.zig).
const std = @import("std");
const qa = @import("qa.zig");
const i18n = @import("i18n.zig");
const S = @import("settings_state.zig");
const ffmpeg = @import("../platform/ffmpeg.zig");
const busca = @import("../platform/ffmpeg_busca.zig");
const get = @import("../net/ffmpeg_get.zig");
const sys = @import("../platform/sys.zig");

var confirming = false;
/// Esperando a pasta do seletor do sistema.
var picking = false;
/// O seletor fechou sem pasta (o aviso vem da thread do diálogo).
var pick_cancelled = std.atomic.Value(bool).init(false);
/// A última pasta escolhida que não servia, e por quê (ela não é guardada).
var refused: ?busca.Check = null;
/// A pasta nova vale só ao abrir o app de novo: o FFmpeg carregado fica até lá.
var pending_restart = false;

pub fn section(p: anytype) void {
    const ctx = p.ctx;
    p.heading(i18n.tr("Vídeos", "Videos"));
    var buf: [420]u8 = undefined;
    // Sem carregar o FFmpeg só por abrir a página: ele fica na memória depois.
    switch (get.phase()) {
        .downloading, .installing => {
            p.note(if (get.phase() == .downloading) i18n.fmt(&buf, "Baixando o FFmpeg: {d}%", "Downloading FFmpeg: {d}%", .{get.percent()}) else i18n.tr("Instalando o FFmpeg…", "Installing FFmpeg…"));
            return;
        },
        .done => p.note(i18n.tr("FFmpeg instalado. Os vídeos já tocam aqui no app.", "FFmpeg installed. Videos now play in the app.")),
        .failed => p.note(switch (get.failure()) {
            .network => i18n.tr("Não deu para baixar o FFmpeg. Confira a internet e tente de novo.", "Couldn't download FFmpeg. Check your connection and try again."),
            .hash => i18n.tr("O arquivo baixado não bate com o esperado, então nada foi instalado.", "The downloaded file doesn't match what was expected, so nothing was installed."),
            else => i18n.tr("Não deu para gravar o FFmpeg no disco.", "Couldn't write FFmpeg to disk."),
        }),
        .idle => {},
    }
    if (get.phase() == .done) return;
    const known = ffmpeg.known();
    if (known == true) {
        const v = ffmpeg.loadedVersion();
        p.note(switch (ffmpeg.loadedSource()) {
            .chosen => i18n.fmt(&buf, "FFmpeg {d}, da pasta escolhida: os vídeos tocam aqui no app.", "FFmpeg {d}, from the chosen folder: videos play in the app.", .{v}),
            .path => i18n.fmt(&buf, "FFmpeg {d}, de {s} (no PATH): os vídeos tocam aqui no app.", "FFmpeg {d}, from {s} (on PATH): videos play in the app.", .{ v, ffmpeg.loadedDir() }),
            .system => i18n.fmt(&buf, "FFmpeg {d} encontrado: os vídeos tocam aqui no app.", "FFmpeg {d} found: videos play in the app.", .{v}),
        });
        // Tem uma pasta escolhida e o FFmpeg veio de outro lugar: diz por quê.
        if (ffmpeg.loadedSource() != .chosen and ctx.st.settings.ffmpeg_dir.len > 0 and !pending_restart) {
            var dg: ffmpeg.Diag = undefined;
            ffmpeg.diagnosis(&dg);
            var why: [700]u8 = undefined;
            if (dg.chosen) |ch| markedNote(p, dirText(&why, ch, i18n.tr("A pasta escolhida", "The chosen folder")), "ffmpeg-diag:pasta:{s}", .{@tagName(ch)});
            if (dg.failed_file.len > 0) p.note(i18n.fmt(&why, "{s} existe, mas o sistema não conseguiu carregar: {s}", "{s} is there, but the system couldn't load it: {s}", .{ dg.failed_file.slice(), dg.failed_why.slice() }));
            p.note(i18n.tr("Por isso o app usa o FFmpeg que achou em outro lugar.", "So the app uses the FFmpeg it found elsewhere."));
        }
        folderRows(p, false);
        return;
    }
    if (known == null) {
        p.note(i18n.tr("Com o FFmpeg, os vídeos tocam aqui no app. Sem ele, abrem no navegador.", "With FFmpeg, videos play in the app. Without it, they open in the browser."));
        if (p.buttonSoft(i18n.tr("Verificar se tem FFmpeg", "Check for FFmpeg"))) _ = ffmpeg.get();
        folderRows(p, true);
        return;
    }
    p.note(i18n.tr("FFmpeg não encontrado: os vídeos abrem no navegador.", "FFmpeg not found: videos open in the browser."));
    diagnosis(p);
    if (!sys.windows and !get.qa_no_network) {
        p.note(i18n.tr("Instale o pacote ffmpeg do seu sistema (pacman -S ffmpeg, apt install ffmpeg ou dnf install ffmpeg). Se o do sistema for antigo demais, escolha abaixo a pasta de uma versão \"shared\" mais nova.", "Install your system's ffmpeg package (pacman -S ffmpeg, apt install ffmpeg or dnf install ffmpeg). If your system's is too old, choose the folder of a newer \"shared\" build below."));
    } else if (confirming) {
        p.note(i18n.fmt(&buf, "Vai baixar {d} MB de {s}, um projeto de terceiros sem relação com o larperCord. O app confere o SHA-256 do arquivo e guarda só o necessário, cerca de {d} MB em disco. Depois de instalado, o FFmpeg roda dentro do app sempre que um vídeo tocar.", "This downloads {d} MB from {s}, a third-party project unrelated to larperCord. The app checks the file's SHA-256 and keeps only what it needs, about {d} MB on disk. Once installed, FFmpeg runs inside the app whenever a video plays.", .{ get.download_mb, get.source, get.disk_mb }));
        if (p.button(i18n.tr("Baixar agora", "Download now"), false)) {
            confirming = false;
            // O QA clica em tudo: aqui ele nunca baixa de verdade.
            get.qa_no_network = qa.on();
            get.start();
        }
        if (p.buttonSoft(i18n.tr("Cancelar", "Cancel"))) confirming = false;
        return;
    } else if (p.button(i18n.tr("Baixar FFmpeg", "Download FFmpeg"), false)) confirming = true;
    folderRows(p, true);
    if (p.buttonSoft(i18n.tr("Procurar de novo", "Check again"))) {
        ffmpeg.forget();
        _ = ffmpeg.get();
    }
}

/// O texto de uma nota que o QA também procura pela marcação `key`.
fn markedNote(p: anytype, t: []const u8, comptime key: []const u8, args: anytype) void {
    const y0 = p.y;
    p.note(t);
    qa.mark(.{ .x = p.x, .y = y0, .w = p.w, .h = @max(p.y - y0 - 7, 1) }, key, args);
}

/// "avcodec-61.dll" (ou "libavcodec.so.61") da biblioteca que falta num conjunto.
fn missingName(buf: []u8, set: busca.Set, lib: busca.Lib) []const u8 {
    return busca.libFile(buf, busca.native, @tagName(lib), busca.major(set, lib)) orelse @tagName(lib);
}

/// O que uma pasta tem, em palavras. `subject`: "A pasta escolhida", "Essa pasta"…
fn dirText(buf: []u8, ch: busca.Check, subject: []const u8) []const u8 {
    var vb: [32]u8 = undefined;
    const versions = busca.supportedVersions(&vb, i18n.tr(" ou ", " or "));
    var nb: [48]u8 = undefined;
    return switch (ch) {
        .ok => |s| i18n.fmt(buf, "{s} tem o FFmpeg {d}, mas ele não carregou.", "{s} has FFmpeg {d}, but it didn't load.", .{ subject, busca.ffmpegVersion(s.lavf) }),
        .incomplete => |inc| i18n.fmt(buf, "{s} tem parte do FFmpeg {d}: falta o {s}.", "{s} has part of FFmpeg {d}: {s} is missing.", .{ subject, busca.ffmpegVersion(inc.set.lavf), missingName(&nb, inc.set, inc.missing) }),
        .unsupported => |m| i18n.fmt(buf, "{s} tem o FFmpeg {d} (libavformat {d}), e o app só sabe usar o FFmpeg {s}.", "{s} has FFmpeg {d} (libavformat {d}), and the app only works with FFmpeg {s}.", .{ subject, busca.ffmpegVersion(m), m, versions }),
        .static_exe => if (busca.native == .windows)
            i18n.fmt(buf, "{s} só tem o ffmpeg.exe: é uma versão estática, um programa só, sem as bibliotecas (DLLs) que o app carrega.", "{s} only has ffmpeg.exe: it's a static build, a single program without the libraries (DLLs) the app loads.", .{subject})
        else
            i18n.fmt(buf, "{s} só tem o ffmpeg: é uma versão estática, sem as bibliotecas (libavcodec e as outras) que o app carrega.", "{s} only has ffmpeg: it's a static build, without the libraries (libavcodec and the others) the app loads.", .{subject}),
        .nothing => i18n.fmt(buf, "{s} não tem as bibliotecas do FFmpeg.", "{s} doesn't have FFmpeg's libraries.", .{subject}),
    };
}

/// Por que não achou: o que tinha na pasta escolhida, no PATH e no sistema, e o
/// que foi procurado.
fn diagnosis(p: anytype) void {
    var dg: ffmpeg.Diag = undefined;
    ffmpeg.diagnosis(&dg);
    var buf: [900]u8 = undefined;
    var vb: [32]u8 = undefined;
    const versions = busca.supportedVersions(&vb, i18n.tr(" ou ", " or "));
    if (dg.chosen) |ch| markedNote(p, dirText(&buf, ch, i18n.tr("A pasta escolhida", "The chosen folder")), "ffmpeg-diag:pasta:{s}", .{@tagName(ch)});
    if (dg.failed_file.len > 0) {
        markedNote(p, i18n.fmt(&buf, "{s} existe, mas o sistema não conseguiu carregar: {s}", "{s} is there, but the system couldn't load it: {s}", .{ dg.failed_file.slice(), dg.failed_why.slice() }), "ffmpeg-diag:falhou", .{});
    } else if (dg.mismatch != 0) {
        markedNote(p, i18n.fmt(&buf, "O libavformat {d} carregou, mas a versão dentro dele não bate com o nome do arquivo.", "libavformat {d} loaded, but the version inside it doesn't match the file name.", .{dg.mismatch}), "ffmpeg-diag:versao-errada", .{});
    }
    if (dg.other != 0) markedNote(p, i18n.fmt(&buf, "Em {s} tem o FFmpeg {d} (libavformat {d}), e o app só sabe usar o FFmpeg {s}.", "{s} has FFmpeg {d} (libavformat {d}), and the app only works with FFmpeg {s}.", .{ dg.other_dir.slice(), busca.ffmpegVersion(dg.other), dg.other, versions }), "ffmpeg-diag:versao:{d}", .{dg.other});
    // O ffmpeg do PATH sem bibliotecas por perto (no Linux, nem nas pastas do sistema).
    const exe_alone = dg.exe_dir.len > 0 and (dg.exe_check == .static_exe or dg.exe_check == .nothing) and dg.system == .nothing and dg.other == 0;
    if (exe_alone) {
        markedNote(p, if (busca.native == .windows)
            i18n.fmt(&buf, "O ffmpeg.exe em {s} é uma versão estática: um programa só, sem as bibliotecas (DLLs) que o app carrega. O winget, o choco e as versões \"essentials\" e \"full\" do gyan.dev instalam assim. Use o Baixar FFmpeg abaixo, ou escolha a pasta de uma versão \"shared\", que traz o avcodec e as outras DLLs.", "The ffmpeg.exe in {s} is a static build: a single program without the libraries (DLLs) the app loads. winget, choco and gyan.dev's \"essentials\" and \"full\" builds install it this way. Use Download FFmpeg below, or choose the folder of a \"shared\" build, which comes with avcodec and the other DLLs.", .{dg.exe_dir.slice()})
        else
            i18n.fmt(&buf, "O ffmpeg em {s} é uma versão estática: um programa só, sem as bibliotecas (libavcodec e as outras) que o app carrega.", "The ffmpeg in {s} is a static build: a single program without the libraries (libavcodec and the others) the app loads.", .{dg.exe_dir.slice()}), "ffmpeg-diag:estatico", .{});
    } else if (dg.exe_dir.len > 0 and dg.exe_check == .incomplete) {
        markedNote(p, dirText(&buf, dg.exe_check, dg.exe_dir.slice()), "ffmpeg-diag:incompleto", .{});
    }
    if (dg.system == .incomplete) markedNote(p, dirText(&buf, dg.system, dg.system_dir.slice()), "ffmpeg-diag:sistema", .{});
    var nb: [160]u8 = undefined;
    markedNote(p, i18n.fmt(&buf, "Procurei {s}.", "Looked for {s}.", .{busca.searchedNames(&nb, busca.native)}), "ffmpeg-diag:procurei", .{});
    if (dg.disabled) p.note(i18n.tr("LARPER_NO_FFMPEG está ligado: o app não carrega o FFmpeg.", "LARPER_NO_FFMPEG is set: the app doesn't load FFmpeg."));
}

/// Escolher a pasta (e o porquê de a última não servir) e a pasta guardada, que dá
/// para esquecer. `choose`: sem FFmpeg carregado, o botão de escolher aparece.
fn folderRows(p: anytype, choose: bool) void {
    const ctx = p.ctx;
    const s = &ctx.st.settings;
    var buf: [700]u8 = undefined;
    if (choose) {
        if (p.buttonSoft(i18n.tr("Escolher a pasta do FFmpeg…", "Choose FFmpeg folder…"))) {
            picking = true;
            pick_cancelled.store(false, .release);
            refused = null;
            ctx.act(.pick_ffmpeg_dir);
        }
        if (refused) |ch| {
            markedNote(p, dirText(&buf, ch, i18n.tr("Essa pasta", "That folder")), "ffmpeg-escolha:{s}", .{@tagName(ch)});
            if (ch == .static_exe or ch == .nothing) p.note(i18n.tr("Escolha a pasta com as bibliotecas de uma versão \"shared\" do FFmpeg (no Windows, a pasta bin com o avcodec e as outras DLLs).", "Choose the folder with the libraries of a \"shared\" FFmpeg build (on Windows, the bin folder with avcodec and the other DLLs)."));
        }
    }
    if (s.ffmpeg_dir.len > 0) {
        markedNote(p, i18n.fmt(&buf, "Pasta escolhida: {s}", "Chosen folder: {s}", .{s.ffmpeg_dir.slice()}), "ffmpeg-pasta", .{});
        if (p.buttonSoft(i18n.tr("Esquecer a pasta", "Forget the folder"))) forgetDir(s);
    }
    if (pending_restart) p.note(i18n.tr("A troca de pasta vale na próxima vez que o app abrir: o FFmpeg já carregado fica até lá.", "The folder change applies the next time the app starts: the FFmpeg already loaded stays until then."));
}

fn forgetDir(s: *S.Settings) void {
    s.ffmpeg_dir = .{};
    ffmpeg.setDir("");
    refused = null;
    switch (ffmpeg.known() orelse return) {
        // Carregado da pasta: fica até o app abrir de novo.
        true => pending_restart = ffmpeg.loadedSource() == .chosen,
        false => {
            ffmpeg.forget();
            _ = ffmpeg.get();
        },
    }
}

/// O seletor do sistema devolveu uma pasta: é a do FFmpeg esperada? Confere e
/// guarda; recusada, diz o porquê (e não guarda). true = o caminho era daqui.
pub fn takePicked(st: anytype, now_ms: i64, path: [:0]const u8) bool {
    if (!picking) return false;
    picking = false;
    refused = null;
    const s = &st.settings;
    if (path.len > s.ffmpeg_dir.buf.len) {
        st.showToast(now_ms, true, "o caminho dessa pasta é longo demais", "that folder's path is too long", .{});
        return true;
    }
    const ch = ffmpeg.checkDir(path);
    if (ch != .ok) {
        refused = ch;
        return true;
    }
    s.ffmpeg_dir.set(path);
    ffmpeg.setDir(path);
    switch (ffmpeg.known() orelse false) {
        true => {
            pending_restart = true;
            st.showToast(now_ms, false, "pasta guardada: vale ao abrir o app de novo", "folder saved: applies the next time the app starts", .{});
        },
        false => {
            ffmpeg.forget();
            if (ffmpeg.get() != null) {
                st.showToast(now_ms, false, "FFmpeg {d} carregado da pasta", "FFmpeg {d} loaded from the folder", .{ffmpeg.loadedVersion()});
            } else st.showToast(now_ms, true, "a pasta tem o FFmpeg, mas ele não carregou: o motivo está em Vídeos", "the folder has FFmpeg, but it didn't load: the reason is under Videos", .{});
        },
    }
    return true;
}

/// O seletor fechou sem pasta (chamado da thread do diálogo).
pub fn cancelPick() void {
    pick_cancelled.store(true, .release);
}

/// A cada volta do laço: o seletor cancelado não deixa o próximo arquivo (um
/// anexo) virar a pasta do FFmpeg.
pub fn pollCancel() void {
    if (pick_cancelled.swap(false, .acq_rel)) picking = false;
}

/// QA: o botão pediu a pasta (o seletor do sistema não abre no QA).
pub fn qaPicking() bool {
    return picking;
}
