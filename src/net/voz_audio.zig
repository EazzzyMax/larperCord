//! O áudio da voz fora do protocolo: o que a interface escolhe (dispositivos,
//! volumes, limiar, aperte para falar), o microfone e a saída abertos pelo
//! nome e trocados sem derrubar nada, e uma thread curta para o que precisa de
//! som fora da call (medidor e teste do microfone, com a página aberta, e os
//! bipes). A interface nunca toca no áudio do SDL: abrir um dispositivo pode
//! levar centenas de milissegundos.
//!
//! Como em net/voice.zig: o microfone é um stream lido a cada 20 ms e a saída
//! é um dispositivo lógico onde cada som liga o seu stream. O SDL mistura.
//! A call e o medidor abrem cada um o seu microfone (o SDL deixa), então
//! testar não encosta no que está indo para a call.
//!
//! Os sons (entrar, sair, mutar…, o toque de chamada) são os de core/sons.zig
//! ou o arquivo que a pessoa escolheu, lido e decodificado só na hora de tocar
//! (core/som_arquivo.zig): nada fica na memória entre um som e outro, e o
//! toque do arquivo só enquanto toca.
const std = @import("std");
const c = @import("c");
const voz = @import("../core/voz.zig");
const sons = @import("../core/sons.zig");
const arq = @import("../core/som_arquivo.zig");
const ruido = @import("../core/ruido.zig");
const S = @import("../ui/settings_state.zig");
const fsutil = @import("../platform/fsutil.zig");

const alloc = std.heap.c_allocator;

const Atomic = std.atomic.Value;
const bytes_per_ms = voz.rate * voz.channels * @sizeOf(i16) / 1000;
const frame_bytes = voz.frame_len * @sizeOf(i16);

pub const spec: c.SDL_AudioSpec = .{ .format = c.SDL_AUDIO_S16, .channels = voz.channels, .freq = voz.rate };

const nowMs = @import("fake_gateway.zig").nowMs;

// --- Subsistema de áudio ----------------------------------------------------

/// No QA e nos prints: driver mudo (não abre o microfone de ninguém).
pub var force_dummy = false;
var init_lock: c.SDL_SpinLock = 0;

/// SDL_InitSubSystem não pode rodar em duas threads ao mesmo tempo, e aqui
/// a call, o medidor e o vídeo abrem o áudio cada um por sua conta.
/// Numa call agora? (Nada que segure a memória do processo deve rodar.)
pub var in_call = std.atomic.Value(bool).init(false);

pub fn acquire() bool {
    c.SDL_LockSpinlock(&init_lock);
    defer c.SDL_UnlockSpinlock(&init_lock);
    if (force_dummy) _ = c.SDL_SetHint(c.SDL_HINT_AUDIO_DRIVER, "dummy");
    return c.SDL_InitSubSystem(c.SDL_INIT_AUDIO);
}

pub fn release() void {
    c.SDL_LockSpinlock(&init_lock);
    defer c.SDL_UnlockSpinlock(&init_lock);
    c.SDL_QuitSubSystem(c.SDL_INIT_AUDIO);
}

// --- O que a interface escolheu ---------------------------------------------

pub const Shared = struct {
    in_gain: Atomic(f32) = .init(1),
    out_gain: Atomic(f32) = .init(1),
    threshold_db: Atomic(f32) = .init(-48.8),
    auto: Atomic(bool) = .init(false),
    highpass: Atomic(bool) = .init(true),
    gate: Atomic(bool) = .init(false),
    denoise: Atomic(ruido.Mode) = .init(ruido.Mode.default),
    sounds: Atomic(bool) = .init(true),
    /// Por evento (core/sons.zig Event): a variante e o volume (%) escolhidos.
    variant: [sons.Event.count]Atomic(u8) = defaultVariants(),
    volume: [sons.Event.count]Atomic(u8) = @splat(.init(100)),
    /// Um bit por evento: o arquivo escolhido não abriu da última vez (tocou o
    /// clássico no lugar). A página Voz avisa.
    custom_bad: Atomic(u16) = .init(0),
    ptt: Atomic(bool) = .init(false),
    /// A tecla do aperte para falar está apertada (eventos do SDL, janela em foco).
    ptt_down: Atomic(bool) = .init(false),
    binding: Atomic(u32) = .init(0),
    /// Imposto pelo servidor (VOICE_STATE_UPDATE).
    server_mute: Atomic(bool) = .init(false),
    server_deaf: Atomic(bool) = .init(false),
    /// Sobe quando o microfone ou a saída escolhidos mudam.
    devices_gen: Atomic(u32) = .init(1),

    // A página Voz aberta e o que ela mostra.
    page_open: Atomic(bool) = .init(false),
    test_on: Atomic(bool) = .init(false),
    level_db: Atomic(f32) = .init(voz.db_silence),
    shown_threshold_db: Atomic(f32) = .init(-48.8),
    mic_failed: Atomic(bool) = .init(false),
    /// O microfone escolhido sumiu: o medidor está no padrão do sistema.
    mic_fallback: Atomic(bool) = .init(false),
    out_fallback: Atomic(bool) = .init(false),
    list_gen: Atomic(u32) = .init(0),
    /// O menu rápido de dispositivos abriu: a thread lê a lista uma vez e sai.
    list_req: Atomic(bool) = .init(false),

    // Contadores e injeção para o QA (nada disso muda o som de verdade).
    qa_tone: Atomic(f32) = .init(0),
    /// Ruído branco no lugar do microfone (amplitude, de 0 a 1).
    qa_noise: Atomic(f32) = .init(0),
    /// O nível do que o teste do microfone devolveu por último.
    loop_db: Atomic(f32) = .init(voz.db_silence),
    qa_fail_mic: Atomic(bool) = .init(false),
    sounds_played: Atomic(u32) = .init(0),
    /// Pedaços do toque de chamada já postos na saída.
    ring_chunks: Atomic(u32) = .init(0),
    loop_frames: Atomic(u32) = .init(0),
    mic_opens: Atomic(u32) = .init(0),
    out_opens: Atomic(u32) = .init(0),

    pub fn captureCfg(s: *const Shared) voz.Cfg {
        return .{
            .gain = s.in_gain.load(.monotonic),
            .threshold_db = s.threshold_db.load(.monotonic),
            .auto = s.auto.load(.monotonic),
            .highpass = s.highpass.load(.monotonic),
            .gate = s.gate.load(.monotonic),
            .denoise = s.denoise.load(.monotonic),
        };
    }
};

