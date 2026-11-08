#!/usr/bin/env python3
"""Testa a bandeja com o processo de verdade, sem ninguém na frente da tela.

Roda dentro de um Xvfb e de um D-Bus particular (ver tools/qa_bandeja.sh). Fecha
a janela pelo mesmo WM_DELETE_WINDOW de um gerenciador de janelas e faz o papel
do painel: registra o StatusNotifierWatcher, recebe o StatusNotifierItem do
processo do ícone, clica no ícone (Activate, como o clique esquerdo de uma barra) e
nos itens do menu pelo dbusmenu. Só --demo: nunca conecta em lugar nenhum.
"""
import os
import shutil
import signal
import subprocess
import sys
import tempfile
import threading
import time
from pathlib import Path

import dbus
import dbus.mainloop.glib
import dbus.service
from gi.repository import GLib
from Xlib import X, display, protocol
from Xlib.error import XError

BIN = sys.argv[1]
SLOW = "--slow" in sys.argv
WATCHER = "org.kde.StatusNotifierWatcher"
ICON_MAX_S = 5.0
passed = 0
failed = []


def check(name, ok, extra=""):
    global passed
    if ok:
        passed += 1
        print(f"  ok   {name}{'  (' + extra + ')' if extra else ''}")
    else:
        failed.append(name)
        print(f"  FALHA {name}{'  (' + extra + ')' if extra else ''}")


def wait_until(f, timeout=8.0):
    end = time.time() + timeout
    while time.time() < end:
        v = f()
        if v:
            return v
        time.sleep(0.05)
    return f()


# --- O painel falso ------------------------------------------------------------


class Watcher(dbus.service.Object):
    def __init__(self, bus):
        self.items = []
        self.name = dbus.service.BusName(WATCHER, bus)
        super().__init__(bus, "/StatusNotifierWatcher")
        # Como um painel de verdade: o protocolo não tem como tirar um ícone do
        # registro, ele só sai quando a conexão de quem o registrou fecha.
        self.owner_match = bus.add_signal_receiver(self.owner_changed, "NameOwnerChanged", "org.freedesktop.DBus")

    def owner_changed(self, name, old, new):
        if new:
            return
        for item in [i for i in self.items if i[0] == str(name)]:
            self.items.remove(item)
            self.StatusNotifierItemUnregistered(f"{item[0]}{item[1]}")

    @dbus.service.method(WATCHER, in_signature="s", sender_keyword="sender")
    def RegisterStatusNotifierItem(self, service, sender=None):
        path = service if service.startswith("/") else "/StatusNotifierItem"
        self.items.append((str(sender), str(path)))
        self.StatusNotifierItemRegistered(f"{sender}{path}")

    @dbus.service.method(WATCHER, in_signature="s")
    def RegisterStatusNotifierHost(self, service):
        pass

    @dbus.service.signal(WATCHER, signature="s")
    def StatusNotifierItemRegistered(self, service):
        pass

    @dbus.service.signal(WATCHER, signature="s")
    def StatusNotifierItemUnregistered(self, service):
        pass

    @dbus.service.signal(WATCHER, signature="")
    def StatusNotifierHostRegistered(self):
        pass

    @dbus.service.method(dbus.PROPERTIES_IFACE, in_signature="ss", out_signature="v")
    def Get(self, iface, prop):
        if prop == "IsStatusNotifierHostRegistered":
            return dbus.Boolean(True, variant_level=1)
        if prop == "ProtocolVersion":
            return dbus.Int32(0, variant_level=1)
        if prop == "RegisteredStatusNotifierItems":
            return dbus.Array([], signature="s", variant_level=1)
        raise dbus.exceptions.DBusException("org.freedesktop.DBus.Error.UnknownProperty")

    @dbus.service.method(dbus.PROPERTIES_IFACE, in_signature="s", out_signature="a{sv}")
    def GetAll(self, iface):
        return {
            "IsStatusNotifierHostRegistered": dbus.Boolean(True),
            "ProtocolVersion": dbus.Int32(0),
            "RegisteredStatusNotifierItems": dbus.Array([], signature="s"),
        }


