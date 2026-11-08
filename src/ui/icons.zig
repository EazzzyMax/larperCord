//! Ícones vetoriais simples desenhados direto no ImDrawList.
const std = @import("std");
const c = @import("c");

const pi = std.math.pi;

fn v(x: f32, y: f32) c.ImVec2 {
    return .{ .x = x, .y = y };
}

fn line(dl: *c.ImDrawList, x1: f32, y1: f32, x2: f32, y2: f32, col: u32, th: f32) void {
    c.ImDrawList_AddLineEx(dl, v(x1, y1), v(x2, y2), col, th, 0);
}

fn arc(dl: *c.ImDrawList, cx: f32, cy: f32, r: f32, a0: f32, a1: f32, col: u32, th: f32) void {
    c.ImDrawList_PathClear(dl);
    c.ImDrawList_PathArcTo(dl, v(cx, cy), r, a0, a1, 0);
    c.ImDrawList_PathStroke(dl, col, th, 0);
}

/// Ícones centrados em (cx, cy), cabendo num quadrado de ~20px.
pub fn mic(dl: *c.ImDrawList, cx: f32, cy: f32, col: u32) void {
    c.ImDrawList_AddRectFilledEx(dl, v(cx - 3.5, cy - 9), v(cx + 3.5, cy + 3), col, 3.5, 0);
    arc(dl, cx, cy - 1, 6.5, 0, pi, col, 1.8);
    line(dl, cx, cy + 5.5, cx, cy + 9, col, 1.8);
    line(dl, cx - 3.5, cy + 9, cx + 3.5, cy + 9, col, 1.8);
}

pub fn headset(dl: *c.ImDrawList, cx: f32, cy: f32, col: u32) void {
    arc(dl, cx, cy + 1, 7.5, pi, 2 * pi, col, 1.9);
    c.ImDrawList_AddRectFilledEx(dl, v(cx - 9, cy), v(cx - 5, cy + 8), col, 2, 0);
    c.ImDrawList_AddRectFilledEx(dl, v(cx + 5, cy), v(cx + 9, cy + 8), col, 2, 0);
}

pub fn gear(dl: *c.ImDrawList, cx: f32, cy: f32, col: u32) void {
    var i: usize = 0;
    while (i < 8) : (i += 1) {
        const a = @as(f32, @floatFromInt(i)) * pi / 4.0;
        line(dl, cx + @cos(a) * 5.5, cy + @sin(a) * 5.5, cx + @cos(a) * 8.7, cy + @sin(a) * 8.7, col, 2.8);
    }
    c.ImDrawList_AddCircleEx(dl, v(cx, cy), 5, col, 0, 2.2, 0);
}

/// Alfinete em traço, em pé: chapéu, corpo que abre e a ponta.
pub fn pin(dl: *c.ImDrawList, cx_in: f32, cy_in: f32, col: u32) void {
    const cx = @round(cx_in);
    const cy = @round(cy_in);
    const th: f32 = 1.7;
    const pts = [_]c.ImVec2{
        v(cx - 3.5, cy - 8), v(cx + 3.5, cy - 8), v(cx + 3.5, cy - 6), v(cx + 2.5, cy - 5),
        v(cx + 2.5, cy - 1), v(cx + 6, cy + 2.5), v(cx + 6, cy + 4),   v(cx - 6, cy + 4),
        v(cx - 6, cy + 2.5), v(cx - 2.5, cy - 1), v(cx - 2.5, cy - 5), v(cx - 3.5, cy - 6),
    };
    c.ImDrawList_AddPolyline(dl, &pts[0], pts.len, col, th, c.ImDrawFlags_Closed);
    line(dl, cx, cy + 4, cx, cy + 9, col, th);
}

/// Estrela de 5 pontas de raio `r`; cheia (favorito) ou só o contorno.
pub fn star(dl: *c.ImDrawList, cx: f32, cy: f32, r: f32, col: u32, filled: bool) void {
    var pts: [10]c.ImVec2 = undefined;
    for (&pts, 0..) |*p, i| {
        const a = -pi / 2.0 + @as(f32, @floatFromInt(i)) * pi / 5.0;
        const rr = if (i % 2 == 0) r else r * 0.46;
        p.* = v(cx + @cos(a) * rr, cy + @sin(a) * rr);
    }
    if (filled) c.ImDrawList_AddConcavePolyFilled(dl, &pts[0], pts.len, col);
    c.ImDrawList_AddPolyline(dl, &pts[0], pts.len, col, 1.6, c.ImDrawFlags_Closed);
}