pub var sh: Shared = .{};

fn defaultVariants() [sons.Event.count]Atomic(u8) {
    var out: [sons.Event.count]Atomic(u8) = undefined;
    for (&out, std.enums.values(sons.Event)) |*a, e| a.* = .init(@backingInt(e.defaultVariant()));
    return out;
}

fn eventBit(e: sons.Event) u16 {
    return @as(u16, 1) << @intCast(@backingInt(e));
}

var names_lock: c.SDL_SpinLock = 0;
var mic_name: S.Text = .{};
var out_name: S.Text = .{};
/// Cópias da interface (só para saber se mudou, sem trancar a cada quadro).
var ui_mic: S.Text = .{};
var ui_out: S.Text = .{};
var ui_binding: S.Text = .{};
/// O arquivo de cada som (o nome dentro da pasta dos sons): a cópia da
/// interface e a que a thread lê, sob a trava.
var ui_files: [sons.Event.count]S.Text = @splat(.{});
var custom_lock: c.SDL_SpinLock = 0;
var custom_names: [sons.Event.count]S.Text = @splat(.{});

fn chosenName(recording: bool) S.Text {
    c.SDL_LockSpinlock(&names_lock);
    defer c.SDL_UnlockSpinlock(&names_lock);
    return if (recording) mic_name else out_name;
}

/// As configurações valendo para o áudio (a cada quadro, como o proxy: só
/// guarda números; as threads leem quando precisam).
pub fn apply(set: *const S.Settings) void {
    sh.in_gain.store(@as(f32, @floatFromInt(@min(set.voice_in_gain, 200))) / 100, .monotonic);
    sh.out_gain.store(@as(f32, @floatFromInt(@min(set.voice_out_gain, 200))) / 100, .monotonic);
    sh.threshold_db.store(voz.sensToDb(set.voice_sens), .monotonic);
    sh.auto.store(set.voice_auto, .monotonic);
    sh.highpass.store(set.voice_highpass, .monotonic);
    sh.gate.store(set.voice_gate, .monotonic);
    sh.denoise.store(ruido.Mode.fromByte(set.voice_denoise), .monotonic);
    sh.sounds.store(set.voice_sounds, .monotonic);
    for (std.enums.values(sons.Event), 0..) |e, i| {
        sh.variant[i].store(S.soundVariantC(set, e), .monotonic);
        sh.volume[i].store(S.soundVolumeC(set, e), .monotonic);
        const file = S.soundFileC(set, e);
        if (!std.mem.eql(u8, file.slice(), ui_files[i].slice())) {
            ui_files[i] = file.*;
            c.SDL_LockSpinlock(&custom_lock);
            custom_names[i] = file.*;
            c.SDL_UnlockSpinlock(&custom_lock);
            _ = sh.custom_bad.fetchAnd(~eventBit(e), .monotonic);
        }
    }
    if (set.voice_ptt != sh.ptt.load(.monotonic)) {
        sh.ptt.store(set.voice_ptt, .monotonic);
        sh.ptt_down.store(false, .monotonic);
    }
    if (!std.mem.eql(u8, set.voice_key.slice(), ui_binding.slice())) {
        ui_binding = set.voice_key;
        sh.binding.store(voz.Binding.parse(set.voice_key.slice()).encode(), .monotonic);
        sh.ptt_down.store(false, .monotonic);
    }
    const mic_changed = !std.mem.eql(u8, set.voice_mic.slice(), ui_mic.slice());
    const out_changed = !std.mem.eql(u8, set.voice_out.slice(), ui_out.slice());
    if (mic_changed or out_changed) {
        ui_mic = set.voice_mic;
        ui_out = set.voice_out;
        c.SDL_LockSpinlock(&names_lock);
        mic_name = ui_mic;
        out_name = ui_out;
        c.SDL_UnlockSpinlock(&names_lock);
        _ = sh.devices_gen.fetchAdd(1, .release);
    }
}

// --- Atalho -----------------------------------------------------------------

var capturing = false;
var captured: ?voz.Binding = null;

pub fn startCapture() void {
    capturing = true;
    captured = null;
}

pub fn cancelCapture() void {
    capturing = false;
}

pub fn isCapturing() bool {
    return capturing;
}

/// O atalho escolhido em `startCapture`, uma vez.
pub fn takeCaptured() ?voz.Binding {
    const b = captured;
    captured = null;
    return b;
}