class Panel:
    """Sobe e desce o painel no meio de um teste."""

    def __init__(self):
        dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
        self.bus = dbus.SessionBus()
        self.watcher = None
        self.loop = GLib.MainLoop()
        threading.Thread(target=self.loop.run, daemon=True).start()

    def call(self, f):
        """Roda na thread do GLib e espera (o dbus-python não é para duas threads)."""
        done = threading.Event()
        box = {}

        def job():
            try:
                box["v"] = f()
            except Exception as e:  # o teste decide o que fazer
                box["e"] = e
            done.set()
            return False

        GLib.idle_add(job)
        done.wait(10)
        if "e" in box:
            raise box["e"]
        return box.get("v")

    def up(self):
        def go():
            if not self.watcher:
                self.watcher = Watcher(self.bus)

        self.call(go)

    def down(self):
        def go():
            if self.watcher:
                self.watcher.owner_match.remove()
                self.watcher.remove_from_connection()
                self.bus.release_name(WATCHER)
                # O dbus-python guarda o BusName pelo nome: sem tirar daqui, subir o
                # painel de novo devolveria o antigo, já solto, e o nome ficaria sem dono.
                self.bus._bus_names.pop(WATCHER, None)
                self.watcher = None

        self.call(go)

    def items(self):
        return list(self.watcher.items) if self.watcher else []

    def clear(self):
        if self.watcher:
            self.watcher.items.clear()

    def prop(self, item, name):
        def go():
            o = self.bus.get_object(item[0], item[1])
            return dbus.Interface(o, dbus.PROPERTIES_IFACE).Get("org.kde.StatusNotifierItem", name)

        return self.call(go)

    def activate(self, item, token=None, method="Activate"):
        """O clique esquerdo de uma barra: a ficha do xdg-activation (se houver) e o Activate."""

        def go():
            o = self.bus.get_object(item[0], item[1])
            sni = dbus.Interface(o, "org.kde.StatusNotifierItem")
            if token:
                sni.ProvideXdgActivationToken(token)
            getattr(sni, method)(0, 0)

        self.call(go)

    def menu(self, item):
        """Os itens do menu do ícone: {rótulo: id}."""
        path = self.prop(item, "Menu")

        def go():
            o = self.bus.get_object(item[0], path)
            _, layout = dbus.Interface(o, "com.canonical.dbusmenu").GetLayout(0, -1, ["label"])
            return {str(ch[1].get("label", "")): int(ch[0]) for ch in layout[2]}

        return self.call(go)

    def click(self, item, menu_id):
        path = self.prop(item, "Menu")

        def go():
            o = self.bus.get_object(item[0], path)
            dbus.Interface(o, "com.canonical.dbusmenu").Event(menu_id, "clicked", dbus.String("", variant_level=1), 0)

        self.call(go)


# --- A janela no X -------------------------------------------------------------

dpy = display.Display()
root = dpy.screen().root
WM_PROTOCOLS = dpy.intern_atom("WM_PROTOCOLS")
WM_DELETE = dpy.intern_atom("WM_DELETE_WINDOW")


def windows():
    """Janelas do larperCord, mapeadas ou não."""
    out = []
    for w in root.query_tree().children:
        try:
            if w.get_wm_name() == "larperCord" or (w.get_wm_class() or ("", ""))[0] == "larperCord":
                out.append(w)
        except Exception:
            pass
    return out


def mapped():
    out = []
    for w in windows():
        try:
            if w.get_attributes().map_state == X.IsViewable:
                out.append(w)
        except Exception:
            pass
    dpy.sync()
    return out


def close_window():
    ws = mapped()
    if not ws:
        return False
    w = ws[0]
    ev = protocol.event.ClientMessage(window=w, client_type=WM_PROTOCOLS, data=(32, [WM_DELETE, X.CurrentTime, 0, 0, 0]))
    w.send_event(ev)
    dpy.sync()
    return True


def focus(w):
    """Dá o foco do teclado para a janela (sem gerenciador de janelas, direto no X)."""
    w.set_input_focus(X.RevertToPointerRoot, X.CurrentTime)
    dpy.sync()


def unfocus():
    """O foco vai para outro lugar: a janela fica aberta, mas atrás."""
    root.set_input_focus(X.RevertToPointerRoot, X.CurrentTime)
    dpy.sync()


