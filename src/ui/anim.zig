//! Animações por id: cada valor se aproxima do alvo com easing exponencial.
//! `active` indica se algo ainda está se movendo, para o loop continuar
//! desenhando; quando tudo para, o app volta a dormir esperando eventos.
const std = @import("std");

var values: std.AutoHashMapUnmanaged(u32, f32) = .empty;

pub var dt: f32 = 1.0 / 60.0;
pub var active: bool = false;
/// "Reduzir movimento": tudo chega no alvo na hora.
pub var instant: bool = false;
/// Relógio do quadro (ms), atualizado pelo app.
pub var now_ms: i64 = 0;
/// Próximo redesenho pedido por algo que anda devagar (pontinhos de
/// "digitando", esqueletos de carregamento): o app dorme até lá em vez de
/// desenhar a 60 quadros por segundo. Zerado a cada quadro.
pub var next_wake_ms: i64 = std.math.maxInt(i64);

/// Redesenha a cada `period_ms` enquanto quem chama continuar na tela.
pub fn every(period_ms: i64) void {
    at(now_ms - @mod(now_ms, period_ms) + period_ms);
}

/// Redesenha em `t` (ms).
pub fn at(t: i64) void {
    next_wake_ms = @min(next_wake_ms, t);
}

/// Quanto o app dorme esperando um redesenho pedido para daqui a `wait_ms`. Perto, no
/// máximo 1 s por vez: o relógio do sistema pode pular, e o prazo não atrasa mais que
/// isso. Longe (status personalizado que expira em horas, castigo de dias), até 1 min
/// antes dele, de uma vez: um pulo do relógio maior que isso muda o minuto, e o tique do
/// minuto acorda o app de qualquer jeito.
pub fn sleepFor(wait_ms: i64) i64 {
    if (wait_ms <= 60_000) return @min(wait_ms, 1000);
    return @min(wait_ms - 60_000, std.math.maxInt(i32));
}

pub fn id(comptime tag: []const u8, n: u64) u32 {
    return @truncate(std.hash.Wyhash.hash(n, tag));
}

/// Esquece as animações quando o mapa cresce demais (uma chave por membro,
/// mensagem, canal… acumula numa sessão longa). Só com tudo parado: quem
/// voltar começa já no alvo, sem pulo visível.
pub fn trim() void {
    if (values.count() > 4096 and !active) values.clearRetainingCapacity();
}

/// Aproxima o valor `key` de `target`. `speed` maior = mais rápido.
pub fn to(key: u32, target: f32, speed: f32) f32 {
    trim();
    const gop = values.getOrPut(std.heap.c_allocator, key) catch return target;
    if (!gop.found_existing) {
        gop.value_ptr.* = target;
        return target;
    }
    gop.value_ptr.* = step(gop.value_ptr.*, target, speed);
    return gop.value_ptr.*;
}

/// Mesmo easing de `to`, para valores guardados fora do mapa.
pub fn step(value: f32, target: f32, speed: f32) f32 {
    // Já no alvo (quase sempre: cada hover da tela passa aqui a cada quadro): sem
    // o `@exp`, que é a parte cara. O resultado é o mesmo do caminho de baixo.
    if (instant or value == target) return target;
    const k = 1.0 - @exp(-speed * dt);
    const v = value + (target - value) * k;
    // `v == value`: o passo ficou menor que a precisão do f32 (rolagem alta com
    // muitos quadros por segundo). Sem isso, nunca chega e o app não dorme mais.
    if (@abs(target - v) < 0.01 or v == value) return target;
    active = true;
    return v;
}

test "prazo longe não acorda o app a cada segundo" {
    try std.testing.expectEqual(@as(i64, 250), sleepFor(250));
    try std.testing.expectEqual(@as(i64, 1000), sleepFor(30_000));
    try std.testing.expectEqual(@as(i64, 1000), sleepFor(60_000));
    // Status que expira em 3 h: uma espera só até faltar 1 min, depois de segundo em segundo.
    const three_h: i64 = 3 * 3_600_000;
    try std.testing.expectEqual(three_h - 60_000, sleepFor(three_h));
    var left = three_h;
    var wakes: usize = 0;
    while (left > 0) : (wakes += 1) left -= sleepFor(left);
    try std.testing.expect(wakes <= 62);
    // Castigo de semanas: cabe no inteiro que o SDL recebe.
    try std.testing.expectEqual(@as(i64, std.math.maxInt(i32)), sleepFor(40 * 86_400_000));
}

test "passo menor que a precisão do f32 termina" {
    instant = false;
    dt = 0.001;
    active = false;
    try std.testing.expectEqual(@as(f32, 15847.22), step(15847.197, 15847.22, 18));
    try std.testing.expect(!active);
}

test "já no alvo: devolve o alvo sem marcar animação" {
    instant = false;
    dt = 1.0 / 60.0;
    active = false;
    try std.testing.expectEqual(@as(f32, 42), step(42, 42, 18));
    try std.testing.expect(!active);
    // Fora do alvo continua andando (e pedindo quadro).
    const v = step(0, 42, 18);
    try std.testing.expect(v > 0 and v < 42);
    try std.testing.expect(active);
}