pub fn search(dl: *c.ImDrawList, cx: f32, cy: f32, col: u32) void {
    c.ImDrawList_AddCircleEx(dl, v(cx - 1.5, cy - 1.5), 5, col, 0, 1.7, 0);
    line(dl, cx + 2, cy + 2, cx + 6, cy + 6, col, 1.7);
}

pub fn speaker(dl: *c.ImDrawList, cx: f32, cy: f32, col: u32) void {
    c.ImDrawList_PathClear(dl);
    c.ImDrawList_PathLineTo(dl, v(cx - 8, cy - 3));
    c.ImDrawList_PathLineTo(dl, v(cx - 4.5, cy - 3));
    c.ImDrawList_PathLineTo(dl, v(cx + 0.5, cy - 7.5));
    c.ImDrawList_PathLineTo(dl, v(cx + 0.5, cy + 7.5));
    c.ImDrawList_PathLineTo(dl, v(cx - 4.5, cy + 3));
    c.ImDrawList_PathLineTo(dl, v(cx - 8, cy + 3));
    c.ImDrawList_PathFillConvex(dl, col, 0);
    arc(dl, cx + 1, cy, 4.5, -pi / 3.5, pi / 3.5, col, 1.7);
    arc(dl, cx + 1, cy, 8, -pi / 3.2, pi / 3.2, col, 1.7);
}

pub fn chevron(dl: *c.ImDrawList, cx: f32, cy: f32, col: u32, open: f32) void {
    // open = 0 aponta para a direita, 1 aponta para baixo.
    const a = open * pi / 2.0;
    const ca = @cos(a);
    const sa = @sin(a);
    const pts = [_][2]f32{ .{ -2, -4 }, .{ 2, 0 }, .{ -2, 4 } };
    var p: [3]c.ImVec2 = undefined;
    for (pts, 0..) |q, i| p[i] = v(cx + q[0] * ca - q[1] * sa, cy + q[0] * sa + q[1] * ca);
    line(dl, p[0].x, p[0].y, p[1].x, p[1].y, col, 1.6);
    line(dl, p[1].x, p[1].y, p[2].x, p[2].y, col, 1.6);
}

pub fn plus(dl: *c.ImDrawList, cx: f32, cy: f32, r: f32, col: u32) void {
    line(dl, cx - r, cy, cx + r, cy, col, 2);
    line(dl, cx, cy - r, cx, cy + r, col, 2);
}

/// Uma pessoa com um "+" ao lado: adicionar amigo.
pub fn addFriend(dl: *c.ImDrawList, cx_in: f32, cy_in: f32, col: u32) void {
    const cx = @round(cx_in) - 2;
    const cy = @round(cy_in);
    c.ImDrawList_AddCircleEx(dl, v(cx, cy - 3), 3, col, 0, 1.6, 0);
    c.ImDrawList_PathClear(dl);
    c.ImDrawList_PathArcTo(dl, v(cx, cy + 7), 5.5, -pi, 0, 0);
    c.ImDrawList_PathStroke(dl, col, 1.6, 0);
    plus(dl, cx + 7.5, cy - 1, 2.5, col);
}

/// Duas pessoas (amigos, lista de membros).
pub fn members(dl: *c.ImDrawList, cx: f32, cy: f32, col: u32) void {
    people(dl, cx, cy, 0.8, 1.7, col);
}