def painted():
    """A janela tem desenho: várias cores, e não um retângulo liso."""
    ws = mapped()
    if not ws:
        return False
    try:
        g = ws[0].get_geometry()
        raw = ws[0].get_image(0, 0, g.width, g.height, X.ZPixmap, 0xFFFFFFFF).data
    except XError as e:
        # A janela pode sumir entre olhar e copiar. Se ficar assim, a checagem seguinte falha.
        print(f"  (a janela {ws[0].id:#x} recusou a cópia: {e.__class__.__name__}, geometria {g.width}x{g.height}+{g.x}+{g.y})" if "g" in locals() else "  (a janela sumiu)")
        return False
    return len({bytes(raw[i : i + 4]) for i in range(0, len(raw), 4 * 97)}) > 8


# --- Os processos --------------------------------------------------------------


running = []


class App:
    def __init__(self, home, *args, single=True):
        running.append(self)
        env = {k: v for k, v in os.environ.items() if k != "LARPER_TOKEN"}
        env.update(
            HOME=str(home),
            XDG_CONFIG_HOME=str(home / "config"),
            XDG_CACHE_HOME=str(home / "cache"),
            XDG_RUNTIME_DIR=str(home),
            SDL_VIDEO_DRIVER="x11",
            GDK_BACKEND="x11",
            LARPER_RENDERER="software",
            SDL_AUDIO_DRIVER="dummy",
            LARPER_NO_PICS="1",
        )
        env.pop("WAYLAND_DISPLAY", None)
        if single:
            env["LARPER_INSTANCE"] = "1"
        self.log = tempfile.TemporaryFile()
        self.p = subprocess.Popen([BIN, "--demo", "--no-live", "--theme", "classico", *args], env=env, stdout=self.log, stderr=subprocess.STDOUT, start_new_session=True)

    def alive(self):
        return self.p.poll() is None

    def wait(self, timeout):
        try:
            return self.p.wait(timeout)
        except subprocess.TimeoutExpired:
            return None

    def output(self):
        self.log.seek(0)
        return self.log.read().decode(errors="replace")

    def cpu_ticks(self):
        f = Path(f"/proc/{self.p.pid}/stat").read_text().rsplit(")", 1)[1].split()
        return int(f[11]) + int(f[12])

    def pss_kb(self):
        for line in Path(f"/proc/{self.p.pid}/smaps_rollup").read_text().splitlines():
            if line.startswith("Pss:"):
                return int(line.split()[1])
        return 0

    def threads(self):
        return len(list(Path(f"/proc/{self.p.pid}/task").iterdir()))

    def kill(self):
        # O grupo inteiro: o aviso de erro do SDL pode ser um processo filho.
        try:
            os.killpg(self.p.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        self.p.wait()


def helpers(a):
    """Os processos do ícone: filhos do app."""
    out = []
    try:
        kids = Path(f"/proc/{a.p.pid}/task/{a.p.pid}/children").read_text().split()
    except OSError:
        return out
    for k in kids:
        try:
            if b"--tray-helper" in Path(f"/proc/{k}/cmdline").read_bytes():
                out.append(int(k))
        except OSError:
            pass
    return out


def pss_of(pid):
    for line in Path(f"/proc/{pid}/smaps_rollup").read_text().splitlines():
        if line.startswith("Pss:"):
            return int(line.split()[1])
    return 0


def no_windows():
    """Espera as janelas de quem foi morto sumirem do X."""
    wait_until(lambda: not windows(), 5)


def fresh_home(settings=None):
    d = Path(tempfile.mkdtemp(prefix="larper-qa-"))
    (d / "config" / "larpercord").mkdir(parents=True)
    if settings:
        (d / "config/larpercord/settings.kdl").write_text(f"settings {settings}\n")
    return d


def start(home, *args, **kw):
    """Abre e espera a janela aparecer de verdade (já pintada)."""
    a = App(home, *args, **kw)
    # Pintada já tem o app de pé: antes disso, fechar seria sair (sem conexão).
    wait_until(lambda: painted() or not a.alive(), 20)
    time.sleep(1.0)
    return a


def cpu_percent(a, seconds):
    t0 = a.cpu_ticks()
    time.sleep(seconds)
    return (a.cpu_ticks() - t0) / os.sysconf("SC_CLK_TCK") / seconds * 100


def ticks_of(pid):
    f = Path(f"/proc/{pid}/stat").read_text().rsplit(")", 1)[1].split()
    return int(f[11]) + int(f[12])


def wakeups_of(pid):
    """Vezes que o processo (todas as threads) foi acordado: trocas de contexto."""
    n = 0
    for t in Path(f"/proc/{pid}/task").iterdir():
        for line in (t / "status").read_text().splitlines():
            if line.startswith(("voluntary_ctxt_switches:", "nonvoluntary_ctxt_switches:")):
                n += int(line.split()[1])
    return n


def rss_of(pid):
    for line in Path(f"/proc/{pid}/status").read_text().splitlines():
        if line.startswith("VmRSS:"):
            return int(line.split()[1])
    return 0


panel = Panel()


def section(name):
    print(f"\n{name}")


def no_panel():
    section("sem painel: o SDL_CreateTray até funcionaria, mas fechar tem que sair")
    panel.down()
    home = fresh_home()
    a = start(home)
    check("a janela abriu", bool(mapped()))
    time.sleep(2.5)
    check("com fechar para a bandeja ligado (o padrão): nenhum processo do ícone", not helpers(a), str(helpers(a)))
    t = time.time()
    close_window()
    code = a.wait(5)
    check("fechar encerra o processo", code == 0, f"código {code}, {time.time() - t:.2f} s")
    check("sem passar pelo vigia", "encerramento demorou" not in a.output())
    a.kill()
    shutil.rmtree(home)


def option_off():
    section("com painel e fechar para a bandeja desligado")
    panel.up()
    panel.clear()
    home = fresh_home("close_to_tray=#false")
    a = start(home)
    time.sleep(2.5)
    check("nenhum processo do ícone com a janela aberta", not helpers(a), str(helpers(a)))
    check("e nenhum ícone no painel", not panel.items())
    close_window()
    code = a.wait(5)
    check("fechar encerra o processo", code == 0, f"código {code}")
    check("nenhum ícone foi criado", not panel.items())
    a.kill()
    shutil.rmtree(home)


def full_flow():
    section("fechar para a bandeja (o padrão): o ícone da abertura até sair")
    panel.up()
    panel.clear()
    # Um settings.kdl de um build de desenvolvimento, ainda com o tray_always: a chave é ignorada.
    home = fresh_home("tray_always=#false")
    t_start = time.time()
    a = start(home)
    items = wait_until(panel.items, ICON_MAX_S)
    check("o ícone aparece com a janela aberta (o tray_always=#false de um arquivo antigo não conta)", bool(items) and bool(mapped()), f"{len(panel.items())} ícone(s)")
    if not items:
        a.kill()
        return
    item = items[-1]
    icon = panel.prop(item, "IconName")
    sizes = [(int(w), int(h), len(px)) for w, h, px in panel.prop(item, "IconPixmap")]
    check("o ícone vai desenhado no IconPixmap (22, 32 e 64 em ARGB), sem nome de tema", icon == "" and [w for w, _, _ in sizes] == [22, 32, 64] and all(n == w * h * 4 for w, h, n in sizes), str(sizes))
    # O desenho de verdade, e não um quadrado liso: várias cores opacas, e não só branco.
    px32 = next((bytes(bytearray(int(b) for b in px)) for w, h, px in panel.prop(item, "IconPixmap") if int(w) == 32), b"")
    opaque = {px32[i + 1 : i + 4] for i in range(0, len(px32), 4) if px32[i] == 255}
    check("o ícone tem as cores do PNG (não um quadrado branco)", len(opaque) > 8 and any(c != b"\xff\xff\xff" for c in opaque), f"{len(opaque)} cores opacas")
    who = {k: str(panel.prop(item, k)) for k in ("Id", "Title", "Category", "Status")}
    check("Id, título, categoria e estado", who == {"Id": "larpercord", "Title": "larperCord", "Category": "Communications", "Status": "Active"}, str(who))
    check("o clique esquerdo é do app: ItemIsMenu falso e o menu em /MenuBar", not bool(panel.prop(item, "ItemIsMenu")) and str(panel.prop(item, "Menu")) == "/MenuBar")
    labels = panel.menu(item)
    check("o menu tem Abrir e Sair", len(labels) == 2, ", ".join(labels))
    open_id = next(v for k, v in labels.items() if "larperCord" in k)
    kids = helpers(a)
    check("um processo só para o ícone", len(kids) == 1, str(kids))
    check("o GTK fica fora do app", "libgtk-3" not in Path(f"/proc/{a.p.pid}/maps").read_text())
    check("e fora do processo do ícone também", bool(kids) and "libgtk-3" not in Path(f"/proc/{kids[0]}/maps").read_text())

    # O custo do ícone o tempo todo: o processo dele e o app parados, 20 s (o
    # "digitando" da demonstração anima nos primeiros 10 s).
    time.sleep(max(0.0, 12 - (time.time() - t_start)))
    pss_open = a.pss_kb()
    hz = os.sysconf("SC_CLK_TCK")
    h0, a0 = (ticks_of(kids[0]) if kids else 0), a.cpu_ticks()
    w0 = wakeups_of(kids[0]) if kids else 0
    time.sleep(20)
    cpu_open = (a.cpu_ticks() - a0) / hz / 20 * 100
    if kids:
        cpu_h = (ticks_of(kids[0]) - h0) / hz / 20 * 100
        wake_h = (wakeups_of(kids[0]) - w0) / 20
        print(f"       custo do ícone: processo do ícone RSS {rss_of(kids[0])} KB, PSS {pss_of(kids[0])} KB, CPU {cpu_h:.2f}% e {wake_h:.2f} despertares/s em 20 s parado; app no mesmo tempo {cpu_open:.2f}% de CPU, PSS {pss_open} KB")
        check("parado, o processo do ícone quase não usa CPU", cpu_h < 1.0, f"{cpu_h:.2f}%")
        check("e não acorda sozinho (fica no poll até o painel ou o app falarem)", wake_h <= 0.5, f"{wake_h:.2f}/s")

    section("fechar, Abrir e um segundo larperCord")
    close_window()
    check("fechar esconde a janela", wait_until(lambda: not mapped(), 3) is True)
    time.sleep(0.3)
    check("e o mesmo ícone fica, no mesmo processo", panel.items() == [item] and helpers(a) == kids, f"{panel.items()} {helpers(a)}")
    check("o processo continua", a.alive())
    time.sleep(2)
    cpu_hidden = cpu_percent(a, 10)
    check("escondido: quase nada de CPU", cpu_hidden < 1.0, f"{cpu_hidden:.2f}% com a janela escondida, {cpu_open:.2f}% com ela aberta")
    print(f"       RAM (PSS): {pss_open} KB aberta, {a.pss_kb()} KB na bandeja")
    panel.click(item, open_id)
    check("Abrir volta a janela", bool(wait_until(mapped, 5)))
    time.sleep(1.0)
    check("voltou desenhada, não em branco", painted(), "")
    check("e o ícone fica", panel.items() == [item] and helpers(a) == kids)
    cpu_back = cpu_percent(a, 5)
    check("aberta de novo, volta ao custo de antes", cpu_back < cpu_open + 0.5, f"{cpu_back:.2f}% agora, {cpu_open:.2f}% antes de ir para a bandeja")
    panel.click(item, open_id)
    time.sleep(0.5)
    check("Abrir com a janela aberta: continua uma janela só, aberta", len(mapped()) == 1 and len(windows()) == 1)
    b = App(home)
    code = b.wait(8)
    check("um segundo larperCord com a janela aberta sai sem abrir outra", code == 0 and len(mapped()) == 1, f"código {code}")
    close_window()
    check("escondeu de novo", wait_until(lambda: not mapped(), 3) is True)
    t = time.time()
    b = App(home)
    code = b.wait(8)
    check("com a janela na bandeja: o segundo sai", code == 0, f"código {code}, {time.time() - t:.2f} s")
    check("e o primeiro volta", bool(wait_until(mapped, 5)))
    check("sempre uma janela só", len(windows()) == 1, f"{len(windows())}")
    time.sleep(0.5)

    section("clique no ícone (Activate): a janela vem e vai, como o esquerdo no Windows")
    focus(mapped()[0])
    time.sleep(0.5)
    panel.activate(item)
    check("aberta e com o foco: o clique esconde na bandeja", wait_until(lambda: not mapped(), 3) is True and a.alive())
    check("e o mesmo ícone fica, no mesmo processo", panel.items() == [item] and helpers(a) == kids, f"{panel.items()} {helpers(a)}")
    time.sleep(0.6)
    # Uma barra no Wayland manda a ficha do xdg-activation antes do clique (no X ela não faz nada).
    panel.activate(item, token="qa-ficha-1")
    check("escondida: o clique traz a janela de volta (com a ficha do painel antes)", bool(wait_until(mapped, 5)))
    time.sleep(1.0)
    check("voltou desenhada", painted())
    unfocus()
    time.sleep(0.6)
    panel.activate(item)
    time.sleep(1.0)
    check("aberta mas sem o foco (atrás de outra): o clique traz para a frente, não esconde", bool(mapped()) and a.alive())
    focus(mapped()[0])
    time.sleep(0.5)
    panel.activate(item)
    time.sleep(0.1)
    panel.activate(item)
    gone = wait_until(lambda: not mapped(), 3) is True
    time.sleep(1.0)
    check("clique duplo conta uma vez: escondeu e continua escondida", gone and not mapped())
    panel.activate(item, method="SecondaryActivate")
    check("o botão do meio (SecondaryActivate) também traz de volta", bool(wait_until(mapped, 5)))
    time.sleep(0.5)
    check("sempre uma janela só, o mesmo ícone e o mesmo processo", len(windows()) == 1 and panel.items() == [item] and helpers(a) == kids)

    section("idas e voltas")
    ok = True
    icons = []
    for _ in range(5):
        ok = ok and close_window()
        ok = ok and wait_until(lambda: not mapped(), 3) is True
        icons.append(len(panel.items()))
        b = App(home)
        ok = ok and b.wait(8) == 0
        ok = ok and bool(wait_until(mapped, 5))
        time.sleep(0.3)
        icons.append(len(panel.items()))
    check("5 vezes para a bandeja e de volta pelo segundo larperCord", ok and a.alive())
    check("sempre o mesmo ícone, nos dois estados", icons == [1, 1] * 5 and panel.items() == [item] and helpers(a) == kids, str(icons))

    section("o painel reinicia com a janela aberta")
    panel.down()
    time.sleep(1.0)
    panel.up()
    back = wait_until(panel.items, 10)
    check("o ícone volta ao painel, sem outro processo", bool(back) and helpers(a) == kids, f"{back} {helpers(a)}")
    check("a janela continua aberta", bool(mapped()) and a.alive())
    if back:
        item = back[-1]

    section("o processo do ícone morre")
    if kids:
        os.kill(kids[0], signal.SIGKILL)
    # O ícone novo pode entrar antes de o painel ser visto vazio: vale o antigo sair.
    check("com a janela aberta: ela continua e o app segue", wait_until(lambda: item not in panel.items(), 3) is True and bool(mapped()) and a.alive())
    back = wait_until(panel.items, 8)
    kids = helpers(a)
    check("e o ícone volta sozinho, num processo novo", bool(back) and len(kids) == 1, f"{back} {kids}")
    if back:
        item = back[-1]
    close_window()
    wait_until(lambda: not mapped(), 3)
    if kids:
        os.kill(kids[0], signal.SIGKILL)
    check("com a janela escondida: ela volta", bool(wait_until(mapped, 5)) and a.alive())
    # Duas quedas seguidas: a segunda espera a próxima tentativa (até 10 s).
    back = wait_until(panel.items, 15)
    check("e o ícone também", bool(back) and len(helpers(a)) == 1, f"{back} {helpers(a)}")
    if back:
        item = back[-1]
    time.sleep(0.5)

    section("Sair no menu com a janela aberta")
    labels = panel.menu(item)
    quit_id = next(v for k, v in labels.items() if "larperCord" not in k)
    check("janela aberta antes de sair", bool(mapped()))
    threads = a.threads()
    t = time.time()
    panel.click(item, quit_id)
    code = a.wait(5)
    check("Sair no menu encerra tudo sem fechar a janela antes", code == 0, f"código {code}, {time.time() - t:.2f} s, {threads} threads antes")
    check("sem passar pelo vigia", "encerramento demorou" not in a.output())
    check("sem erro na saída", "panic" not in a.output() and "Segmentation" not in a.output(), a.output()[-200:] if "panic" in a.output() else "")
    check("e o ícone sai do painel", wait_until(lambda: not panel.items(), 3) is True)
    a.kill()
    kdl = (home / "config/larpercord/settings.kdl").read_text()
    check("as configurações ficaram salvas, sem o tray_always antigo", "close_to_tray=#true" in kdl and "video_volume=100" in kdl and "tray_always" not in kdl)

    section("depois de sair: a trava não fica presa")
    a = start(home)
    check("abre de novo normalmente", a.alive() and bool(mapped()))
    close_window()
    wait_until(lambda: not mapped(), 3)
    item = wait_until(panel.items, ICON_MAX_S)
    if item:
        labels = panel.menu(item[-1])
        panel.click(item[-1], next(v for k, v in labels.items() if "larperCord" not in k))
    check("Sair no menu com a janela escondida também", a.wait(5) == 0)
    a.kill()
    a = start(home)
    a.p.kill()
    a.p.wait()
    no_windows()
    a = start(home)
    check("depois de um kill -9, também", a.alive() and bool(mapped()))
    close_window()
    wait_until(lambda: not mapped(), 3)
    a.p.send_signal(signal.SIGTERM)
    check("SIGTERM com a janela escondida sai", a.wait(5) == 0)
    a.kill()
    shutil.rmtree(home)


def restarted():
    section("primeiro travado")
    panel.up()
    home = fresh_home()
    a = start(home)
    a.p.send_signal(signal.SIGSTOP)
    b = App(home)
    time.sleep(6.5)
    # Parado no aviso do sistema, sem conexão nenhuma (fica até alguém clicar).
    check("o segundo não abre o app; avisa", b.alive() and "primeiro quadro" not in b.output() and len(mapped()) >= 1)
    b.kill()
    a.p.send_signal(signal.SIGCONT)
    a.kill()
    no_windows()
    shutil.rmtree(home)

    section("--restarted")
    panel.up()
    panel.clear()
    home = fresh_home()
    a = start(home)
    # O ícone do antigo (o novo põe o dele só depois de assumir).
    item = (wait_until(panel.items, ICON_MAX_S) or [None])[-1]
    close_window()
    wait_until(lambda: not mapped())
    # Toma o lugar do antigo sem chamar por ele: o antigo continua escondido.
    b = App(home, "--restarted")
    time.sleep(2)
    check("não acorda o antigo", not mapped() and b.alive())
    # O antigo sai (como depois de `restart_wanted`).
    labels = panel.menu(item)
    t = time.time()
    panel.click(item, next(v for k, v in labels.items() if "larperCord" not in k))
    check("o antigo saiu", a.wait(5) == 0)
    check("o novo assume dentro dos 5 s", bool(wait_until(mapped, 8)) and b.alive(), f"{time.time() - t:.2f} s")
    time.sleep(1)
    c = App(home)
    check("um terceiro chama o novo", c.wait(8) == 0 and b.alive())
    b.kill()
    no_windows()

    # O antigo não sai nunca: depois dos 5 s o reiniciado desiste e chama por ele.
    a = start(home)
    close_window()
    wait_until(lambda: not mapped())
    t = time.time()
    b = App(home, "--restarted")
    code = b.wait(9)
    took = time.time() - t
    check("antigo de pé: desiste depois de ~5 s e não abre outra conexão", code == 0 and 4.5 < took < 8, f"código {code}, {took:.1f} s")
    check("e o antigo aparece", bool(wait_until(mapped, 3)))
    a.kill()
    shutil.rmtree(home)


def demo_not_gated():
    section("a demonstração sem LARPER_INSTANCE roda ao lado (não pega a trava)")
    panel.up()
    home = fresh_home()
    a = start(home, single=False)
    b = start(home, single=False)
    check("duas ao mesmo tempo", a.alive() and b.alive() and len(mapped()) == 2, f"{len(mapped())} janelas")
    a.kill()
    b.kill()
    shutil.rmtree(home)


def panel_dies():
    section("o painel morre com a janela escondida (--slow)")
    panel.up()
    panel.clear()
    home = fresh_home()
    a = start(home)
    wait_until(panel.items, ICON_MAX_S)
    close_window()
    wait_until(lambda: not mapped())
    panel.down()
    t = time.time()
    back = bool(wait_until(mapped, 190))
    check("a janela volta sozinha", back and a.alive(), f"{time.time() - t:.0f} s")
    a.kill()
    shutil.rmtree(home)


try:
    no_panel()
    option_off()
    full_flow()
    restarted()
    demo_not_gated()
    if SLOW:
        panel_dies()
except Exception as e:
    import traceback

    traceback.print_exc()
    failed.append(f"o teste quebrou: {e}")
finally:
    for a in running:
        a.kill()

print(f"\n{passed} passaram, {len(failed)} falharam")
for f in failed:
    print(f"  - {f}")
sys.exit(1 if failed else 0)
