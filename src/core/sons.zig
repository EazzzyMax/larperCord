//! Os sons da call: os eventos que tocam alguma coisa, as variantes
//! embutidas de cada um (geradas aqui, sem arquivo nenhum) e o toque de
//! chamada. Nada de SDL: quem toca é net/voz_audio.zig, que também lê o
//! arquivo escolhido pela pessoa (core/som_arquivo.zig decodifica).
const std = @import("std");

pub const rate = 48000;
pub const channels = 2;

/// O que toca. A ordem é a da página Voz e a dos bits de `custom_bad`.
pub const Event = enum(u8) {
    join,
    leave,
    user_join,
    user_leave,
    mute,
    unmute,
    deafen,
    undeafen,
    ring,

    pub const count = std.enums.values(Event).len;

    /// Maior duração aceita num arquivo escolhido: o toque repete, então pode
    /// ser uma música curta; os outros são avisos.
    pub fn maxMs(e: Event) u32 {
        return if (e == .ring) 15_000 else 5_000;
    }

    /// O que tocava antes de dar para escolher: alguém entrando ou saindo da
    /// call não tinha som, então continua sem até a pessoa ligar.
    pub fn defaultVariant(e: Event) Variant {
        return switch (e) {
            .user_join, .user_leave => .off,
            else => .classic,
        };
    }
};

/// O número salvo nas configurações (sound_<evento>).
pub const Variant = enum(u8) {
    off = 0,
    classic = 1,
    soft = 2,
    glass = 3,
    retro = 4,
    /// O arquivo da pessoa (sound_<evento>_file).
    custom = 5,

    /// Desligado e os embutidos (os primeiros números).
    pub const builtin_count: usize = 5;

    /// Número desconhecido (arquivo editado à mão, versão mais nova): o clássico.
    pub fn fromByte(b: u8) Variant {
        return if (b <= @backingInt(Variant.custom)) @fromBackingInt(@intCast(b)) else .classic;
    }
};

// --- Timbres -------------------------------------------------------------------

const Note = struct { hz: f32, at_ms: u32, ms: u32 };

/// Uma nota no instante `t` (segundos desde o começo dela), já com o envelope.
/// Todos terminam em zero no fim da nota (sem estalo).
fn voice(v: Variant, hz: f32, t: f32, prog: f32) f32 {
    const w = 2 * std.math.pi * hz * t;
    return switch (v) {
        // O bipe de sempre: seno com um pouco da segunda harmônica, ataque curto
        // e queda suave.
        .classic, .off, .custom => {
            const attack = @min(t / 0.006, 1);
            const decay = (1 - prog) * (1 - prog);
            const wave = @sin(w) + 0.25 * @sin(2 * w);
            return wave * attack * decay * 5200;
        },
        // Madeira (marimba): o brilho da quarta harmônica some logo e o resto
        // cai devagar.
        .soft => {
            const attack = @min(t / 0.003, 1);
            const env = @exp(-t * 9) * (1 - prog);
            const wave = @sin(w) + 0.35 * @exp(-t * 30) * @sin(4 * w);
            return wave * attack * env * 6400;
        },
        // Sino: FM com parciais fora da série harmônica, que somem antes da nota.
        .glass => {
            const attack = @min(t / 0.002, 1);
            const env = @exp(-t * 5) * (1 - prog);
            const mod = 2.0 * @exp(-t * 7) * @sin(1.4 * w);
            return @sin(w + mod) * attack * env * 4300;
        },
        // Videogame antigo: quadrada com só as primeiras harmônicas (sem o
        // chiado da quadrada perfeita), cheia até o fim e solta rápido.
        .retro => {
            const attack = @min(t / 0.002, 1);
            const release = if (prog < 0.75) 1 else (1 - prog) / 0.25;
            const wave = @sin(w) + @sin(3 * w) / 3 + @sin(5 * w) / 5 + @sin(7 * w) / 7;
            return wave * attack * release * 2800;
        },
    };
}

// Notas (Hz).
const a3 = 220.0;
const c4 = 261.63;
const d4 = 293.66;
const e4 = 329.63;
const g4 = 392.0;
const a4 = 440.0;
const c5 = 523.25;
const cs5 = 554.37;
const d5 = 587.33;
const e5 = 659.25;
const gs5 = 830.61;
const g5 = 783.99;
const a5 = 880.0;
const b5 = 987.77;
const c6 = 1046.5;
const d6 = 1174.66;
const e6 = 1318.51;
const g6 = 1567.98;

