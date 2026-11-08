//! QA da voz: página de Configurações, medidor, teste do microfone, escolha de
//! dispositivo, detecção de voz, aperte para falar, avisos e sons (os de cada
//! evento, com os arquivos de teste gerados em qa-out/). Roda com o
//! driver mudo do SDL (`voz_audio.force_dummy`): o "microfone" é silêncio, e
//! `qa_tone` põe um tom no lugar para exercitar o caminho inteiro, inclusive a
//! thread de voz da demonstração. Sem call de verdade: isso aqui cobre a
//! interface e a lógica, não o som nem o Discord.
const std = @import("std");
const c = @import("c");
const App = @import("app.zig").App;
const R = @import("qa_runner.zig");
const Op = R.Op;
const qa = @import("ui/qa.zig");
const gw = @import("net/fake_gateway.zig");
const voz = @import("core/voz.zig");
const sons = @import("core/sons.zig");
const arq = @import("core/som_arquivo.zig");
const ogg = @import("core/ogg_opus.zig");
const voz_audio = @import("net/voz_audio.zig");
const ruido = @import("core/ruido.zig");
const ev = @import("core/event.zig");
const S = @import("ui/settings_state.zig");
const platform = @import("platform/window.zig");
const Id = @import("core/types.zig").Id;

const sh = &voz_audio.sh;
const me: Id = 1000;
const call: Id = 500014;

fn s(name: []const u8) Op {
    return .{ .section = name };
}
fn click(k: []const u8) Op {
    return .{ .click = .{ .mark = k } };
}
fn expect(name: []const u8, f: *const fn (*App) bool) Op {
    return .{ .expect = .{ .name = name, .check = f } };
}
fn expectLong(name: []const u8, f: *const fn (*App) bool) Op {
    return .{ .expect = .{ .name = name, .check = f, .timeout_ms = 6000 } };
}
fn run(f: *const fn (*App) void) Op {
    return .{ .run = f };
}
fn shot(name: []const u8) Op {
    return .{ .shot = name };
}

// --- Injeção -----------------------------------------------------------------

fn toneOn(_: *App) void {
    sh.qa_tone.store(0.25, .monotonic);
}
fn toneOff(_: *App) void {
    sh.qa_tone.store(0, .monotonic);
}

fn pushKey(scancode: c_uint, down: bool) void {
    var e: c.SDL_Event = std.mem.zeroes(c.SDL_Event);
    e.type = if (down) c.SDL_EVENT_KEY_DOWN else c.SDL_EVENT_KEY_UP;
    e.key.scancode = scancode;
    e.key.down = down;
    _ = c.SDL_PushEvent(&e);
}

fn pushButton(button: u8, down: bool) void {
    var e: c.SDL_Event = std.mem.zeroes(c.SDL_Event);
    e.type = if (down) c.SDL_EVENT_MOUSE_BUTTON_DOWN else c.SDL_EVENT_MOUSE_BUTTON_UP;
    e.button.button = button;
    e.button.down = down;
    _ = c.SDL_PushEvent(&e);
}

fn fDown(_: *App) void {
    pushKey(c.SDL_SCANCODE_F, true);
}
fn fUp(_: *App) void {
    pushKey(c.SDL_SCANCODE_F, false);
}
fn gDown(_: *App) void {
    pushKey(c.SDL_SCANCODE_G, true);
    pushKey(c.SDL_SCANCODE_G, false);
}
fn escTap(_: *App) void {
    pushKey(c.SDL_SCANCODE_ESCAPE, true);
    pushKey(c.SDL_SCANCODE_ESCAPE, false);
}
fn x1Tap(_: *App) void {
    pushButton(4, true);
    pushButton(4, false);
}
fn x1Down(_: *App) void {
    pushButton(4, true);
}
fn focusLost(_: *App) void {
    var e: c.SDL_Event = std.mem.zeroes(c.SDL_Event);
    e.type = c.SDL_EVENT_WINDOW_FOCUS_LOST;
    _ = c.SDL_PushEvent(&e);
}

fn pushFlags(app: *App, flags: ev.VoiceFlags) void {
    app.events.push(.{ .voice_state = .{ .channel = call, .user = me, .flags = flags } });
    platform.Window.wake(app.win.wake_type, .gateway);
}

fn resetAll(app: *App) void {
    const set = &app.st.settings;
    set.voice_mic = .{};
    set.voice_out = .{};
    set.voice_in_gain = 100;
    set.voice_out_gain = 100;
    set.voice_sens = voz.default_sens;
    set.voice_auto = false;
    set.voice_ptt = false;
    set.voice_key = .{};
    set.voice_highpass = true;
    set.voice_gate = false;
    // O tom constante da injeção é justamente o que o supressor tira: as checagens
    // de nível e de transmissão rodam sem ele, e a seção dele liga por conta própria.
    set.voice_denoise = 0;
    set.voice_sounds = true;
    S.resetSounds(set);
    sh.qa_tone.store(0, .monotonic);
    sh.qa_noise.store(0, .monotonic);
    sh.qa_fail_mic.store(false, .monotonic);
    if (app.st.muted) app.handle(.toggle_mute);
    if (app.st.deafened) app.handle(.toggle_deafen);
    if (app.st.muted) app.handle(.toggle_mute);
}

// --- Página ------------------------------------------------------------------