/// Para cada evento do SDL, antes da interface. true = era a escolha do
/// atalho e a interface não deve ver.
pub fn onSdlEvent(e: *const c.SDL_Event) bool {
    switch (e.type) {
        c.SDL_EVENT_KEY_DOWN, c.SDL_EVENT_KEY_UP => {
            const down = e.type == c.SDL_EVENT_KEY_DOWN;
            if (capturing) {
                if (!down) return true;
                capturing = false;
                if (e.key.scancode != c.SDL_SCANCODE_ESCAPE) captured = .{ .key = @intCast(e.key.scancode) };
                return true;
            }
            if (sh.ptt.load(.monotonic)) setPtt(voz.pttFromEvent(voz.Binding.decode(sh.binding.load(.monotonic)), .{ .key = .{ .code = @intCast(e.key.scancode), .down = down } }));
        },
        c.SDL_EVENT_MOUSE_BUTTON_DOWN, c.SDL_EVENT_MOUSE_BUTTON_UP => {
            const down = e.type == c.SDL_EVENT_MOUSE_BUTTON_DOWN;
            if (capturing) {
                // O botão esquerdo é o que clica na interface: não vira atalho.
                if (e.button.button == c.SDL_BUTTON_LEFT) return false;
                if (!down) return true;
                capturing = false;
                captured = .{ .mouse = e.button.button };
                return true;
            }
            if (sh.ptt.load(.monotonic)) setPtt(voz.pttFromEvent(voz.Binding.decode(sh.binding.load(.monotonic)), .{ .mouse = .{ .button = e.button.button, .down = down } }));
        },
        c.SDL_EVENT_WINDOW_FOCUS_LOST => setPtt(voz.pttFromEvent(.none, .focus_lost)),
        else => {},
    }
    return false;
}

fn setPtt(v: ?bool) void {
    if (v) |down| sh.ptt_down.store(down, .monotonic);
}

// --- Dispositivos -----------------------------------------------------------

fn defaultDevice(recording: bool) c.SDL_AudioDeviceID {
    return if (recording) c.SDL_AUDIO_DEVICE_DEFAULT_RECORDING else c.SDL_AUDIO_DEVICE_DEFAULT_PLAYBACK;
}

/// O dispositivo com este nome, ou o padrão do sistema se ele não está lá.
fn resolve(recording: bool, name: []const u8) c.SDL_AudioDeviceID {
    if (name.len == 0) return defaultDevice(recording);
    var n: c_int = 0;
    const ids = (if (recording) c.SDL_GetAudioRecordingDevices(&n) else c.SDL_GetAudioPlaybackDevices(&n)) orelse return defaultDevice(recording);
    defer c.SDL_free(ids);
    for (0..@intCast(n)) |i| {
        const dn = c.SDL_GetAudioDeviceName(ids[i]) orelse continue;
        if (voz.sameName(name, std.mem.span(dn))) return ids[i];
    }
    return defaultDevice(recording);
}

/// A saída escolhida na página Voz (ou a padrão do sistema), para quem toca
/// som fora da call (mensagens de voz). Só numa thread com o áudio iniciado.
pub fn outputDevice() c.SDL_AudioDeviceID {
    const name = chosenName(false);
    return resolve(false, name.slice());
}

/// O microfone: um stream lido a cada 20 ms. Abre pelo nome salvo, confere de
/// vez em quando se o dispositivo continua lá (e se a escolha mudou) e reabre
/// sem que quem lê perceba mais do que um quadro faltando.
pub const Mic = struct {
    stream: ?*c.SDL_AudioStream = null,
    target: c.SDL_AudioDeviceID = 0,
    gen: u32 = 0,
    paused: bool = false,
    /// Aberto, mas nada chega há um tempo (dispositivo morto, sem permissão).
    no_data: bool = false,
    last_data_ms: i64 = 0,
    next_check_ms: i64 = 0,
    phase: f32 = 0,
    noise_seed: u32 = 12345,

    const check_ms = 1000;
    const no_data_ms = 3000;

    pub fn open(m: *Mic, now: i64) void {
        m.close();
        m.gen = sh.devices_gen.load(.acquire);
        const name = chosenName(true);
        m.target = resolve(true, name.slice());
        if (!sh.qa_fail_mic.load(.monotonic)) {
            m.stream = c.SDL_OpenAudioDeviceStream(m.target, &spec, null, null);
            if (m.stream == null and m.target != defaultDevice(true)) {
                m.target = defaultDevice(true);
                m.stream = c.SDL_OpenAudioDeviceStream(m.target, &spec, null, null);
            }
        }
        _ = sh.mic_opens.fetchAdd(1, .monotonic);
        if (m.stream) |s| if (!m.paused) {
            _ = c.SDL_ResumeAudioStreamDevice(s);
        } else {
            _ = c.SDL_PauseAudioStreamDevice(s);
        };
        m.last_data_ms = now;
        m.next_check_ms = now + check_ms;
    }

    pub fn close(m: *Mic) void {
        if (m.stream) |s| c.SDL_DestroyAudioStream(s);
        m.stream = null;
    }

    pub fn isFallback(m: *const Mic) bool {
        const name = chosenName(true);
        return name.len > 0 and m.target == defaultDevice(true);
    }

    pub fn failed(m: *const Mic) bool {
        return m.stream == null or m.no_data;
    }

    pub fn setPaused(m: *Mic, on: bool) void {
        if (m.paused == on) return;
        m.paused = on;
        const s = m.stream orelse return;
        if (on) {
            _ = c.SDL_PauseAudioStreamDevice(s);
        } else {
            _ = c.SDL_ClearAudioStream(s);
            _ = c.SDL_ResumeAudioStreamDevice(s);
            m.last_data_ms = nowMs();
        }
    }

    /// Troca de dispositivo, dispositivo que sumiu ou voltou, microfone mudo.
    pub fn check(m: *Mic, now: i64) void {
        const gen = sh.devices_gen.load(.acquire);
        if (gen == m.gen and now < m.next_check_ms) return;
        m.next_check_ms = now + check_ms;
        if (sh.qa_fail_mic.load(.monotonic)) {
            m.close();
            return;
        }
        const name = chosenName(true);
        const want = resolve(true, name.slice());
        if (gen != m.gen or want != m.target or m.stream == null) return m.open(now);
        if (m.paused) return;
        const s = m.stream orelse return;
        if (c.SDL_GetAudioStreamAvailable(s) >= frame_bytes) m.last_data_ms = now;
        if (now - m.last_data_ms > no_data_ms) {
            m.no_data = true;
            m.open(now);
        }
    }

    /// Um quadro de 20 ms. Se acumulou atraso, joga fora o mais antigo.
    pub fn read(m: *Mic, out: *[voz.frame_len]i16) bool {
        const s = m.stream orelse return false;
        var avail = c.SDL_GetAudioStreamAvailable(s);
        var scratch: [frame_bytes]u8 = undefined;
        while (avail > frame_bytes * 4) {
            _ = c.SDL_GetAudioStreamData(s, &scratch, frame_bytes);
            avail -= frame_bytes;
        }
        if (avail < frame_bytes) return false;
        if (c.SDL_GetAudioStreamData(s, out, frame_bytes) != frame_bytes) return false;
        m.no_data = false;
        m.last_data_ms = nowMs();
        const amp = sh.qa_tone.load(.monotonic);
        if (amp > 0) {
            var i: usize = 0;
            while (i < out.len) : (i += 2) {
                const v: i16 = @intFromFloat(@sin(m.phase) * amp * 32767);
                out[i] = v;
                out[i + 1] = v;
                m.phase = @mod(m.phase + 2 * std.math.pi * 440.0 / @as(f32, voz.rate), 2 * std.math.pi);
            }
        }
        const noise = sh.qa_noise.load(.monotonic);
        if (noise > 0) {
            var i: usize = 0;
            while (i < out.len) : (i += 2) {
                m.noise_seed = m.noise_seed *% 1664525 +% 1013904223;
                const u = @as(f32, @floatFromInt(m.noise_seed >> 8)) / (1 << 24);
                const v: i16 = @intFromFloat((u * 2 - 1) * noise * 32767);
                out[i] = v;
                out[i + 1] = v;
            }
        }
        return true;
    }
};