fn n(hz: f32, at_ms: u32, ms: u32) Note {
    return .{ .hz = hz, .at_ms = at_ms, .ms = ms };
}

/// Notas de cada evento (menos o toque) em cada variante embutida. Subir é
/// entrar e ligar o som; descer é sair e cortar.
fn notesOf(v: Variant, e: Event) []const Note {
    // Montadas ao compilar: as listas ficam na memória do programa (calculadas
    // aqui, `&.{...}` apontaria para a pilha desta função).
    return switch (v) {
        inline else => |cv| switch (e) {
            inline else => |ce| comptime notesTable(cv, ce),
        },
    };
}

fn notesTable(comptime v: Variant, comptime e: Event) []const Note {
    return switch (v) {
        // Ensurdecer e desensurdecer tocavam o mesmo de mutar e desmutar: o
        // clássico continua igual para quem já usava.
        .classic, .off, .custom => switch (e) {
            .join => &.{ n(c5, 0, 110), n(g5, 90, 170) },
            .leave => &.{ n(g5, 0, 110), n(c5, 90, 170) },
            .user_join => &.{ n(e5, 0, 80), n(a5, 70, 120) },
            .user_leave => &.{ n(a5, 0, 80), n(e5, 70, 120) },
            .mute, .deafen => &.{n(g4, 0, 90)},
            .unmute, .undeafen, .ring => &.{n(e5, 0, 90)},
        },
        .soft => switch (e) {
            .join => &.{ n(a4, 0, 180), n(e5, 110, 260) },
            .leave => &.{ n(e5, 0, 180), n(a4, 110, 260) },
            .user_join => &.{n(c5, 0, 220)},
            .user_leave => &.{n(g4, 0, 220)},
            .mute => &.{n(d4, 0, 200)},
            .unmute, .ring => &.{n(a4, 0, 200)},
            .deafen => &.{ n(d4, 0, 160), n(a3, 100, 240) },
            .undeafen => &.{ n(a3, 0, 160), n(d4, 100, 240) },
        },
        .glass => switch (e) {
            .join => &.{ n(c6, 0, 260), n(g6, 90, 380) },
            .leave => &.{ n(g6, 0, 260), n(c6, 90, 380) },
            .user_join => &.{n(e6, 0, 320)},
            .user_leave => &.{n(a5, 0, 320)},
            .mute => &.{n(g5, 0, 260)},
            .unmute, .ring => &.{n(d6, 0, 260)},
            .deafen => &.{ n(g5, 0, 200), n(d5, 100, 300) },
            .undeafen => &.{ n(d5, 0, 200), n(g5, 100, 300) },
        },
        .retro => switch (e) {
            .join => &.{ n(c5, 0, 60), n(e5, 60, 60), n(g5, 120, 90) },
            .leave => &.{ n(g5, 0, 60), n(e5, 60, 60), n(c5, 120, 90) },
            .user_join => &.{ n(g5, 0, 50), n(c6, 50, 80) },
            .user_leave => &.{ n(c6, 0, 50), n(g5, 50, 80) },
            .mute => &.{ n(a4, 0, 60), n(e4, 60, 80) },
            .unmute, .ring => &.{ n(e4, 0, 60), n(a4, 60, 80) },
            .deafen => &.{ n(c5, 0, 50), n(g4, 50, 50), n(c4, 100, 90) },
            .undeafen => &.{ n(c4, 0, 50), n(g4, 50, 50), n(c5, 100, 90) },
        },
    };
}

fn endMs(notes: []const Note) u32 {
    var end: u32 = 0;
    for (notes) |x| end = @max(end, x.at_ms + x.ms);
    return end;
}

/// Amostras (intercaladas) de um som embutido.
pub fn soundLen(v: Variant, e: Event) usize {
    return @as(usize, endMs(notesOf(v, e))) * rate / 1000 * channels;
}

/// O maior dos sons embutidos cabe aqui.
pub const max_sound_len = blk: {
    @setEvalBranchQuota(20_000);
    var most: usize = 0;
    for (std.enums.values(Variant)) |v| {
        for (std.enums.values(Event)) |e| most = @max(most, soundLen(v, e));
    }
    break :blk most;
};