fn settingsOpen(app: *App) bool {
    return app.st.settings.open;
}
fn settingsClosed(app: *App) bool {
    return !app.st.settings.open;
}
fn pageOpen(app: *App) bool {
    return app.st.settings.page == .voz and sh.page_open.load(.acquire);
}
fn pageMarks(_: *App) bool {
    // O tamanho da fila da saída é zero até o teste: a página não abre som à toa.
    return qa.find("voz-mic") != null and qa.find("voz-out") != null and qa.find("voz-vol:10") != null and qa.find("voz-sens") != null and qa.find("button:Testar microfone") != null;
}
var dev_in: voz_audio.DeviceList = .{};
var dev_out: voz_audio.DeviceList = .{};
fn devicesListed(_: *App) bool {
    voz_audio.copyDevices(&dev_in, &dev_out);
    return dev_in.n > 0 and dev_out.n > 0;
}
fn meterQuiet(_: *App) bool {
    // O driver mudo entrega silêncio: o microfone abriu e não há som.
    return !sh.mic_failed.load(.monotonic) and sh.level_db.load(.monotonic) < -60;
}
fn meterLoud(_: *App) bool {
    // 0,25 do fundo de escala em RMS: cerca de -15 dB.
    return sh.level_db.load(.monotonic) > -20;
}

var loop0: u32 = 0;
fn markLoop(_: *App) void {
    loop0 = sh.loop_frames.load(.monotonic);
}
fn testRuns(_: *App) bool {
    return sh.test_on.load(.acquire) and sh.loop_frames.load(.monotonic) > loop0 + 10;
}
fn testStopped(_: *App) bool {
    return !sh.test_on.load(.acquire) and qa.find("button:Testar microfone") != null;
}
fn testStoppedKeepsCounter(_: *App) bool {
    // O medidor continua, mas nada mais volta para a saída.
    const a = sh.loop_frames.load(.monotonic);
    c.SDL_Delay(120);
    return a == sh.loop_frames.load(.monotonic);
}
fn leftPage(_: *App) bool {
    return !sh.page_open.load(.acquire) and !sh.test_on.load(.acquire);
}
fn levelReset(_: *App) bool {
    return sh.level_db.load(.monotonic) <= voz.db_silence;
}

// --- Dispositivos ------------------------------------------------------------

var opens0: u32 = 0;
fn markOpens(_: *App) void {
    opens0 = sh.mic_opens.load(.monotonic);
}
fn micReopened(_: *App) bool {
    return sh.mic_opens.load(.monotonic) > opens0;
}
fn micOptions(_: *App) bool {
    return qa.find("voz-mic-opt:0") != null and qa.find("voz-mic-opt:1") != null;
}
fn micNamed(app: *App) bool {
    return app.st.settings.voice_mic.slice().len > 0 and std.mem.eql(u8, app.st.settings.voice_mic.slice(), dev_in.slice(0));
}
fn micDefault(app: *App) bool {
    return app.st.settings.voice_mic.slice().len == 0;
}
fn outOptions(_: *App) bool {
    return qa.find("voz-out-opt:1") != null;
}
fn outNamed(app: *App) bool {
    return std.mem.eql(u8, app.st.settings.voice_out.slice(), dev_out.slice(0));
}
fn outDefault(app: *App) bool {
    return app.st.settings.voice_out.slice().len == 0;
}
fn setGoneMic(app: *App) void {
    app.st.settings.voice_mic.set("Placa que sumiu");
    app.st.settings.voice_out.set("Caixa que sumiu");
}
fn goneFallsBack(_: *App) bool {
    return qa.find("voz-mic-sumiu") != null and qa.find("voz-out-sumiu") != null and !sh.mic_failed.load(.monotonic);
}
fn clearMic(app: *App) void {
    app.st.settings.voice_mic = .{};
    app.st.settings.voice_out = .{};
}
fn noFallback(_: *App) bool {
    return qa.find("voz-mic-sumiu") == null and qa.find("voz-out-sumiu") == null;
}

// --- Volume e sensibilidade --------------------------------------------------

fn lowGain(app: *App) void {
    app.st.settings.voice_in_gain = 10;
}
fn levelDropped(_: *App) bool {
    // 20 dB abaixo do tom sozinho (-15 dB), e o medidor cai devagar.
    return sh.level_db.load(.monotonic) < -30;
}
fn gainCentered(app: *App) bool {
    const g = app.st.settings.voice_in_gain;
    return g >= 95 and g <= 105 and sh.in_gain.load(.monotonic) > 0.9;
}
fn outGainCentered(app: *App) bool {
    const g = app.st.settings.voice_out_gain;
    return g >= 95 and g <= 105;
}
fn setLowOut(app: *App) void {
    app.st.settings.voice_out_gain = 20;
}
fn sensCentered(app: *App) bool {
    const v = app.st.settings.voice_sens;
    return v >= 48 and v <= 52 and @abs(sh.threshold_db.load(.monotonic) - -40) < 2;
}
fn autoOn(app: *App) bool {
    return app.st.settings.voice_auto and sh.auto.load(.monotonic);
}
fn autoLearns(_: *App) bool {
    // Silêncio digital leva o aprendido ao mínimo; o tom constante o traz para perto.
    return sh.shown_threshold_db.load(.monotonic) > -35;
}
fn autoOff(app: *App) bool {
    return !app.st.settings.voice_auto;
}
fn pinSens(app: *App) void {
    app.st.settings.voice_sens = 77;
}
fn sensHeldInAuto(app: *App) bool {
    return app.st.settings.voice_sens == 77;
}

// --- Aperte para falar -------------------------------------------------------

