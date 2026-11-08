//! O que a prévia de uma resposta mostra quando a mensagem original não tem
//! texto: o arquivo, a imagem ou o vídeo, a figurinha, a mensagem de voz, a
//! enquete ou o embed. Só escolhe e aponta para o que já está na mensagem
//! (nome do arquivo, da figurinha, pergunta, título): nada é alocado, então
//! pode rodar a cada quadro. A frase e o ícone de cada caso ficam na
//! interface (ui/comp_messages.zig).
const std = @import("std");
const types = @import("types.zig");

pub const Kind = enum {
    /// Tem texto: a prévia mostra o próprio texto, sem ícone.
    text,
    /// Um arquivo só (não imagem): o nome dele.
    file,
    /// Mais de um arquivo.
    files,
    image,
    video,
    sticker,
    voice,
    poll,
    /// Só um embed (bot, encaminhada): o título ou o começo da descrição.
    embed,
    /// Nada que dê para mostrar.
    empty,
};

pub const Label = struct {
    kind: Kind,
    /// O que vem da própria mensagem (nome do arquivo ou da figurinha,
    /// pergunta da enquete, título do embed). Vazio = a interface põe a frase
    /// dela ("Clique para ver o anexo", "Mensagem de voz").
    text: []const u8 = "",
};

/// Figurinha que virou imagem (net/discord.zig `attachmentsOf`): vem do
/// caminho de figurinhas do Discord, ou da demonstração.
pub fn isSticker(a: *const types.Attachment) bool {
    const hosts = [_][]const u8{ "https://cdn.discordapp.com/stickers/", "https://media.discordapp.net/stickers/", "demo:sticker:" };
    for (hosts) |h| if (std.mem.startsWith(u8, a.url, h)) return true;
    return false;
}

/// Tira a marca de título do markdown do começo ("### ", "-# "): numa linha
/// só ela aparece crua. "#hashtag" (sem o espaço) não é título e fica.
fn plainStart(s_in: []const u8) []const u8 {
    const s = std.mem.trimStart(u8, s_in, " \n");
    const k: usize = if (std.mem.startsWith(u8, s, "-# ")) 1 else 0;
    var n: usize = 0;
    while (n < 3 and k + n < s.len and s[k + n] == '#') n += 1;
    if (n > 0 and k + n < s.len and s[k + n] == ' ') return std.mem.trimStart(u8, s[k + n ..], " ");
    return s;
}

/// O que um embed tem para mostrar numa linha, ou o tipo da mídia dele.
fn embedLabel(e: *const types.Embed) ?Label {
    if (e.poll) return .{ .kind = .poll, .text = e.title };
    if (e.title.len > 0) return .{ .kind = .embed, .text = e.title };
    const desc = plainStart(e.description);
    if (desc.len > 0) return .{ .kind = .embed, .text = desc };
    if (e.author.len > 0) return .{ .kind = .embed, .text = e.author };
    if (e.fields.len > 0 and e.fields[0].name.len > 0) return .{ .kind = .embed, .text = e.fields[0].name };
    // Componentes (e a encaminhada): o primeiro texto, senão o primeiro arquivo ou imagem.
    for (e.blocks) |*b| if (b.kind == .text) {
        const t = plainStart(b.text);
        if (t.len > 0) return .{ .kind = .embed, .text = t };
    };
    for (e.blocks) |*b| switch (b.kind) {
        .file => if (b.media.len > 0) return .{ .kind = .file, .text = b.media[0].label },
        .gallery => if (b.media.len > 0) return .{ .kind = if (b.media[0].video) .video else .image },
        else => {},
    };
    if (e.image.len > 0) return .{ .kind = if (e.video) .video else .image };
    return null;
}

/// O que mostrar da mensagem `m` na prévia de quem responde a ela.
pub fn of(m: *const types.Message) Label {
    if (m.content.len > 0) return .{ .kind = .text, .text = m.content };
    var files: usize = 0;
    var first_file: ?*const types.Attachment = null;
    var images: usize = 0;
    var videos: usize = 0;
    for (m.attachments) |*a| {
        // Voz e figurinha vêm sozinhas: são elas que dizem o que é a mensagem.
        if (a.voice) return .{ .kind = .voice };
        if (isSticker(a)) return .{ .kind = .sticker, .text = a.filename };
        if (a.isImage()) {
            if (a.video) videos += 1 else images += 1;
        } else {
            if (first_file == null) first_file = a;
            files += 1;
        }
    }
    if (images + videos > 0) return .{ .kind = if (images == 0) .video else .image };
    if (files == 1) return .{ .kind = .file, .text = first_file.?.filename };
    if (files > 1) return .{ .kind = .files };
    for (m.embeds) |*e| if (embedLabel(e)) |l| return l;
    return .{ .kind = .empty };
}