/// A saída: um dispositivo lógico onde cada stream se liga. O ganho dele é o
/// volume de saída. Trocar abre o novo, passa os streams e só então fecha o
/// velho, então nenhuma pessoa da call precisa reabrir nada.
pub const Output = struct {
    dev: c.SDL_AudioDeviceID = 0,
    target: c.SDL_AudioDeviceID = 0,
    gen: u32 = 0,
    gain: f32 = -1,
    next_check_ms: i64 = 0,

    const check_ms = 1000;

    fn openDevice(o: *Output) c.SDL_AudioDeviceID {
        o.gen = sh.devices_gen.load(.acquire);
        const name = chosenName(false);
        o.target = resolve(false, name.slice());
        var dev = c.SDL_OpenAudioDevice(o.target, &spec);
        if (dev == 0 and o.target != defaultDevice(false)) {
            o.target = defaultDevice(false);
            dev = c.SDL_OpenAudioDevice(o.target, &spec);
        }
        _ = sh.out_opens.fetchAdd(1, .monotonic);
        return dev;
    }

    pub fn open(o: *Output, now: i64) void {
        o.close();
        o.dev = o.openDevice();
        o.gain = -1;
        o.applyGain();
        o.next_check_ms = now + check_ms;
    }

    pub fn close(o: *Output) void {
        if (o.dev != 0) c.SDL_CloseAudioDevice(o.dev);
        o.dev = 0;
    }

    pub fn applyGain(o: *Output) void {
        const g = sh.out_gain.load(.monotonic);
        if (g == o.gain or o.dev == 0) return;
        o.gain = g;
        _ = c.SDL_SetAudioDeviceGain(o.dev, g);
    }

    /// O dispositivo novo, se é hora de trocar. Quem chama passa os streams
    /// para ele (`rebind`) e chama `adopt`.
    pub fn check(o: *Output, now: i64) ?c.SDL_AudioDeviceID {
        const gen = sh.devices_gen.load(.acquire);
        if (gen == o.gen and now < o.next_check_ms) return null;
        o.next_check_ms = now + check_ms;
        const name = chosenName(false);
        const want = resolve(false, name.slice());
        if (gen == o.gen and want == o.target and o.dev != 0) return null;
        const dev = o.openDevice();
        return if (dev != 0) dev else null;
    }

    pub fn rebind(new_dev: c.SDL_AudioDeviceID, stream: *c.SDL_AudioStream) void {
        c.SDL_UnbindAudioStream(stream);
        _ = c.SDL_BindAudioStream(new_dev, stream);
    }

    pub fn adopt(o: *Output, new_dev: c.SDL_AudioDeviceID) void {
        o.close();
        o.dev = new_dev;
        o.gain = -1;
        o.applyGain();
    }
};

// --- Lista de dispositivos (para a página) ----------------------------------

pub const max_devices = 16;

pub const DeviceList = struct {
    n: u8 = 0,
    names: [max_devices]S.Text = @splat(.{}),

    pub fn slice(l: *const DeviceList, i: usize) []const u8 {
        return l.names[i].slice();
    }

    fn eql(a: *const DeviceList, b: *const DeviceList) bool {
        if (a.n != b.n) return false;
        for (0..a.n) |i| if (!std.mem.eql(u8, a.slice(i), b.slice(i))) return false;
        return true;
    }
};

var list_lock: c.SDL_SpinLock = 0;
var list_in: DeviceList = .{};
var list_out: DeviceList = .{};

fn scanDevices(recording: bool, out: *DeviceList) void {
    out.* = .{};
    var n: c_int = 0;
    const ids = (if (recording) c.SDL_GetAudioRecordingDevices(&n) else c.SDL_GetAudioPlaybackDevices(&n)) orelse return;
    defer c.SDL_free(ids);
    for (0..@intCast(n)) |i| {
        if (out.n == max_devices) break;
        const dn = c.SDL_GetAudioDeviceName(ids[i]) orelse continue;
        var buf: [voz.max_name]u8 = undefined;
        out.names[out.n].set(voz.cleanName(&buf, std.mem.span(dn)));
        out.n += 1;
    }
}

