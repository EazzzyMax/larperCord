// A galeria da comunidade: a prévia ao vivo de cada tema de themes/community/.
// O desenho é o do criador de temas (theme-builder-preview.js, com o mesmo escape de tudo
// que vem do arquivo); os textos dos cartões já saem prontos e escapados de tools/gen_site.py.
(function () {
  var box = document.querySelector("[data-community]");
  if (!box || !window.LC_TB || !window.LC_TB_PREVIEW) return;
  var TB = window.LC_TB, html = document.documentElement;
  var lang = html.dataset.lang === "pt" ? "pt" : "en";
  var P = window.LC_TB_PREVIEW(TB, lang);
  var raw = document.getElementById("cg-data");
  var DATA = raw ? JSON.parse(raw.textContent) : { order: [], themes: {} };
  var mode = html.dataset.mode === "light" ? "light" : "dark";
  var cards = Array.prototype.slice.call(box.querySelectorAll("[data-cg-card]"));
  if (!cards.length) return;

  function fit(card) {
    var screen = card.querySelector("[data-cg-screen]"), frame = card.querySelector("[data-cg-frame]");
    if (screen.clientWidth) frame.style.transform = "scale(" + screen.clientWidth / P.W + ")";
  }
  function draw(card) {
    var name = card.getAttribute("data-cg-card"), frame = card.querySelector("[data-cg-frame]");
    if (!TB.own(DATA.themes, name)) return;
    try {
      P.mount(frame, TB.loadTheme(DATA.themes[name].src, { mode: mode }));
      card.classList.add("cg-live");
      card.classList.remove("cg-failed");
    } catch (e) {
      // O build já conferiu cada arquivo; se ainda assim falhar, ficam as amostras de cor.
      frame.textContent = "";
      card.classList.remove("cg-live");
      card.classList.add("cg-failed");
    }
    card.dataset.cgMode = mode;
    fit(card);
  }

  // Só desenha o que aparece na tela: a galeria pode crescer.
  var seen = new Set();
  var io = window.IntersectionObserver ? new IntersectionObserver(function (entries) {
    entries.forEach(function (en) {
      if (!en.isIntersecting) return;
      seen.add(en.target);
      if (en.target.dataset.cgMode !== mode) draw(en.target);
    });
  }, { rootMargin: "300px 0px" }) : null;
  // Sem IntersectionObserver, todos de uma vez (o setMode do fim desenha).
  cards.forEach(function (c) { if (io) io.observe(c); else seen.add(c); });
  if (window.ResizeObserver) {
    var ro = new ResizeObserver(function (entries) { entries.forEach(function (en) { fit(en.target.closest("[data-cg-card]")); }); });
    cards.forEach(function (c) { ro.observe(c.querySelector("[data-cg-screen]")); });
  } else addEventListener("resize", function () { cards.forEach(fit); });

  var buttons = Array.prototype.slice.call(box.querySelectorAll("[data-cg-mode]"));
  function setMode(m) {
    mode = m;
    buttons.forEach(function (b) {
      var on = b.dataset.cgMode === m;
      b.setAttribute("aria-checked", on ? "true" : "false");
      b.tabIndex = on ? 0 : -1;
    });
    seen.forEach(draw);
  }
  buttons.forEach(function (b) {
    b.addEventListener("click", function () { setMode(b.dataset.cgMode); });
    b.addEventListener("keydown", function (e) {
      if (e.key !== "ArrowLeft" && e.key !== "ArrowRight") return;
      e.preventDefault();
      var o = b.dataset.cgMode === "dark" ? "light" : "dark";
      setMode(o);
      box.querySelector('[data-cg-mode="' + o + '"]').focus();
    });
  });
  setMode(mode);
})();