/// Duas pessoas em traço: a da frente inteira e, ao lado dela, só o que aparece
/// da de trás. Nada se cruza, então o desenho fica limpo em qualquer fundo.
/// Desenhado numa grade de 24, em `s` pixels por unidade, centrado em (cx, cy).
pub fn people(dl: *c.ImDrawList, cx_in: f32, cy_in: f32, s: f32, th: f32, col: u32) void {
    const cx = @round(cx_in);
    const cy = @round(cy_in);
    const P = struct {
        cx: f32,
        cy: f32,
        s: f32,
        fn at(g: @This(), x: f32, y: f32) c.ImVec2 {
            return v(g.cx + (x - 12) * g.s, g.cy + (y - 12) * g.s);
        }
    };
    const g: P = .{ .cx = cx, .cy = cy, .s = s };
    // A cabeça da frente.
    const head = g.at(9, 7);
    c.ImDrawList_AddCircleEx(dl, head, 4 * s, col, 0, th, 0);
    // Os ombros da frente.
    c.ImDrawList_PathClear(dl);
    c.ImDrawList_PathLineTo(dl, g.at(16, 21));
    c.ImDrawList_PathArcTo(dl, g.at(12, 19), 4 * s, 0, -pi / 2.0, 0);
    c.ImDrawList_PathArcTo(dl, g.at(6, 19), 4 * s, -pi / 2.0, -pi, 0);
    c.ImDrawList_PathLineTo(dl, g.at(2, 21));
    c.ImDrawList_PathStroke(dl, col, th, 0);
    // De trás: o lado da cabeça e o ombro.
    arc(dl, g.at(15, 7).x, g.at(15, 7).y, 4 * s, -1.32, 1.32, col, th);
    c.ImDrawList_PathClear(dl);
    c.ImDrawList_PathLineTo(dl, g.at(22, 21));
    c.ImDrawList_PathArcTo(dl, g.at(18, 19), 4 * s, 0, -1.32, 0);
    c.ImDrawList_PathStroke(dl, col, th, 0);
}

/// Duas setas saindo do centro: abrir em tamanho maior.
pub fn expand(dl: *c.ImDrawList, cx_in: f32, cy_in: f32, col: u32) void {
    const cx = @round(cx_in);
    const cy = @round(cy_in);
    const th: f32 = 1.5;
    line(dl, cx + 1, cy - 1, cx + 5, cy - 5, col, th);
    line(dl, cx + 1.5, cy - 5, cx + 5, cy - 5, col, th);
    line(dl, cx + 5, cy - 5, cx + 5, cy - 1.5, col, th);
    line(dl, cx - 1, cy + 1, cx - 5, cy + 5, col, th);
    line(dl, cx - 1.5, cy + 5, cx - 5, cy + 5, col, th);
    line(dl, cx - 5, cy + 5, cx - 5, cy + 1.5, col, th);
}

/// Balão de conversa em traço (mandar mensagem).
pub fn message(dl: *c.ImDrawList, cx_in: f32, cy_in: f32, col: u32) void {
    const cx = @round(cx_in);
    const cy = @round(cy_in);
    const th: f32 = 1.7;
    c.ImDrawList_AddRectEx(dl, v(cx - 7.5, cy - 6.5), v(cx + 7.5, cy + 4.5), col, 3.5, th, 0);
    line(dl, cx - 3.5, cy + 4.5, cx - 5, cy + 8, col, th);
    line(dl, cx - 5, cy + 8, cx - 0.5, cy + 4.5, col, th);
}

/// Cadeado (canal sem acesso).
pub fn lock(dl: *c.ImDrawList, cx: f32, cy: f32, col: u32) void {
    c.ImDrawList_AddRectFilledEx(dl, v(cx - 5.5, cy - 1), v(cx + 5.5, cy + 7), col, 2, 0);
    arc(dl, cx, cy - 1.5, 3.6, pi, 2 * pi, col, 1.8);
    line(dl, cx - 3.6, cy - 1.5, cx - 3.6, cy - 0.5, col, 1.8);
    line(dl, cx + 3.6, cy - 1.5, cx + 3.6, cy - 0.5, col, 1.8);
}

/// Caixa de entrada: uma bandeja com a abertura no meio.
pub fn inbox(dl: *c.ImDrawList, cx: f32, cy: f32, col: u32) void {
    const th: f32 = 1.7;
    line(dl, cx - 8, cy - 6, cx + 8, cy - 6, col, th);
    line(dl, cx - 8, cy - 6, cx - 8, cy + 7, col, th);
    line(dl, cx + 8, cy - 6, cx + 8, cy + 7, col, th);
    line(dl, cx - 8, cy + 7, cx + 8, cy + 7, col, th);
    line(dl, cx - 8, cy + 1, cx - 3.5, cy + 1, col, th);
    line(dl, cx + 3.5, cy + 1, cx + 8, cy + 1, col, th);
    line(dl, cx - 3.5, cy + 1, cx - 2, cy + 3.5, col, th);
    line(dl, cx + 2, cy + 3.5, cx + 3.5, cy + 1, col, th);
    line(dl, cx - 2, cy + 3.5, cx + 2, cy + 3.5, col, th);
}