fn publishDevices() void {
    const T = struct {
        var a: DeviceList = .{};
        var b: DeviceList = .{};
    };
    scanDevices(true, &T.a);
    scanDevices(false, &T.b);
    c.SDL_LockSpinlock(&list_lock);
    defer c.SDL_UnlockSpinlock(&list_lock);
    if (T.a.eql(&list_in) and T.b.eql(&list_out)) return;
    list_in = T.a;
    list_out = T.b;
    _ = sh.list_gen.fetchAdd(1, .release);
}

/// A lista como a thread de áudio viu por último (a interface guarda uma cópia).
pub fn copyDevices(recording: *DeviceList, playback: *DeviceList) void {
    c.SDL_LockSpinlock(&list_lock);
    defer c.SDL_UnlockSpinlock(&list_lock);
    recording.* = list_in;
    playback.* = list_out;
}

// --- Thread do medidor, do teste e dos bipes --------------------------------

var state_lock: c.SDL_SpinLock = 0;
var running = false;
/// Um som pedido: na call (respeita "Sons da call") ou o Ouvir da página.
const Req = struct { ev: sons.Event, preview: bool };
var pending: [8]Req = undefined;
var n_pending: usize = 0;
var stop_req: Atomic(bool) = .init(false);
/// Só a thread da interface mexe neste.
var thread: ?*c.SDL_Thread = null;

/// Sobe a thread, se ela não estiver de pé (só a thread da interface chama).
fn ensureThread() void {
    c.SDL_LockSpinlock(&state_lock);
    const start = !running;
    if (start) running = true;
    c.SDL_UnlockSpinlock(&state_lock);
    if (!start) return;
    // A anterior já avisou que acabou: esperar por ela não trava a interface.
    if (thread) |t| c.SDL_WaitThread(t, null);
    thread = c.SDL_CreateThread(helperMain, "voz-audio", null);
    if (thread == null) {
        c.SDL_LockSpinlock(&state_lock);
        running = false;
        n_pending = 0;
        c.SDL_UnlockSpinlock(&state_lock);
    }
}

/// A página Voz abriu ou fechou (a cada quadro: só age quando muda).
pub fn setPageOpen(open: bool) void {
    if (open == sh.page_open.load(.monotonic)) return;
    sh.page_open.store(open, .release);
    if (open) {
        sh.mic_failed.store(false, .monotonic);
        ensureThread();
    } else {
        sh.test_on.store(false, .release);
        capturing = false;
    }
}

/// Pede a lista de dispositivos uma vez (o menu rápido do microfone e do fone).
/// Não bloqueia: a thread abre o áudio, lê e fecha; `list_gen` sobe se mudou.
pub fn requestList() void {
    sh.list_req.store(true, .release);
    ensureThread();
}

fn variantOf(e: sons.Event) sons.Variant {
    return sons.Variant.fromByte(sh.variant[@backingInt(e)].load(.monotonic));
}

fn enqueue(req: Req) void {
    c.SDL_LockSpinlock(&state_lock);
    if (n_pending < pending.len) {
        pending[n_pending] = req;
        n_pending += 1;
    }
    c.SDL_UnlockSpinlock(&state_lock);
    ensureThread();
}

/// Toca o som do evento, se os sons estão ligados e o dele não está
/// desligado. Não bloqueia: a thread abre o áudio (e lê o arquivo, se é um).
pub fn play(e: sons.Event) void {
    if (!sh.sounds.load(.monotonic) or variantOf(e) == .off) return;
    enqueue(.{ .ev = e, .preview = false });
}

/// O Ouvir da página Voz: toca mesmo com "Sons da call" desligado, e corta o
/// que a página estava tocando (clicar de novo recomeça, não empilha).
pub fn preview(e: sons.Event) void {
    enqueue(.{ .ev = e, .preview = true });
}

/// Toque de chamada: liga (repete até desligar) ou desliga. Não bloqueia.
/// Sozinho, para depois de `ring_max_ms` (um CALL_UPDATE perdido não deixa
/// o toque para sempre). Desligado nas configurações, nada toca (nem a
/// thread sobe).
pub fn setRinging(on: bool) void {
    const want = on and variantOf(.ring) != .off;
    if (ring_on.load(.acquire) == want) return;
    // Sob a trava, como a fila dos bipes: a thread que está saindo vê o
    // pedido, ou `ensureThread` vê que ela saiu.
    c.SDL_LockSpinlock(&state_lock);
    ring_on.store(want, .release);
    c.SDL_UnlockSpinlock(&state_lock);
    if (want) ensureThread();
}

pub fn ringing() bool {
    return ring_on.load(.acquire);
}

var ring_on: Atomic(bool) = .init(false);
const ring_max_ms = 60_000;
/// 50 ms por pedaço (intercalado).
const ring_chunk = 50 * voz.rate / 1000 * voz.channels;
/// O toque do arquivo, no Ouvir da página, para aqui (o de verdade repete).
const preview_ring_len = 6 * voz.rate * voz.channels;

/// Ao fechar o app, antes do SDL_Quit.
pub fn shutdown() void {
    stop_req.store(true, .release);
    if (thread) |t| c.SDL_WaitThread(t, null);
    thread = null;
}

