//! Mede o custo do supressor por quadro de 10 ms: `zig build ruido-custo`
//! (otimizado como o app; -Doptimize=small mede o outro modo). Só para quem
//! desenvolve; não entra no app.
const std = @import("std");
const voz = @import("voz.zig");
const ruido = @import("ruido.zig");

const Ts = extern struct { sec: i64, nsec: c_long };
extern fn timespec_get(ts: *Ts, base: c_int) c_int;

fn seconds() f64 {
    var t: Ts = undefined;
    _ = timespec_get(&t, 1);
    return @as(f64, @floatFromInt(t.sec)) + @as(f64, @floatFromInt(t.nsec)) * 1e-9;
}

fn fill(pcm: []i16, seed: *u32, amp: f32) void {
    var i: usize = 0;
    while (i < pcm.len) : (i += voz.channels) {
        seed.* = seed.* *% 1664525 +% 1013904223;
        const u = @as(f32, @floatFromInt(seed.* >> 8)) / (1 << 24);
        const v: i16 = @intFromFloat((u * 2 - 1) * amp);
        pcm[i] = v;
        pcm[i + 1] = v;
    }
}

/// Só o supressor, ou a captura inteira (volume, passa-altas, supressor, nível e
/// porta), que é o que a thread de áudio roda a cada quadro.
fn step(cap: *voz.Capture, pcm: []i16, mode: ruido.Mode, captura: bool) void {
    if (captura) {
        _ = cap.process(pcm, .{ .gain = 1.2, .gate = true, .denoise = mode });
    } else _ = cap.ns.process(pcm, mode);
}

/// Pior e melhor de 5 rodadas de 10 s de áudio (a máquina pode estar ocupada:
/// a melhor é o custo do código; a pior, o que se viu com ela carregada).
fn measure(name: []const u8, mode: ruido.Mode, amp: f32, captura: bool) void {
    var cap: voz.Capture = .{};
    defer cap.release();
    var pcm: [voz.frame_len]i16 = undefined;
    var seed: u32 = 12345;
    // Assenta antes de medir (no silêncio é aqui que a cauda decairia).
    for (0..500) |_| {
        fill(&pcm, &seed, amp);
        step(&cap, &pcm, mode, captura);
    }
    const frames = 500;
    var best: f64 = 1e9;
    var worst: f64 = 0;
    for (0..5) |_| {
        var spent: f64 = 0;
        for (0..frames) |_| {
            fill(&pcm, &seed, amp);
            const t0 = seconds();
            step(&cap, &pcm, mode, captura);
            spent += seconds() - t0;
        }
        const per10 = spent / (frames * voz.frame_ms / 10);
        best = @min(best, per10);
        worst = @max(worst, per10);
    }
    std.debug.print("{s}: {d:.1} us por 10 ms = {d:.2}% de um núcleo (pior rodada {d:.2}%)\n", .{ name, best * 1e6, best / 0.01 * 100, worst / 0.01 * 100 });
}

pub fn main() void {
    measure("RNNoise, ruído alto", .rnnoise, 3000, false);
    measure("RNNoise, ruído baixo", .rnnoise, 30, false);
    measure("RNNoise, quase nada (1 LSB)", .rnnoise, 2, false);
    measure("RNNoise, silêncio digital", .rnnoise, 0, false);
    measure("desligado", .off, 3000, false);
    measure("captura inteira, com RNNoise", .rnnoise, 3000, true);
    measure("captura inteira, sem supressor", .off, 3000, true);
}