test "prévia da resposta: o que a original sem texto tem" {
    const t = std.testing;
    const file: types.Attachment = .{ .url = "https://cdn.discordapp.com/attachments/1/2/corpo.html", .filename = "corpo_humano_do_futuro.html", .size = 1200 };
    const pdf: types.Attachment = .{ .url = "https://cdn.discordapp.com/attachments/1/3/r.pdf", .filename = "relatorio.pdf" };
    const img: types.Attachment = .{ .url = "https://media.discordapp.net/attachments/1/4/a.png", .filename = "a.png", .width = 900, .height = 600 };
    const vid: types.Attachment = .{ .url = "https://media.discordapp.net/attachments/1/5/v.mp4", .filename = "v.mp4", .width = 426, .height = 240, .video = true };
    const sticker: types.Attachment = .{ .url = "https://media.discordapp.net/stickers/7.gif?size=160", .filename = "bom dia", .width = 160, .height = 160 };
    const voice: types.Attachment = .{ .url = "https://cdn.discordapp.com/attachments/1/6/voice-message.ogg", .filename = "voice-message.ogg", .voice = true, .voice_ms = 4000 };

    // Texto ganha de tudo (o anexo aparece embaixo dele na conversa).
    const with_text: types.Message = .{ .id = 1, .channel = 1, .author = 1, .timestamp = 0, .content = "olha", .attachments = &.{file} };
    try t.expectEqual(Kind.text, of(&with_text).kind);
    try t.expectEqualStrings("olha", of(&with_text).text);

    // Um arquivo: o nome dele; vários: a frase da interface.
    const one: types.Message = .{ .id = 2, .channel = 1, .author = 1, .timestamp = 0, .content = "", .attachments = &.{file} };
    try t.expectEqual(Kind.file, of(&one).kind);
    try t.expectEqualStrings("corpo_humano_do_futuro.html", of(&one).text);
    const two: types.Message = .{ .id = 3, .channel = 1, .author = 1, .timestamp = 0, .content = "", .attachments = &.{ file, pdf } };
    try t.expectEqual(Kind.files, of(&two).kind);
    try t.expectEqualStrings("", of(&two).text);

    // Imagem (mesmo junto com arquivo), só vídeo, figurinha e voz.
    const mixed: types.Message = .{ .id = 4, .channel = 1, .author = 1, .timestamp = 0, .content = "", .attachments = &.{ pdf, img } };
    try t.expectEqual(Kind.image, of(&mixed).kind);
    const video: types.Message = .{ .id = 5, .channel = 1, .author = 1, .timestamp = 0, .content = "", .attachments = &.{vid} };
    try t.expectEqual(Kind.video, of(&video).kind);
    const stk: types.Message = .{ .id = 6, .channel = 1, .author = 1, .timestamp = 0, .content = "", .attachments = &.{sticker} };
    try t.expectEqual(Kind.sticker, of(&stk).kind);
    try t.expectEqualStrings("bom dia", of(&stk).text);
    const demo_stk: types.Attachment = .{ .url = "demo:sticker:900401:1", .filename = "wumpus", .width = 160, .height = 160 };
    try t.expect(isSticker(&demo_stk));
    try t.expect(!isSticker(&img));
    const vm: types.Message = .{ .id = 7, .channel = 1, .author = 1, .timestamp = 0, .content = "", .attachments = &.{voice} };
    try t.expectEqual(Kind.voice, of(&vm).kind);

    // Enquete: a pergunta (o cartão parado traz no título).
    const poll_e = [_]types.Embed{.{ .provider = "Enquete", .title = "Qual tema vocês mais usam?", .description = "vidro\nterminal", .poll = true }};
    const pm: types.Message = .{ .id = 8, .channel = 1, .author = 1, .timestamp = 0, .content = "", .embeds = &poll_e };
    try t.expectEqual(Kind.poll, of(&pm).kind);
    try t.expectEqualStrings("Qual tema vocês mais usam?", of(&pm).text);

    // Só embed: o título; sem título, a descrição sem as marcas de título.
    const bot_e = [_]types.Embed{.{ .author = "larperBot", .title = "Status do servidor", .description = "Tudo funcionando." }};
    const bm: types.Message = .{ .id = 9, .channel = 1, .author = 1, .timestamp = 0, .content = "", .embeds = &bot_e };
    try t.expectEqual(Kind.embed, of(&bm).kind);
    try t.expectEqualStrings("Status do servidor", of(&bm).text);
    const fwd_e = [_]types.Embed{.{ .provider = "Encaminhada", .description = "### oi gente" }};
    const fm: types.Message = .{ .id = 10, .channel = 1, .author = 1, .timestamp = 0, .content = "", .embeds = &fwd_e };
    try t.expectEqualStrings("oi gente", of(&fm).text);
    try t.expectEqualStrings("#zig no topo", plainStart("#zig no topo"));
    try t.expectEqualStrings("#### quatro", plainStart("#### quatro"));

    // Componentes: o primeiro texto; encaminhada só com arquivo: o nome dele.
    const blocks = [_]types.EmbedBlock{ .{ .kind = .separator }, .{ .text = "-# Música errada? Use `/buscar`" } };
    const cv2 = [_]types.Embed{.{ .blocks = &blocks }};
    const cm: types.Message = .{ .id = 11, .channel = 1, .author = 1, .timestamp = 0, .content = "", .embeds = &cv2 };
    try t.expectEqual(Kind.embed, of(&cm).kind);
    try t.expectEqualStrings("Música errada? Use `/buscar`", of(&cm).text);
    const media = [_]types.EmbedMedia{.{ .label = "notas.txt", .size = 10 }};
    const fblocks = [_]types.EmbedBlock{.{ .kind = .file, .media = &media }};
    const fwd_file = [_]types.Embed{.{ .provider = "Encaminhada", .blocks = &fblocks }};
    const ffm: types.Message = .{ .id = 12, .channel = 1, .author = 1, .timestamp = 0, .content = "", .embeds = &fwd_file };
    try t.expectEqual(Kind.file, of(&ffm).kind);
    try t.expectEqualStrings("notas.txt", of(&ffm).text);

    // Nada: a interface diz para clicar.
    const none: types.Message = .{ .id = 13, .channel = 1, .author = 1, .timestamp = 0, .content = "" };
    try t.expectEqual(Kind.empty, of(&none).kind);
}