const Helper = struct {
    mic: Mic = .{},
    out: Output = .{},
    cap: voz.Capture = .{},
    loop: ?*c.SDL_AudioStream = null,
    sfx: ?*c.SDL_AudioStream = null,
    /// O toque de chamada, e em que ponto do ciclo ele está.
    ring: ?*c.SDL_AudioStream = null,
    ring_pos: usize = 0,
    ring_since_ms: i64 = 0,
    ring_variant: sons.Variant = .classic,
    /// O arquivo do toque, decodificado só enquanto toca.
    ring_pcm: ?[]i16 = null,
    /// Até quando os bipes já postos ainda estão tocando.
    sfx_until_ms: i64 = 0,
    next_scan_ms: i64 = 0,
    mic_open: bool = false,
    shown_db: f32 = voz.db_silence,
    audio_ok: bool = false,

    fn closeAll(h: *Helper) void {
        h.mic.close();
        h.cap.release();
        h.mic_open = false;
        if (h.loop) |s| c.SDL_DestroyAudioStream(s);
        h.loop = null;
        if (h.sfx) |s| c.SDL_DestroyAudioStream(s);
        h.sfx = null;
        if (h.ring) |s| c.SDL_DestroyAudioStream(s);
        h.ring = null;
        h.freeRing();
        h.out.close();
    }

    fn freeRing(h: *Helper) void {
        if (h.ring_pcm) |p| alloc.free(p);
        h.ring_pcm = null;
    }

    fn ensureOut(h: *Helper, now: i64) bool {
        if (h.out.dev == 0) h.out.open(now);
        return h.out.dev != 0;
    }

    fn newStream(h: *Helper, now: i64) ?*c.SDL_AudioStream {
        if (!h.ensureOut(now)) return null;
        const s = c.SDL_CreateAudioStream(&spec, &spec) orelse return null;
        _ = c.SDL_BindAudioStream(h.out.dev, s);
        return s;
    }

    fn stepPage(h: *Helper, now: i64) void {
        if (!sh.page_open.load(.acquire)) {
            if (h.mic_open) {
                h.mic.close();
                h.mic_open = false;
                h.cap.release();
                h.cap = .{};
                h.shown_db = voz.db_silence;
                sh.level_db.store(voz.db_silence, .monotonic);
            }
            if (h.loop) |s| c.SDL_DestroyAudioStream(s);
            h.loop = null;
            return;
        }
        if (now >= h.next_scan_ms) {
            h.next_scan_ms = now + 1000;
            publishDevices();
            // A saída só abre para tocar algo; o aviso de "sumiu" vale antes disso.
            const out = chosenName(false);
            sh.out_fallback.store(out.len > 0 and resolve(false, out.slice()) == defaultDevice(false), .monotonic);
        }
        if (!h.mic_open) {
            h.mic.open(now);
            h.mic_open = true;
        } else h.mic.check(now);
        sh.mic_failed.store(h.mic.failed(), .monotonic);
        sh.mic_fallback.store(h.mic.isFallback(), .monotonic);
        const testing = sh.test_on.load(.acquire);
        if (testing and h.loop == null) h.loop = h.newStream(now);
        if (!testing) if (h.loop) |s| {
            c.SDL_DestroyAudioStream(s);
            h.loop = null;
        };
        var pcm: [voz.frame_len]i16 = undefined;
        var last_db: ?f32 = null;
        while (h.mic.read(&pcm)) {
            const res = h.cap.process(&pcm, sh.captureCfg());
            last_db = res.db;
            sh.shown_threshold_db.store(res.threshold_db, .monotonic);
            if (h.loop) |s| {
                // Fila grande (a saída engasgou): recomeça no presente.
                if (c.SDL_GetAudioStreamQueued(s) > 200 * bytes_per_ms) _ = c.SDL_ClearAudioStream(s);
                _ = c.SDL_PutAudioStreamData(s, &pcm, frame_bytes);
                _ = sh.loop_frames.fetchAdd(1, .monotonic);
                sh.loop_db.store(voz.dbOf(voz.rmsOf(&pcm)), .monotonic);
            }
        }
        // Sobe na hora e cai devagar: dá para ler a barra.
        if (last_db) |db| {
            h.shown_db = @max(db, h.shown_db - 1.5);
            sh.level_db.store(h.shown_db, .monotonic);
        }
    }

    fn stepSounds(h: *Helper, now: i64) void {
        var list: [pending.len]Req = undefined;
        c.SDL_LockSpinlock(&state_lock);
        const n = n_pending;
        @memcpy(list[0..n], pending[0..n]);
        n_pending = 0;
        c.SDL_UnlockSpinlock(&state_lock);
        for (list[0..n]) |req| {
            if (h.sfx == null) h.sfx = h.newStream(now);
            const s = h.sfx orelse break;
            if (req.preview) _ = c.SDL_ClearAudioStream(s);
            if (putSound(s, req)) _ = sh.sounds_played.fetchAdd(1, .monotonic);
        }
        if (h.sfx) |s| {
            if (n > 0) h.sfx_until_ms = now + @divTrunc(c.SDL_GetAudioStreamQueued(s), bytes_per_ms) + 300;
            if (now >= h.sfx_until_ms) {
                c.SDL_DestroyAudioStream(s);
                h.sfx = null;
            }
        }
    }

    /// Mantém uns 200 ms do toque na fila: desligar para logo, e um atraso
    /// da thread não deixa buraco.
    fn stepRing(h: *Helper, now: i64) void {
        if (!ring_on.load(.acquire)) {
            if (h.ring) |s| c.SDL_DestroyAudioStream(s);
            h.ring = null;
            h.ring_since_ms = 0;
            h.freeRing();
            return;
        }
        if (h.ring_since_ms == 0) {
            h.ring_since_ms = now;
            h.ring_pos = 0;
            // A escolha vale para o toque inteiro; o arquivo decodifica uma vez.
            h.ring_variant = variantOf(.ring);
            if (h.ring_variant == .custom) {
                h.ring_pcm = loadCustom(.ring, sons.Event.ring.maxMs());
                if (h.ring_pcm == null) h.ring_variant = .classic;
            }
        }
        if (now - h.ring_since_ms > ring_max_ms) {
            ring_on.store(false, .release);
            return;
        }
        if (h.ring == null) h.ring = h.newStream(now);
        const s = h.ring orelse return;
        // Um arquivo curto repete no ritmo do embutido (um "dim" a cada 3 s, não
        // colado); um longo emenda no começo.
        const period = if (h.ring_pcm) |p| @max(p.len / voz.channels, sons.ring_cycle_len) else sons.ring_cycle_len;
        const vol = sh.volume[@backingInt(sons.Event.ring)].load(.monotonic);
        while (c.SDL_GetAudioStreamQueued(s) < 200 * bytes_per_ms) {
            var pcm: [ring_chunk]i16 = undefined;
            if (h.ring_pcm) |file| loopInto(file, period, h.ring_pos, &pcm) else sons.ringSynth(h.ring_variant, h.ring_pos, &pcm);
            sons.applyGain(&pcm, vol);
            h.ring_pos = (h.ring_pos + ring_chunk / voz.channels) % period;
            if (!c.SDL_PutAudioStreamData(s, &pcm, @intCast(pcm.len * @sizeOf(i16)))) break;
            _ = sh.ring_chunks.fetchAdd(1, .monotonic);
        }
    }

    fn stepOutput(h: *Helper, now: i64) void {
        if (h.out.dev == 0) return;
        if (h.loop == null and h.sfx == null and h.ring == null) {
            h.out.close();
            return;
        }
        h.out.applyGain();
        if (h.out.check(now)) |dev| {
            if (h.loop) |s| Output.rebind(dev, s);
            if (h.sfx) |s| Output.rebind(dev, s);
            if (h.ring) |s| Output.rebind(dev, s);
            h.out.adopt(dev);
        }
    }

    fn hasWork(h: *const Helper) bool {
        return sh.page_open.load(.acquire) or h.sfx != null or n_pending > 0 or ring_on.load(.acquire) or h.ring != null or sh.list_req.load(.acquire);
    }
};