fn pttOn(app: *App) bool {
    return app.st.settings.voice_ptt and sh.ptt.load(.monotonic) and qa.find("voz-atalho") != null;
}
fn capturing(_: *App) bool {
    return voz_audio.isCapturing();
}
fn notCapturing(_: *App) bool {
    return !voz_audio.isCapturing();
}
fn keyF(app: *App) bool {
    return !voz_audio.isCapturing() and std.mem.eql(u8, app.st.settings.voice_key.slice(), "k:9") and voz.Binding.decode(sh.binding.load(.monotonic)) == .key;
}
fn keepF(app: *App) bool {
    return !voz_audio.isCapturing() and std.mem.eql(u8, app.st.settings.voice_key.slice(), "k:9") and app.st.settings.open;
}
fn keyMouse(app: *App) bool {
    return !voz_audio.isCapturing() and std.mem.eql(u8, app.st.settings.voice_key.slice(), "m:4");
}
fn pttOff(app: *App) bool {
    return !app.st.settings.voice_ptt and qa.find("toggle:Sensibilidade automática") != null;
}
fn highpassOff(_: *App) bool {
    return !sh.highpass.load(.monotonic);
}
fn highpassOn(_: *App) bool {
    return sh.highpass.load(.monotonic);
}
fn gateOn(_: *App) bool {
    return sh.gate.load(.monotonic);
}
fn gateOff(_: *App) bool {
    return !sh.gate.load(.monotonic);
}

// --- Supressão de ruído ------------------------------------------------------

// Branco de 0,05 do fundo de escala: cerca de -31 dB, bem acima do limiar padrão.
fn noiseOn(_: *App) void {
    sh.qa_tone.store(0, .monotonic);
    sh.qa_noise.store(0.05, .monotonic);
}
fn noiseOff(_: *App) void {
    sh.qa_noise.store(0, .monotonic);
}
fn denoiseOff(app: *App) bool {
    return app.st.settings.voice_denoise == 0 and sh.denoise.load(.monotonic) == .off;
}
fn denoiseOn(app: *App) bool {
    return app.st.settings.voice_denoise == 1 and sh.denoise.load(.monotonic) == .rnnoise;
}
fn selectorMarks(_: *App) bool {
    return qa.find("voz-ruido:0") != null and qa.find("voz-ruido:1") != null and qa.find("voz-ruido:2") == null;
}
fn noStates(_: *App) bool {
    return ruido.live.load(.monotonic) == 0;
}
fn oneState(_: *App) bool {
    return ruido.live.load(.monotonic) == 1;
}
fn meterNoisy(_: *App) bool {
    return sh.level_db.load(.monotonic) > -35;
}
fn meterClean(_: *App) bool {
    return sh.level_db.load(.monotonic) < -55;
}
fn loopNoisy(_: *App) bool {
    return sh.test_on.load(.acquire) and sh.loop_db.load(.monotonic) > -35;
}
fn loopClean(_: *App) bool {
    return sh.test_on.load(.acquire) and sh.loop_db.load(.monotonic) < -55;
}
fn micKept(_: *App) bool {
    return sh.mic_opens.load(.monotonic) == opens0;
}
fn setDenoiseOn(app: *App) void {
    app.st.settings.voice_denoise = 1;
}
fn setDenoiseOff(app: *App) void {
    app.st.settings.voice_denoise = 0;
}
fn setUnknownMode(app: *App) void {
    app.st.settings.voice_denoise = 200;
}
fn unknownIsDefault(_: *App) bool {
    return sh.denoise.load(.monotonic) == ruido.Mode.default;
}
fn liveWithoutDrop(app: *App) bool {
    return inCall(app) and sh.mic_opens.load(.monotonic) == opens0;
}
fn offTransmits(app: *App) bool {
    return denoiseOff(app) and noStates(app) and transmitting(app) and liveWithoutDrop(app);
}
fn onSilent(app: *App) bool {
    return denoiseOn(app) and oneState(app) and notTransmitting(app) and liveWithoutDrop(app);
}
fn mutedNoState(app: *App) bool {
    return app.st.muted and noStates(app);
}
fn unmutedState(app: *App) bool {
    return !app.st.muted and oneState(app);
}

fn soundsOff(_: *App) bool {
    return !sh.sounds.load(.monotonic);
}
fn soundsOn(_: *App) bool {
    return sh.sounds.load(.monotonic);
}

// --- Sons de cada evento ------------------------------------------------------

fn keyOf(buf: []u8, comptime fmt: []const u8, e: sons.Event) []const u8 {
    return std.fmt.bufPrint(buf, fmt, .{@tagName(e)}) catch "";
}

fn allEvents(_: *App) bool {
    var b: [56]u8 = undefined;
    for (std.enums.values(sons.Event)) |e| {
        if (qa.find(keyOf(&b, "som-var:{s}", e)) == null) return false;
        if (qa.find(keyOf(&b, "som-play:{s}", e)) == null) return false;
        if (qa.find(keyOf(&b, "som-vol:{s}", e)) == null) return false;
    }
    return true;
}
fn joinOptions(_: *App) bool {
    // Os embutidos e escolher arquivo; "seu arquivo" só depois de escolher um.
    return qa.find("som-opt:join:0") != null and qa.find("som-opt:join:4") != null and qa.find("som-arquivo:join") != null and qa.find("som-opt:join:5") == null;
}
fn variantIs(app: *App, e: sons.Event, v: sons.Variant) bool {
    return S.soundVariantC(&app.st.settings, e) == @backingInt(v) and sh.variant[@backingInt(e)].load(.monotonic) == @backingInt(v);
}
fn joinGlass(app: *App) bool {
    return variantIs(app, .join, .glass);
}
fn joinVolume(app: *App) bool {
    const v = app.st.settings.sound_join_vol;
    return v >= 35 and v <= 65 and sh.volume[@backingInt(sons.Event.join)].load(.monotonic) == v;
}
/// Escreve as configurações como no settings.kdl e lê de volta (o QA não
/// grava o arquivo de verdade).
fn soundsPersist(app: *App) bool {
    const kdl = @import("theme/kdl.zig");
    const gpa = std.heap.c_allocator;
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(gpa);
    S.write(&app.st.settings, "classico", &out, gpa) catch return false;
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const nodes = kdl.parse(arena.allocator(), out.items, null) catch return false;
    var back: S.Settings = .{};
    S.apply(&back, &nodes[0]);
    return back.sound_join == app.st.settings.sound_join and back.sound_join_vol == app.st.settings.sound_join_vol and back.sound_join == @backingInt(sons.Variant.glass);
}
fn muteOff(app: *App) bool {
    return variantIs(app, .mute, .off);
}