/// Gera o som embutido em `out` (intercalado, os dois canais iguais).
pub fn synth(v: Variant, e: Event, out: []i16) []i16 {
    const len = @min(soundLen(v, e), out.len);
    @memset(out[0..len], 0);
    for (notesOf(v, e)) |note| {
        const start = @as(usize, note.at_ms) * rate / 1000;
        const count = @as(usize, note.ms) * rate / 1000;
        for (0..count) |i| {
            const pos = (start + i) * channels;
            if (pos + 1 >= len) break;
            const t = @as(f32, @floatFromInt(i)) / rate;
            const prog = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(count));
            const mixed = @as(f32, @floatFromInt(out[pos])) + voice(v, note.hz, t, prog);
            const sample: i16 = @intFromFloat(std.math.clamp(mixed, -32768, 32767));
            out[pos] = sample;
            out[pos + 1] = sample;
        }
    }
    return out[0..len];
}

// --- Toque de chamada -------------------------------------------------------

/// Um ciclo do toque (call de DM chegando): frases curtas e silêncio. Repete
/// enquanto toca; gerado aos pedaços, sem guardar o ciclo inteiro.
pub const ring_cycle_ms = 3000;
/// Quadros (cada um com `channels` amostras) de um ciclo.
pub const ring_cycle_len = ring_cycle_ms * rate / 1000;

fn trill(comptime at: u32) [10]Note {
    var out: [10]Note = undefined;
    for (&out, 0..) |*x, i| x.* = n(if (i % 2 == 0) e5 else g5, at + @as(u32, @intCast(i)) * 60, 55);
    return out;
}

const ring_classic = [_]Note{
    n(e5, 0, 260),   n(gs5, 120, 260), n(b5, 240, 380),
    n(e5, 750, 260), n(gs5, 870, 260), n(b5, 990, 380),
};
const ring_soft = [_]Note{
    n(a4, 0, 300),    n(cs5, 150, 300),  n(e5, 300, 300),  n(a5, 450, 500),
    n(a4, 1500, 300), n(cs5, 1650, 300), n(e5, 1800, 300), n(a5, 1950, 500),
};
const ring_glass = [_]Note{ n(g6, 0, 700), n(e6, 350, 900), n(g6, 1500, 700), n(e6, 1850, 900) };
const ring_retro = trill(0) ++ trill(1000);

fn ringNotes(v: Variant) []const Note {
    return switch (v) {
        .soft => &ring_soft,
        .glass => &ring_glass,
        .retro => &ring_retro,
        .classic, .off, .custom => &ring_classic,
    };
}

/// Preenche `out` (intercalado) com o toque a partir do quadro `pos` do
/// ciclo. Cada amostra só depende da posição: os pedaços emendam sem estalo.
pub fn ringSynth(v: Variant, pos: usize, out: []i16) void {
    const notes = ringNotes(v);
    var f: usize = 0;
    while (f * channels + 1 < out.len) : (f += 1) {
        const i = (pos + f) % ring_cycle_len;
        var acc: f32 = 0;
        for (notes) |note| {
            const start = @as(usize, note.at_ms) * rate / 1000;
            const count = @as(usize, note.ms) * rate / 1000;
            if (i < start or i >= start + count) continue;
            const k = i - start;
            const t = @as(f32, @floatFromInt(k)) / rate;
            const prog = @as(f32, @floatFromInt(k)) / @as(f32, @floatFromInt(count));
            acc += voice(v, note.hz, t, prog);
        }
        const sample: i16 = @intFromFloat(std.math.clamp(acc, -32768, 32767));
        out[f * channels] = sample;
        out[f * channels + 1] = sample;
    }
}

// --- Volume e nomes -----------------------------------------------------------

/// Volume do som em % (0..200; 100 = como foi gerado ou gravado).
pub fn applyGain(pcm: []i16, volume: u8) void {
    if (volume == 100) return;
    const g = @as(f32, @floatFromInt(@min(volume, 200))) / 100;
    for (pcm) |*x| x.* = @intFromFloat(std.math.clamp(@round(@as(f32, @floatFromInt(x.*)) * g), -32768, 32767));
}

/// Nome que dá para juntar à pasta dos sons sem sair dela (o settings.kdl
/// pode ter sido editado à mão).
pub fn safeName(name: []const u8) bool {
    if (name.len == 0 or name.len > 200) return false;
    if (std.mem.eql(u8, name, ".") or std.mem.eql(u8, name, "..")) return false;
    for (name) |ch| if (ch < 0x20 or ch == '/' or ch == '\\' or ch == ':') return false;
    return true;
}