/// Marcador de página (mensagens salvas). `filled` = já salva.
pub fn bookmark(dl: *c.ImDrawList, cx: f32, cy: f32, col: u32, filled: bool) void {
    const pts = [_]c.ImVec2{ v(cx - 5.5, cy - 8), v(cx + 5.5, cy - 8), v(cx + 5.5, cy + 8), v(cx, cy + 3.5), v(cx - 5.5, cy + 8) };
    if (filled) {
        // O recorte de baixo deixa o polígono côncavo: vai em triângulos.
        c.ImDrawList_AddTriangleFilled(dl, pts[0], pts[1], pts[2], col);
        c.ImDrawList_AddTriangleFilled(dl, pts[0], pts[2], pts[3], col);
        c.ImDrawList_AddTriangleFilled(dl, pts[0], pts[3], pts[4], col);
        return;
    }
    c.ImDrawList_AddPolyline(dl, &pts[0], pts.len, col, 1.7, c.ImDrawFlags_Closed);
}

/// Fórum: um balão com duas linhas de texto.
pub fn forum(dl: *c.ImDrawList, cx: f32, cy: f32, col: u32) void {
    const th: f32 = 1.7;
    c.ImDrawList_AddRectEx(dl, v(cx - 7.5, cy - 7), v(cx + 7.5, cy + 4.5), col, 3, th, 0);
    line(dl, cx - 3.5, cy + 4.5, cx - 5, cy + 8, col, th);
    line(dl, cx - 5, cy + 8, cx - 0.5, cy + 4.5, col, th);
    line(dl, cx - 4, cy - 3.5, cx + 4, cy - 3.5, col, th);
    line(dl, cx - 4, cy + 0.5, cx + 1.5, cy + 0.5, col, th);
}

/// Canal de mídia: uma foto com uma montanha e o sol.
pub fn media(dl: *c.ImDrawList, cx: f32, cy: f32, col: u32) void {
    const th: f32 = 1.7;
    c.ImDrawList_AddRectEx(dl, v(cx - 8, cy - 6.5), v(cx + 8, cy + 6.5), col, 2.5, th, 0);
    line(dl, cx - 6, cy + 4, cx - 1.5, cy - 1, col, th);
    line(dl, cx - 1.5, cy - 1, cx + 2, cy + 2.5, col, th);
    line(dl, cx + 2, cy + 2.5, cx + 3.8, cy + 0.8, col, th);
    line(dl, cx + 3.8, cy + 0.8, cx + 6, cy + 4, col, th);
    c.ImDrawList_AddCircleFilled(dl, v(cx + 3.5, cy - 3), 1.5, col, 0);
}

// --- Pequenos, para a prévia de uma resposta ------------------------------------
// Desenhados numa grade de 24, em `s` pixels por unidade (0,6 cabe numa linha de
// texto de 13 px), centrados em (cx, cy). O traço acompanha o tamanho.

const Grid = struct {
    cx: f32,
    cy: f32,
    s: f32,
    fn init(cx: f32, cy: f32, s: f32) Grid {
        return .{ .cx = @round(cx), .cy = @round(cy), .s = s };
    }
    fn at(g: Grid, x: f32, y: f32) c.ImVec2 {
        return v(g.cx + (x - 12) * g.s, g.cy + (y - 12) * g.s);
    }
    fn th(g: Grid) f32 {
        return @max(1.2, 2.4 * g.s);
    }
    fn seg(g: Grid, dl: *c.ImDrawList, x1: f32, y1: f32, x2: f32, y2: f32, col: u32) void {
        c.ImDrawList_AddLineEx(dl, g.at(x1, y1), g.at(x2, y2), col, g.th(), 0);
    }
};

/// Folha com o canto dobrado e duas linhas de texto (arquivo).
pub fn file(dl: *c.ImDrawList, cx: f32, cy: f32, s: f32, col: u32) void {
    const g = Grid.init(cx, cy, s);
    const pts = [_]c.ImVec2{ g.at(5, 2), g.at(14, 2), g.at(19, 7), g.at(19, 22), g.at(5, 22) };
    c.ImDrawList_AddPolyline(dl, &pts[0], pts.len, col, g.th(), c.ImDrawFlags_Closed);
    g.seg(dl, 14, 2, 14, 7, col);
    g.seg(dl, 14, 7, 19, 7, col);
    g.seg(dl, 8.5, 12.5, 15.5, 12.5, col);
    g.seg(dl, 8.5, 17, 13.5, 17, col);
}