const fixture_ok = "qa-out/som-teste.wav";
const fixture_big = "qa-out/som-grande.wav";
const fixture_long = "qa-out/som-longo.wav";
const fixture_junk = "qa-out/som-lixo.wav";
const fixture_ogg = "qa-out/toque-teste.ogg";

fn saveWav(path: [:0]const u8, channels: u16, rate: u32, samples: []const i16) void {
    const gpa = std.heap.c_allocator;
    const bytes = arq.writeWav16(gpa, channels, rate, samples) catch return;
    defer gpa.free(bytes);
    _ = c.SDL_SaveFile(path.ptr, bytes.ptr, bytes.len);
}

fn tone(buf: []i16, channels: usize, rate: u32, hz: f32) void {
    for (buf, 0..) |*x, i| {
        const t = @as(f32, @floatFromInt(i / channels)) / @as(f32, @floatFromInt(rate));
        x.* = @intFromFloat(@sin(2 * std.math.pi * hz * t) * 7000);
    }
}

/// Um Ogg Opus de verdade (libopus), mono, com o tom de `hz`.
fn saveOgg(path: [:0]const u8, seconds: usize, hz: f32) void {
    var err: c_int = 0;
    const enc = c.opus_encoder_create(48000, 1, c.OPUS_APPLICATION_AUDIO, &err) orelse return;
    defer c.opus_encoder_destroy(enc);
    const gpa = std.heap.c_allocator;
    var w: ogg.Writer = .{ .gpa = gpa };
    defer w.out.deinit(gpa);
    var hb: [19]u8 = undefined;
    w.packets(ogg.flag_bos, 0, &.{ogg.opusHead(&hb, 1, 312)}) catch return;
    w.packets(0, 0, &.{"OpusTags\x00\x00\x00\x00\x00\x00\x00\x00"}) catch return;
    const frames = seconds * 50;
    var pcm: [960]i16 = undefined;
    var pkt: [600]u8 = undefined;
    var granule: u64 = 0;
    for (0..frames) |fi| {
        for (&pcm, 0..) |*x, i| {
            const t = @as(f32, @floatFromInt(fi * 960 + i)) / 48000;
            x.* = @intFromFloat(@sin(2 * std.math.pi * hz * t) * 7000);
        }
        const n = c.opus_encode(enc, &pcm, 960, &pkt, pkt.len);
        if (n <= 0) return;
        granule += 960;
        w.packets(if (fi + 1 == frames) ogg.flag_eos else 0, granule, &.{pkt[0..@intCast(n)]}) catch return;
    }
    _ = c.SDL_SaveFile(path.ptr, w.out.items.ptr, w.out.items.len);
}

/// Os arquivos de teste, gerados aqui (nenhum binário no repositório).
fn writeFixtures(_: *App) void {
    _ = c.SDL_CreateDirectory("qa-out");
    const gpa = std.heap.c_allocator;
    // 0,4 s a 22,05 kHz mono: aceito (e passa pela conversão de taxa).
    var short: [8820]i16 = undefined;
    tone(&short, 1, 22050, 880);
    saveWav(fixture_ok, 1, 22050, &short);
    // 12 s de estéreo a 48 kHz: 2,3 MB, passa do teto.
    if (gpa.alloc(i16, 48000 * 2 * 12)) |big| {
        defer gpa.free(big);
        @memset(big, 0);
        saveWav(fixture_big, 2, 48000, big);
    } else |_| {}
    // 6 s a 8 kHz: pequeno, mas longo demais para um aviso.
    var long: [8000 * 6]i16 = undefined;
    tone(&long, 1, 8000, 440);
    saveWav(fixture_long, 1, 8000, &long);
    const junk = "ID3\x04\x00\x00\x00\x00\x00\x00isto seria um MP3";
    _ = c.SDL_SaveFile(fixture_junk, junk.ptr, junk.len);
    // 6 s de Ogg Opus: longo para um aviso, cabe no toque (até 15 s).
    saveOgg(fixture_ogg, 6, 660);
}

fn exists(path: [:0]const u8) bool {
    var info: c.SDL_PathInfo = undefined;
    return c.SDL_GetPathInfo(path.ptr, &info) and info.type == c.SDL_PATHTYPE_FILE;
}
fn fixturesExist(_: *App) bool {
    var info: c.SDL_PathInfo = undefined;
    if (!c.SDL_GetPathInfo(fixture_big, &info) or info.size <= arq.max_bytes) return false;
    return exists(fixture_ok) and exists(fixture_long) and exists(fixture_junk) and exists(fixture_ogg);
}