/// Nome da cópia na pasta dos sons: "<evento>-<nome do arquivo>", sem o que
/// algum sistema recusa num nome de arquivo (vira "_") e curto. Cada evento
/// tem a sua cópia: trocar o som de um não apaga o de outro.
pub fn copyName(buf: []u8, e: Event, src_path: []const u8) []const u8 {
    const slash = std.mem.lastIndexOfAny(u8, src_path, "/\\");
    var base = if (slash) |i| src_path[i + 1 ..] else src_path;
    // Corta sem deixar um caractere pela metade.
    if (base.len > 120) {
        var k: usize = 120;
        while (k > 0 and base[k] & 0xC0 == 0x80) k -= 1;
        base = base[0..k];
    }
    if (base.len == 0 or std.mem.eql(u8, base, ".") or std.mem.eql(u8, base, "..")) base = "som";
    const key = @tagName(e);
    if (buf.len < key.len + 1 + base.len) return "";
    @memcpy(buf[0..key.len], key);
    buf[key.len] = '-';
    const out = buf[key.len + 1 ..][0..base.len];
    for (out, base) |*o, ch| o.* = if (ch < 0x20 or std.mem.indexOfScalar(u8, "<>:\"/\\|?*", ch) != null) '_' else ch;
    return buf[0 .. key.len + 1 + base.len];
}

/// O nome que a pessoa reconhece (sem o "<evento>-" da cópia).
pub fn displayName(e: Event, stored: []const u8) []const u8 {
    const key = @tagName(e);
    if (stored.len > key.len and std.mem.startsWith(u8, stored, key) and stored[key.len] == '-') return stored[key.len + 1 ..];
    return stored;
}

// --- Testes ----------------------------------------------------------------

const t_expect = std.testing.expect;
const t_eq = std.testing.expectEqual;

fn rmsOf(pcm: []const i16) f32 {
    var sum: f64 = 0;
    for (pcm) |x| sum += @as(f64, @floatFromInt(x)) * @as(f64, @floatFromInt(x));
    return @floatCast(@sqrt(sum / @as(f64, @floatFromInt(@max(pcm.len, 1)))));
}

fn peakOf(pcm: []const i16) i32 {
    var peak: i32 = 0;
    for (pcm) |x| peak = @max(peak, @as(i32, @intCast(@abs(x))));
    return peak;
}

test "sons embutidos: curtos, sem estourar, sem estalo no fim, diferentes entre si" {
    var buf: [max_sound_len]i16 = undefined;
    var other: [max_sound_len]i16 = undefined;
    for ([_]Variant{ .classic, .soft, .glass, .retro }) |v| {
        for (std.enums.values(Event)) |e| {
            if (e == .ring) continue;
            const len = soundLen(v, e);
            try t_expect(len > 0 and len <= max_sound_len);
            // Um aviso, não uma música.
            try t_expect(len <= 500 * rate / 1000 * channels);
            const pcm = synth(v, e, &buf);
            try t_eq(len, pcm.len);
            try t_expect(rmsOf(pcm) > 300);
            // Bem abaixo do fundo de escala, para não assustar ninguém.
            try t_expect(peakOf(pcm) < 16000);
            // Termina perto de zero.
            try t_expect(@abs(@as(i32, pcm[pcm.len - 2])) < 200);
        }
        // Entrar e sair não soam iguais em nenhuma variante.
        const a = synth(v, .join, &buf);
        const b = synth(v, .leave, &other);
        try t_expect(!std.mem.eql(i16, a[0..@min(a.len, b.len)], b[0..@min(a.len, b.len)]));
    }
    // Cada variante soa diferente da clássica.
    const classic = synth(.classic, .join, &buf);
    for ([_]Variant{ .soft, .glass, .retro }) |v| {
        const x = synth(v, .join, &other);
        const k = @min(classic.len, x.len);
        try t_expect(!std.mem.eql(i16, classic[0..k], x[0..k]));
    }
    try t_expect(soundLen(.classic, .mute) < soundLen(.classic, .join));
}

test "clássico igual ao bipe de antes (ensurdecer tocava o de mutar)" {
    var a: [max_sound_len]i16 = undefined;
    var b: [max_sound_len]i16 = undefined;
    try t_expect(std.mem.eql(i16, synth(.classic, .mute, &a), synth(.classic, .deafen, &b)));
    try t_expect(std.mem.eql(i16, synth(.classic, .unmute, &a), synth(.classic, .undeafen, &b)));
    // Desconhecido e "arquivo" sem arquivo tocam o clássico.
    try t_eq(Variant.classic, Variant.fromByte(200));
    try t_eq(Variant.custom, Variant.fromByte(5));
    try t_expect(std.mem.eql(i16, synth(.classic, .join, &a), synth(.custom, .join, &b)));
    // Quem já usava o app ouve o mesmo de antes; quem entra e sai é novo.
    try t_eq(Variant.classic, Event.join.defaultVariant());
    try t_eq(Variant.off, Event.user_join.defaultVariant());
}