/// Foto com uma montanha e o sol (imagem ou vídeo).
pub fn picture(dl: *c.ImDrawList, cx: f32, cy: f32, s: f32, col: u32) void {
    const g = Grid.init(cx, cy, s);
    c.ImDrawList_AddRectEx(dl, g.at(2, 4), g.at(22, 20), col, 3 * s, g.th(), 0);
    const hill = [_]c.ImVec2{ g.at(5, 17), g.at(10, 11), g.at(13.5, 14.5), g.at(15.5, 12.5), g.at(19, 17) };
    c.ImDrawList_AddPolyline(dl, &hill[0], hill.len, col, g.th(), 0);
    c.ImDrawList_AddCircleFilled(dl, g.at(16.5, 8.5), 2 * s, col, 0);
}

/// Microfone em traço (mensagem de voz).
pub fn voice(dl: *c.ImDrawList, cx: f32, cy: f32, s: f32, col: u32) void {
    const g = Grid.init(cx, cy, s);
    c.ImDrawList_AddRectEx(dl, g.at(8.5, 2), g.at(15.5, 14), col, 3.5 * s, g.th(), 0);
    c.ImDrawList_PathClear(dl);
    c.ImDrawList_PathArcTo(dl, g.at(12, 11), 6.5 * s, 0, pi, 0);
    c.ImDrawList_PathStroke(dl, col, g.th(), 0);
    g.seg(dl, 12, 17.5, 12, 22, col);
    g.seg(dl, 8.5, 22, 15.5, 22, col);
}

/// Figurinha: um quadrado com a ponta descolando e uma carinha.
pub fn sticker(dl: *c.ImDrawList, cx: f32, cy: f32, s: f32, col: u32) void {
    const g = Grid.init(cx, cy, s);
    const pts = [_]c.ImVec2{ g.at(3, 3), g.at(21, 3), g.at(21, 15), g.at(15, 21), g.at(3, 21) };
    c.ImDrawList_AddPolyline(dl, &pts[0], pts.len, col, g.th(), c.ImDrawFlags_Closed);
    g.seg(dl, 15, 21, 15, 15, col);
    g.seg(dl, 15, 15, 21, 15, col);
    c.ImDrawList_AddCircleFilled(dl, g.at(8, 8.5), 1.8 * s, col, 0);
    c.ImDrawList_AddCircleFilled(dl, g.at(14.5, 8.5), 1.8 * s, col, 0);
    c.ImDrawList_PathClear(dl);
    c.ImDrawList_PathArcTo(dl, g.at(11.25, 10.5), 4.6 * s, pi * 0.2, pi * 0.8, 0);
    c.ImDrawList_PathStroke(dl, col, g.th(), 0);
}

/// Enquete: três barras de tamanhos diferentes.
pub fn poll(dl: *c.ImDrawList, cx: f32, cy: f32, s: f32, col: u32) void {
    const g = Grid.init(cx, cy, s);
    const h = 1.8 * s;
    // Cada barra: a altura dela e até onde vai (todas começam no 3).
    for ([_][2]f32{ .{ 6, 20 }, .{ 12, 13 }, .{ 18, 17 } }) |b| {
        const a = g.at(3, b[0]);
        const z = g.at(b[1], b[0]);
        c.ImDrawList_AddRectFilledEx(dl, v(a.x, a.y - h), v(z.x, z.y + h), col, h, 0);
    }
}

/// Thread: o balão pequeno com uma linha saindo dele.
pub fn thread(dl: *c.ImDrawList, cx: f32, cy: f32, col: u32) void {
    const th: f32 = 1.6;
    c.ImDrawList_AddRectEx(dl, v(cx - 7, cy - 6), v(cx + 7, cy + 3), col, 2.5, th, 0);
    line(dl, cx - 3, cy + 3, cx - 4.5, cy + 6.5, col, th);
    line(dl, cx - 4.5, cy + 6.5, cx, cy + 3, col, th);
    c.ImDrawList_AddCircleFilled(dl, v(cx - 3, cy - 1.5), 1, col, 0);
    c.ImDrawList_AddCircleFilled(dl, v(cx, cy - 1.5), 1, col, 0);
    c.ImDrawList_AddCircleFilled(dl, v(cx + 3, cy - 1.5), 1, col, 0);
}