/// O que o seletor do sistema devolveria (no QA ele não abre).
fn pick(app: *App, path: []const u8) void {
    const z = std.heap.c_allocator.dupeSentinel(u8, path, 0) catch return;
    app.picked.push(z);
    platform.Window.wake(app.win.wake_type, .media);
}
fn pickOk(app: *App) void {
    pick(app, fixture_ok);
}
fn pickBig(app: *App) void {
    pick(app, fixture_big);
}
fn pickLong(app: *App) void {
    pick(app, fixture_long);
}
fn pickJunk(app: *App) void {
    pick(app, fixture_junk);
}
fn pickOgg(app: *App) void {
    pick(app, fixture_ogg);
}

fn leaveCustom(app: *App) bool {
    return variantIs(app, .leave, .custom) and std.mem.eql(u8, app.st.settings.sound_leave_file.slice(), "leave-som-teste.wav") and exists("qa-out/sons/leave-som-teste.wav");
}
fn leaveNamed(_: *App) bool {
    return qa.find("som-nome:leave") != null;
}
fn badBit(e: sons.Event) bool {
    return sh.custom_bad.load(.monotonic) & (@as(u16, 1) << @intCast(@backingInt(e))) != 0;
}
fn leavePlayed(app: *App) bool {
    return soundPlayed(app) and !badBit(.leave);
}
fn toastHas(app: *App, part: []const u8) bool {
    return app.st.toast.is_error and std.mem.indexOf(u8, app.st.toast.text(), part) != null;
}
fn unmuteUntouched(app: *App) bool {
    return variantIs(app, .unmute, .classic) and app.st.settings.sound_unmute_file.len == 0;
}
fn bigRefused(app: *App) bool {
    return toastHas(app, "2 MB") and unmuteUntouched(app);
}
fn longRefused(app: *App) bool {
    return toastHas(app, "5 s") and unmuteUntouched(app);
}
fn junkRefused(app: *App) bool {
    return toastHas(app, "WAV") and unmuteUntouched(app);
}
fn ringCustom(app: *App) bool {
    return variantIs(app, .ring, .custom) and std.mem.eql(u8, app.st.settings.sound_ring_file.slice(), "ring-toque-teste.ogg") and exists("qa-out/sons/ring-toque-teste.ogg");
}
fn ringPlayed(app: *App) bool {
    return soundPlayed(app) and !badBit(.ring);
}
fn removeLeaveCopy(_: *App) void {
    _ = c.SDL_RemovePath("qa-out/sons/leave-som-teste.wav");
}
fn leaveFallback(app: *App) bool {
    // Sumiu: toca o clássico no lugar e a linha avisa.
    return soundPlayed(app) and badBit(.leave) and qa.find("som-nome:leave") != null;
}
fn resetSounds(app: *App) void {
    S.resetSounds(&app.st.settings);
}
fn soundsDefault(_: *App) bool {
    for (std.enums.values(sons.Event)) |e| {
        if (sh.variant[@backingInt(e)].load(.monotonic) != @backingInt(e.defaultVariant())) return false;
    }
    return true;
}

// --- Na call -----------------------------------------------------------------

var sounds0: u32 = 0;
fn markSounds(_: *App) void {
    sounds0 = sh.sounds_played.load(.monotonic);
}
fn soundPlayed(_: *App) bool {
    return sh.sounds_played.load(.monotonic) > sounds0;
}
fn noNewSound(_: *App) bool {
    c.SDL_Delay(60);
    return sh.sounds_played.load(.monotonic) == sounds0;
}
fn join(app: *App) void {
    app.handle(.{ .toggle_voice = call });
}
fn inCall(app: *App) bool {
    return app.st.voice == call and app.st.voice_status == .connected;
}
fn notInCall(app: *App) bool {
    return app.st.voice == null;
}
fn pingShown(app: *App) bool {
    return app.st.voice_ping_ms > 0 and qa.find("voice-ping") != null;
}
/// A linha da pessoa está desenhada? (janela pequena: a lista rola)
fn rowOnScreen(key: []const u8) bool {
    return qa.find(key) != null;
}
fn flagsShown(app: *App) bool {
    // 1003 está mudo pelo servidor na demonstração (a 1001 a bateria geral move).
    if (!app.store.voiceFlags(1003).serverMuted()) return false;
    return !rowOnScreen("voice-member:500014:1003") or qa.find("voice-flagged:1003") != null;
}
fn transmitting(app: *App) bool {
    if (qa.find("voice-transmitting") == null or !app.store.isSpeaking(me, gw.nowMs())) return false;
    // O anel também aparece para si mesmo, com a linha à vista.
    return !rowOnScreen("voice-member:500014:1000") or qa.find("voice-speaking:1000") != null;
}
fn notTransmitting(app: *App) bool {
    return qa.find("voice-transmitting") == null and qa.find("voice-speaking:1000") == null and !app.store.isSpeaking(me, gw.nowMs());
}
fn setPtt(app: *App) void {
    app.st.settings.voice_ptt = true;
    app.st.settings.voice_key.set("k:9");
}
fn setPttMouse(app: *App) void {
    app.st.settings.voice_ptt = true;
    app.st.settings.voice_key.set("m:4");
}
fn clearPtt(app: *App) void {
    app.st.settings.voice_ptt = false;
}
fn failMic(_: *App) void {
    sh.qa_fail_mic.store(true, .monotonic);
}
fn healMic(_: *App) void {
    sh.qa_fail_mic.store(false, .monotonic);
}
fn micWarned(app: *App) bool {
    return app.st.voice_mic_failed and qa.find("voice-warning") != null;
}
fn micHealed(app: *App) bool {
    return !app.st.voice_mic_failed and qa.find("voice-warning") == null;
}
fn serverMute(app: *App) void {
    pushFlags(app, .{ .mute = true });
}
fn serverDeaf(app: *App) void {
    pushFlags(app, .{ .deaf = true });
}
fn serverClear(app: *App) void {
    pushFlags(app, .{});
}
fn serverMutedShown(_: *App) bool {
    return sh.server_mute.load(.acquire) and qa.find("user-forced:0") != null and qa.find("voice-warning") != null;
}
fn serverDeafShown(_: *App) bool {
    return sh.server_deaf.load(.acquire) and qa.find("user-forced:1") != null and qa.find("voice-warning") != null;
}
fn serverCleared(_: *App) bool {
    return !sh.server_mute.load(.acquire) and !sh.server_deaf.load(.acquire) and qa.find("user-forced:0") == null;
}
fn voicePage(app: *App) bool {
    return app.st.settings.open and app.st.settings.page == .voz;
}