/// `out` (intercalado) com o arquivo em loop a partir do quadro `pos`; depois
/// do fim do arquivo e antes de `period`, silêncio.
fn loopInto(file: []const i16, period: usize, pos: usize, out: []i16) void {
    const frames = file.len / voz.channels;
    var f: usize = 0;
    while (f * voz.channels + 1 < out.len) : (f += 1) {
        const i = (pos + f) % period;
        const l: i16 = if (i < frames) file[i * 2] else 0;
        const r: i16 = if (i < frames) file[i * 2 + 1] else 0;
        out[f * 2] = l;
        out[f * 2 + 1] = r;
    }
}

fn putPcm(s: *c.SDL_AudioStream, pcm: []const i16) bool {
    return c.SDL_PutAudioStreamData(s, pcm.ptr, @intCast(pcm.len * @sizeOf(i16)));
}

/// Põe o som pedido na fila. false = nada para tocar (desligado) ou a fila
/// recusou. O arquivo que não abre toca o clássico.
fn putSound(s: *c.SDL_AudioStream, req: Req) bool {
    var v = variantOf(req.ev);
    const vol = sh.volume[@backingInt(req.ev)].load(.monotonic);
    if (v == .off) return false;
    if (v == .custom) {
        if (loadCustom(req.ev, req.ev.maxMs())) |pcm| {
            defer alloc.free(pcm);
            const cut = if (req.ev == .ring) @min(pcm.len, preview_ring_len) else pcm.len;
            sons.applyGain(pcm[0..cut], vol);
            return putPcm(s, pcm[0..cut]);
        }
        v = .classic;
    }
    if (req.ev == .ring) {
        // O toque embutido, no Ouvir da página: um ciclo.
        var pos: usize = 0;
        var chunk: [ring_chunk]i16 = undefined;
        while (pos < sons.ring_cycle_len) : (pos += ring_chunk / voz.channels) {
            sons.ringSynth(v, pos, &chunk);
            sons.applyGain(&chunk, vol);
            if (!putPcm(s, &chunk)) return false;
        }
        return true;
    }
    var pcm: [sons.max_sound_len]i16 = undefined;
    const data = sons.synth(v, req.ev, &pcm);
    sons.applyGain(data, vol);
    return putPcm(s, data);
}

// --- Arquivo escolhido pela pessoa --------------------------------------------

/// No QA e nos prints, as cópias ficam em qa-out/sons (nunca na pasta de
/// configurações de quem roda o teste).
pub var qa_sounds_dir = false;

/// Onde fica a cópia `name` (só o nome do arquivo, como nas configurações).
pub fn soundPath(buf: []u8, name: []const u8) ?[:0]const u8 {
    if (!sons.safeName(name)) return null;
    if (qa_sounds_dir) return std.fmt.bufPrintSentinel(buf, "qa-out/sons/{s}", .{name}, 0) catch null;
    var nb: [256]u8 = undefined;
    const rel = std.fmt.bufPrint(&nb, "sons/{s}", .{name}) catch return null;
    return fsutil.configPath(buf, rel);
}

/// O Opus de cada pacote, pela libopus (core/som_arquivo.zig não a conhece).
const OpusDec = struct {
    h: *c.OpusDecoder,
    channels: usize,

    fn init(channels: u8) ?OpusDec {
        var err: c_int = 0;
        const h = c.opus_decoder_create(@intCast(arq.out_rate), channels, &err) orelse return null;
        return .{ .h = h, .channels = channels };
    }

    fn deinit(d: *OpusDec) void {
        c.opus_decoder_destroy(d.h);
    }

    pub fn decode(d: *OpusDec, packet: []const u8, pcm: []i16) ?usize {
        const got = c.opus_decode(d.h, packet.ptr, @intCast(packet.len), pcm.ptr, @intCast(pcm.len / d.channels), 0);
        return if (got > 0) @intCast(got) else null;
    }
};