test "toque de chamada: emenda sem estalo, som no começo e silêncio no fim" {
    for ([_]Variant{ .classic, .soft, .glass, .retro }) |v| {
        // Um pedaço grande ou dois pequenos dão as mesmas amostras.
        var one: [4000 * channels]i16 = undefined;
        ringSynth(v, 1000, &one);
        var two: [4000 * channels]i16 = undefined;
        ringSynth(v, 1000, two[0 .. 1500 * channels]);
        ringSynth(v, 2500, two[1500 * channels ..]);
        try t_expect(std.mem.eql(i16, &one, &two));
        try t_expect(rmsOf(&one) > 300);
        try t_expect(peakOf(&one) < 16000);
        // O fim do ciclo é silêncio, e a volta ao começo recomeça o toque.
        var tail: [2000 * channels]i16 = undefined;
        ringSynth(v, ring_cycle_len - 2000, &tail);
        for (tail) |x| try t_eq(@as(i16, 0), x);
        var wrap: [4000 * channels]i16 = undefined;
        ringSynth(v, ring_cycle_len + 1000, &wrap);
        try t_expect(std.mem.eql(i16, &one, &wrap));
        // Nenhuma nota passa do ciclo (o silêncio do fim é de verdade).
        try t_expect(endMs(ringNotes(v)) <= ring_cycle_ms - 2000 * 1000 / rate);
    }
}

test "volume por som: 100% não mexe, metade é metade, o dobro não estoura" {
    var pcm = [_]i16{ 1000, -1000, 20000, -20000, 0 };
    applyGain(&pcm, 100);
    try t_eq(@as(i16, 1000), pcm[0]);
    applyGain(&pcm, 50);
    try t_eq(@as(i16, 500), pcm[0]);
    try t_eq(@as(i16, -500), pcm[1]);
    applyGain(&pcm, 200);
    try t_eq(@as(i16, 20000), pcm[2]);
    applyGain(&pcm, 255);
    try t_eq(@as(i16, 32767), pcm[2]);
    try t_eq(@as(i16, -32768), pcm[3]);
    applyGain(&pcm, 0);
    for (pcm) |x| try t_eq(@as(i16, 0), x);
}

test "nome da cópia: só o nome do arquivo, sem caractere proibido, curto" {
    var buf: [256]u8 = undefined;
    try std.testing.expectEqualStrings("join-bip.wav", copyName(&buf, .join, "/home/a/sons/bip.wav"));
    try std.testing.expectEqualStrings("ring-toque legal.ogg", copyName(&buf, .ring, "C:\\Users\\a\\Música\\toque legal.ogg"));
    try std.testing.expectEqualStrings("mute-a_b_c.wav", copyName(&buf, .mute, "a:b\"c.wav"));
    try std.testing.expectEqualStrings("leave-música.wav", copyName(&buf, .leave, "música.wav"));
    try std.testing.expectEqualStrings("leave-som", copyName(&buf, .leave, "/tmp/"));
    try std.testing.expectEqualStrings("leave-som", copyName(&buf, .leave, ".."));
    // Muito comprido: corta sem deixar um "ç" pela metade.
    var long: [200]u8 = undefined;
    for (0..100) |i| @memcpy(long[i * 2 ..][0..2], "ç");
    const cut = copyName(&buf, .join, &long);
    try t_expect(cut.len <= "join-".len + 120);
    try t_expect(std.unicode.utf8ValidateSlice(cut));
    try t_expect(safeName(cut));
    // O nome mostrado tira o evento da frente.
    try std.testing.expectEqualStrings("bip.wav", displayName(.join, "join-bip.wav"));
    try std.testing.expectEqualStrings("outro.wav", displayName(.join, "outro.wav"));
    // Nada que saia da pasta.
    try t_expect(safeName("join-bip.wav"));
    try t_expect(!safeName(""));
    try t_expect(!safeName(".."));
    try t_expect(!safeName("../settings.kdl"));
    try t_expect(!safeName("a\\b.wav"));
    try t_expect(!safeName("C:x.wav"));
    try t_expect(!safeName("a\nb"));
}