var out0: u32 = 0;
fn switchDevices(app: *App) void {
    opens0 = sh.mic_opens.load(.monotonic);
    out0 = sh.out_opens.load(.monotonic);
    app.st.settings.voice_mic.set(dev_in.slice(0));
    app.st.settings.voice_out.set(dev_out.slice(0));
}
fn switchedLive(app: *App) bool {
    return sh.mic_opens.load(.monotonic) > opens0 and sh.out_opens.load(.monotonic) > out0 and app.st.voice_status == .connected and app.st.voice == call;
}
fn gain30(app: *App) void {
    app.st.settings.voice_in_gain = 100;
    app.st.settings.voice_sens = 100;
}
fn belowThreshold(_: *App) bool {
    return qa.find("voice-transmitting") == null;
}
fn sensBack(app: *App) void {
    app.st.settings.voice_sens = voz.default_sens;
}

/// O DAVE gera o pacote de chaves do MLS (par P-256, assinatura ECDSA, SHA-256) com
/// o OpenSSL que vai no binário: um OpenSSL sem algum algoritmo da voz falha aqui.
fn daveKeyPackage(_: *App) bool {
    const session = c.daveSessionCreate(null, "", null, null);
    if (session == null) return false;
    defer c.daveSessionDestroy(session);
    c.daveSessionInit(session, c.daveMaxSupportedProtocolVersion(), call, "1000");
    var p: [*c]u8 = null;
    var n: usize = 0;
    c.daveSessionGetMarshalledKeyPackage(session, &p, &n);
    if (p == null) return false;
    c.daveFree(p);
    return n > 64;
}