/// WAV ou Ogg Opus (pelo começo do arquivo) inteiro, a 48 kHz estéreo.
pub fn decodeFile(gpa: std.mem.Allocator, bytes: []const u8, max_ms: u32) arq.Error![]i16 {
    switch (arq.sniff(bytes) orelse return error.Unsupported) {
        .wav => return arq.decodeWav(gpa, bytes, max_ms),
        .ogg => {
            var s = try arq.openOgg(gpa, bytes, max_ms);
            defer s.deinit(gpa);
            var dec = OpusDec.init(s.channels) orelse return error.Unsupported;
            defer dec.deinit();
            return arq.decodeOgg(gpa, bytes, &s, &dec);
        },
    }
}

pub const LoadError = arq.Error || error{Read};

/// Lê (até 2 MB, conferido antes de abrir) e decodifica.
pub fn loadFile(gpa: std.mem.Allocator, path: [:0]const u8, max_ms: u32) LoadError![]i16 {
    const bytes = try readSmall(path);
    defer c.SDL_free(@constCast(bytes.ptr));
    return decodeFile(gpa, bytes, max_ms);
}

/// O arquivo inteiro, se é um arquivo comum de até `arq.max_bytes`. Quem
/// chama solta com SDL_free.
fn readSmall(path: [:0]const u8) LoadError![]const u8 {
    var info: c.SDL_PathInfo = undefined;
    if (!c.SDL_GetPathInfo(path.ptr, &info) or info.type != c.SDL_PATHTYPE_FILE) return error.Read;
    if (info.size > arq.max_bytes) return error.TooBig;
    var size: usize = 0;
    const data = c.SDL_LoadFile(path.ptr, &size) orelse return error.Read;
    return @as([*]const u8, @ptrCast(data))[0..size];
}

/// O arquivo escolhido para o evento, decodificado. null: nenhum escolhido,
/// ou ele sumiu ou estragou (marca em `custom_bad`; quem chama toca o clássico).
fn loadCustom(e: sons.Event, max_ms: u32) ?[]i16 {
    c.SDL_LockSpinlock(&custom_lock);
    const name = custom_names[@backingInt(e)];
    c.SDL_UnlockSpinlock(&custom_lock);
    if (name.len == 0) return null;
    var pb: [600]u8 = undefined;
    const pcm = if (soundPath(&pb, name.slice())) |path| loadFile(alloc, path, max_ms) catch null else null;
    if (pcm == null) {
        _ = sh.custom_bad.fetchOr(eventBit(e), .monotonic);
        return null;
    }
    _ = sh.custom_bad.fetchAnd(~eventBit(e), .monotonic);
    return pcm;
}

pub const ImportError = arq.Error || error{ Read, Write };

/// A pessoa escolheu `src` para o evento: confere (decodifica uma vez e joga
/// fora), copia para a pasta dos sons (continua tocando se o original mudar
/// de lugar) e põe o nome da cópia em `out`. A cópia anterior do mesmo evento
/// (`old`) sai se o nome mudou. Roda na thread da interface: até 2 MB e 15 s,
/// uma vez por escolha.
pub fn importSound(e: sons.Event, src: [:0]const u8, old: []const u8, out: *S.Text) ImportError!void {
    const bytes = try readSmall(src);
    defer c.SDL_free(@constCast(bytes.ptr));
    const pcm = try decodeFile(alloc, bytes, e.maxMs());
    alloc.free(pcm);
    var nb: [256]u8 = undefined;
    const name = sons.copyName(&nb, e, src);
    var pb: [600]u8 = undefined;
    const dst = soundPath(&pb, name) orelse return error.Write;
    if (std.mem.lastIndexOfScalar(u8, dst, '/')) |slash| {
        if (!fsutil.ensureDir(dst[0..slash])) return error.Write;
    }
    // Pelo SDL: nome com acento funciona também no Windows.
    if (!c.SDL_SaveFile(dst.ptr, bytes.ptr, bytes.len)) {
        _ = c.SDL_RemovePath(dst.ptr);
        return error.Write;
    }
    // Só a cópia deste evento (o nome começa com ele): nunca outro arquivo.
    if (!std.mem.eql(u8, old, name) and std.mem.startsWith(u8, old, @tagName(e)) and old.len > @tagName(e).len and old[@tagName(e).len] == '-') {
        var ob: [600]u8 = undefined;
        if (soundPath(&ob, old)) |op| _ = c.SDL_RemovePath(op.ptr);
    }
    out.set(name);
}

fn helperMain(_: ?*anyopaque) callconv(.c) c_int {
    var h: Helper = .{};
    while (true) {
        h.audio_ok = acquire();
        const no_audio = !h.audio_ok;
        if (no_audio) sh.mic_failed.store(true, .monotonic);
        while (!stop_req.load(.acquire)) {
            const now = nowMs();
            if (h.audio_ok) {
                if (sh.list_req.swap(false, .acq_rel)) publishDevices();
                h.stepPage(now);
                h.stepSounds(now);
                h.stepRing(now);
                h.stepOutput(now);
            }
            c.SDL_LockSpinlock(&state_lock);
            const work = h.hasWork();
            c.SDL_UnlockSpinlock(&state_lock);
            if (!work or !h.audio_ok) break;
            c.SDL_Delay(10);
        }
        h.closeAll();
        if (h.audio_ok) release();
        h.audio_ok = false;
        c.SDL_LockSpinlock(&state_lock);
        const again = !stop_req.load(.acquire) and h.hasWork();
        // Sem áudio de jeito nenhum: não fica tentando a 100 Hz; o próximo
        // pedido (abrir a página, um bipe) tenta de novo.
        if (!again or no_audio) {
            n_pending = 0;
            running = false;
            c.SDL_UnlockSpinlock(&state_lock);
            return 0;
        }
        c.SDL_UnlockSpinlock(&state_lock);
    }
}