pub const ops = [_]Op{
    s("voz: DAVE"),
    expect("o MLS do DAVE gera o pacote de chaves", daveKeyPackage),

    s("voz: página"),
    run(resetAll),
    click("user-btn:2"),
    expect("abrir as configurações", settingsOpen),
    click("settings:Voz"),
    expect("a página de voz abre e liga o medidor", pageOpen),
    expect("tudo da página aparece", pageMarks),
    .{ .expect = .{ .name = "a lista de dispositivos chega da thread de áudio", .check = devicesListed, .timeout_ms = 3000 } },
    expectLong("microfone abre no driver mudo e o medidor mostra silêncio", meterQuiet),
    shot("voz-pagina"),

    s("voz: medidor e teste"),
    run(toneOn),
    expect("o medidor sobe com som no microfone", meterLoud),
    shot("voz-medidor"),
    run(markLoop),
    click("button:Testar microfone"),
    expect("Testar microfone toca de volta", testRuns),
    shot("voz-teste"),
    click("button:Parar teste"),
    expect("Parar teste desliga", testStopped),
    expect("parado, nada mais volta para a saída", testStoppedKeepsCounter),
    click("button:Testar microfone"),
    click("settings:Chat"),
    expect("sair da página desliga o teste e o medidor", leftPage),
    expect("o medidor zera fora da página", levelReset),
    click("settings:Voz"),
    expect("voltar à página liga o medidor de novo", pageOpen),
    expect("o medidor volta a subir", meterLoud),

    s("voz: dispositivos"),
    click("voz-mic"),
    expect("a lista de microfones abre com o padrão do sistema", micOptions),
    shot("voz-dispositivos"),
    run(markOpens),
    click("voz-mic-opt:1"),
    expect("escolher um microfone salva o nome", micNamed),
    expect("escolher um microfone reabre na hora", micReopened),
    click("voz-mic"),
    click("voz-mic-opt:0"),
    expect("voltar ao padrão do sistema", micDefault),
    click("voz-out"),
    expect("a lista de saídas abre", outOptions),
    click("voz-out-opt:1"),
    expect("escolher uma saída salva o nome", outNamed),
    click("voz-out"),
    click("voz-out-opt:0"),
    expect("saída de volta ao padrão", outDefault),
    run(setGoneMic),
    .{ .expect = .{ .name = "microfone salvo que sumiu: avisa e usa o padrão", .check = goneFallsBack, .timeout_ms = 3000 } },
    shot("voz-sumiu"),
    run(clearMic),
    expect("sem escolha, sem aviso", noFallback),

    s("voz: volume e sensibilidade"),
    run(lowGain),
    expect("o volume de entrada muda o nível medido", levelDropped),
    click("voz-vol:10"),
    expect("o controle de entrada responde ao mouse", gainCentered),
    run(setLowOut),
    click("voz-vol:11"),
    expect("o controle de saída responde ao mouse", outGainCentered),
    click("voz-sens"),
    expect("arrastar a marca muda o limiar da detecção", sensCentered),
    run(pinSens),
    click("toggle:Sensibilidade automática"),
    expect("modo automático liga", autoOn),
    expectLong("no automático o limiar acompanha o ruído (aqui, o tom constante)", autoLearns),
    click("voz-sens"),
    expect("no automático a barra não muda o limiar", sensHeldInAuto),
    shot("voz-automatico"),
    click("toggle:Sensibilidade automática"),
    expect("modo automático desliga", autoOff),
    run(sensBack),

    s("voz: aperte para falar"),
    click("voz-modo:1"),
    expect("o modo aperte para falar mostra o atalho", pttOn),
    click("voz-atalho"),
    expect("clicar no atalho espera uma tecla", capturing),
    shot("voz-atalho-esperando"),
    run(fDown),
    run(fUp),
    expect("a tecla apertada vira o atalho", keyF),
    shot("voz-atalho"),
    click("voz-atalho"),
    expect("trocar de novo espera outra tecla", capturing),
    run(escTap),
    expect("Esc cancela sem mudar nem fechar a tela", keepF),
    click("voz-atalho"),
    click("voz-atalho"),
    expect("clicar de novo cancela", notCapturing),
    click("voz-atalho"),
    run(x1Tap),
    expect("botão do mouse também serve", keyMouse),
    click("voz-modo:0"),
    expect("volta para a detecção de voz", pttOff),

    s("voz: filtros e sons"),
    click("toggle:Tirar ronco (passa-altas)"),
    expect("desliga o passa-altas", highpassOff),
    click("toggle:Tirar ronco (passa-altas)"),
    expect("liga o passa-altas", highpassOn),
    click("toggle:Porta de ruído"),
    expect("liga a porta de ruído", gateOn),
    click("toggle:Porta de ruído"),
    expect("desliga a porta de ruído", gateOff),
    click("toggle:Sons da call"),
    expect("desliga os sons", soundsOff),
    click("toggle:Sons da call"),
    expect("liga os sons", soundsOn),
    run(toneOff),

    s("voz: sons de cada evento"),
    expect("a seção mostra todos os eventos, com escolha, Ouvir e volume", allEvents),
    click("som-var:join"),
    expect("a lista tem os embutidos e escolher arquivo", joinOptions),
    shot("voz-sons-lista"),
    run(markSounds),
    click("som-opt:join:3"),
    expect("escolher Cristal vale para o áudio", joinGlass),
    expect("escolher um som toca ele na hora", soundPlayed),
    .{ .click = .{ .at = .{ .key = "som-vol:join", .fx = 0.25, .fy = 0.5 } } },
    expect("o volume do som responde ao mouse", joinVolume),
    expect("variante e volume vão e voltam pelo settings.kdl", soundsPersist),
    run(markSounds),
    click("som-play:join"),
    expect("Ouvir toca o som (no driver mudo, sem dispositivo de verdade)", soundPlayed),
    click("toggle:Sons da call"),
    expect("sons da call desligados", soundsOff),
    run(markSounds),
    click("som-play:join"),
    expect("Ouvir toca mesmo com os sons da call desligados", soundPlayed),
    click("toggle:Sons da call"),
    expect("sons da call ligados de novo", soundsOn),
    click("som-var:mute"),
    click("som-opt:mute:0"),
    expect("desligar só o som de mutar", muteOff),
    run(markSounds),
    click("som-play:mute"),
    expect("desligado, Ouvir não toca nada", noNewSound),
    run(writeFixtures),
    expect("os arquivos de teste foram gerados", fixturesExist),
    click("som-var:leave"),
    click("som-arquivo:leave"),
    run(pickOk),
    expect("WAV curto é aceito, copiado para a pasta dos sons e escolhido", leaveCustom),
    expect("o nome do arquivo aparece na linha", leaveNamed),
    run(markSounds),
    click("som-play:leave"),
    expect("Ouvir toca o arquivo", leavePlayed),
    click("som-var:unmute"),
    click("som-arquivo:unmute"),
    run(pickBig),
    expect("arquivo de mais de 2 MB é recusado, com o motivo", bigRefused),
    click("som-var:unmute"),
    click("som-arquivo:unmute"),
    run(pickLong),
    expect("som de mais de 5 s é recusado, com o motivo", longRefused),
    click("som-var:unmute"),
    click("som-arquivo:unmute"),
    run(pickJunk),
    expect("arquivo que não é WAV nem Ogg Opus é recusado", junkRefused),
    click("som-var:ring"),
    click("som-arquivo:ring"),
    run(pickOgg),
    expect("Ogg Opus de 6 s vale para o toque (até 15 s)", ringCustom),
    run(markSounds),
    click("som-play:ring"),
    expect("Ouvir toca o toque do arquivo (libopus)", ringPlayed),
    shot("voz-sons-arquivo"),
    run(removeLeaveCopy),
    run(markSounds),
    click("som-play:leave"),
    expect("arquivo que sumiu: toca o clássico e a linha avisa", leaveFallback),
    run(resetSounds),
    expect("de volta ao que tocava antes", soundsDefault),

    s("voz: supressão de ruído"),
    expect("o seletor mostra só o que funciona", selectorMarks),
    expect("desligada: o medidor não cria o estado", noStates),
    run(noiseOn),
    expect("desligada: o medidor mostra o ruído", meterNoisy),
    run(markLoop),
    click("button:Testar microfone"),
    expect("o teste do microfone toca", testRuns),
    expect("desligada: o teste devolve o ruído", loopNoisy),
    run(markOpens),
    click("voz-ruido:1"),
    expect("escolher RNNoise vale para o áudio", denoiseOn),
    expect("o estado nasce quando liga", oneState),
    expectLong("ligada: o medidor mostra o som limpo", meterClean),
    expect("ligada: o teste do microfone devolve o som limpo", loopClean),
    shot("voz-supressao"),
    click("voz-ruido:0"),
    expect("desligar vale para o áudio", denoiseOff),
    expect("desligar solta o estado", noStates),
    expect("desligada de novo: o ruído volta ao medidor", meterNoisy),
    expect("desligada de novo: o ruído volta ao teste", loopNoisy),
    expect("trocar não reabre o microfone", micKept),
    run(setUnknownMode),
    expect("número desconhecido no arquivo cai no padrão", unknownIsDefault),
    run(setDenoiseOff),
    click("button:Parar teste"),
    expect("parar o teste", testStopped),
    run(noiseOff),
    click("settings-close"),
    expect("fechar as configurações", settingsClosed),
    expect("fechar desliga o medidor", leftPage),

    s("voz: na call"),
    run(markSounds),
    run(join),
    expect("entrar na call", inCall),
    expect("som de entrar", soundPlayed),
    expect("ping da call no painel", pingShown),
    expect("mudo e surdo dos outros na lista", flagsShown),
    expect("calado não transmite", notTransmitting),
    shot("voz-call"),
    run(toneOn),
    expect("falando: o anel aparece para si mesmo e o painel diz transmitindo", transmitting),
    shot("voz-transmitindo"),
    .{ .wait = 4500 },
    expect("fala longa: o anel não apaga sozinho", transmitting),
    run(toneOff),
    expect("parou de falar: o anel apaga", notTransmitting),
    run(toneOn),
    expect("falando de novo", transmitting),
    run(markSounds),
    click("user-btn:0"),
    expect("mudo não transmite", notTransmitting),
    expect("som de mutar", soundPlayed),
    run(markSounds),
    click("user-btn:0"),
    expect("desmutar volta a transmitir", transmitting),
    expect("som de desmutar", soundPlayed),
    run(gain30),
    expect("com o limiar acima do nível, não transmite", belowThreshold),
    run(sensBack),
    expect("limiar normal: transmite", transmitting),

    s("voz: aperte para falar na call"),
    run(setPtt),
    expect("sem a tecla não transmite, mesmo com som", notTransmitting),
    shot("voz-ptt"),
    run(fDown),
    expect("a tecla apertada transmite", transmitting),
    run(fUp),
    expect("soltar para de transmitir", notTransmitting),
    run(fDown),
    expect("apertada de novo", transmitting),
    run(focusLost),
    expect("perder o foco solta a tecla", notTransmitting),
    run(fUp),
    run(gDown),
    .{ .wait = 80 },
    expect("outra tecla não transmite", notTransmitting),
    run(setPttMouse),
    run(x1Down),
    expect("botão do mouse como atalho transmite", transmitting),
    run(focusLost),
    expect("sem foco, o botão também solta", notTransmitting),
    run(clearPtt),

    s("voz: avisos"),
    run(failMic),
    expect("microfone que não abre: aviso claro no painel", micWarned),
    shot("voz-sem-microfone"),
    expect("sem microfone não transmite", notTransmitting),
    run(healMic),
    expectLong("microfone volta sozinho e o aviso some", micHealed),
    expect("transmite de novo", transmitting),
    run(serverMute),
    expect("mudo pelo servidor: ícone e aviso", serverMutedShown),
    expect("mudo pelo servidor não transmite", notTransmitting),
    shot("voz-mudo-servidor"),
    run(serverDeaf),
    expect("surdo pelo servidor: ícone e aviso", serverDeafShown),
    expect("surdo pelo servidor não transmite", notTransmitting),
    run(serverClear),
    expect("o servidor libera: some o aviso", serverCleared),
    expect("liberado, transmite de novo", transmitting),

    s("voz: supressão em plena call"),
    run(toneOff),
    run(noiseOn),
    run(markOpens),
    expect("desligada: o ruído abre o microfone", offTransmits),
    run(setDenoiseOn),
    expectLong("ligada na call: ruído limpo não abre o microfone, sem cair", onSilent),
    shot("voz-supressao-call"),
    click("user-btn:0"),
    expect("mudo solta o estado", mutedNoState),
    click("user-btn:0"),
    expect("desmutar cria de novo", unmutedState),
    run(setDenoiseOff),
    expectLong("desligada na call: o ruído volta a abrir, sem cair", offTransmits),
    run(noiseOff),
    run(toneOn),
    expect("o tom volta a transmitir", transmitting),

    s("voz: trocar em plena call"),
    run(switchDevices),
    expect("troca microfone e saída sem cair da call", switchedLive),
    expect("depois da troca continua transmitindo", transmitting),
    run(toneOff),
    run(clearMic),
    click("voice-line"),
    expect("a linha do painel abre a página de voz", voicePage),
    click("settings-close"),
    expect("fecha", settingsClosed),
} ++ @import("qa_dispositivos.zig").ops_call ++ [_]Op{
    run(markSounds),
    click("hangup"),
    expect("sair da call", notInCall),
    expect("som de sair", soundPlayed),

    s("voz: sons desligados"),
    click("user-btn:2"),
    click("settings:Voz"),
    click("toggle:Sons da call"),
    expect("sons desligados", soundsOff),
    click("settings-close"),
    run(markSounds),
    run(join),
    expect("entra na call", inCall),
    click("user-btn:0"),
    click("user-btn:0"),
    click("hangup"),
    expect("sai da call", notInCall),
    expect("sem nenhum som", noNewSound),
    run(resetAll),
    .{ .wait = 50 },
};
