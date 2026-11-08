// Instalação: mostra primeiro o caminho do sistema de quem visita e deixa os
// outros a um clique. Sem JavaScript, todas as opções ficam à vista.
// ?os=arch, ?os=linux ou ?os=windows na URL força uma escolha (para testar).
(function () {
  var picks = document.querySelectorAll("[data-os-pick]");
  if (!picks.length) return;
  var pt = document.documentElement.dataset.lang === "pt";
  var T = pt
    ? { windows: "Mostrando a instalação para Windows, que o seu navegador informou.", linux: "Mostrando a instalação para Linux, que o seu navegador informou. Escolha a da sua distro.", distro: "Mostrando a instalação para a sua distro Linux, que o seu navegador informou.", arch: "Mostrando a instalação para Arch Linux, que o seu navegador informou.", none: "O larperCord roda em Linux e Windows (x86_64). Escolha o computador onde vai usar:", more: "Outros sistemas", less: "Esconder os outros sistemas",
        forced: { windows: "Mostrando a instalação para Windows, escolhida no endereço da página.", linux: "Mostrando a instalação para Linux, escolhida no endereço da página.", arch: "Mostrando a instalação para Arch Linux, escolhida no endereço da página." } }
    : { windows: "Showing the install for Windows, as your browser reports.", linux: "Showing the install for Linux, as your browser reports. Pick the one for your distro.", distro: "Showing the install for your Linux distro, as your browser reports.", arch: "Showing the install for Arch Linux, as your browser reports.", none: "larperCord runs on Linux and Windows (x86_64). Pick the computer you'll use it on:", more: "Other systems", less: "Hide the other systems",
        forced: { windows: "Showing the install for Windows, picked in the page address.", linux: "Showing the install for Linux, picked in the page address.", arch: "Showing the install for Arch Linux, picked in the page address." } };

  // Os sistemas a mostrar primeiro, na ordem, e a frase de cima.
  function detect() {
    var forced = /[?&]os=(arch|linux|windows)\b/.exec(location.search);
    if (forced) return { show: [forced[1]], say: T.forced[forced[1]] };
    var platform = "";
    try { platform = (navigator.userAgentData && navigator.userAgentData.platform) || ""; } catch (e) {}
    var ua = navigator.userAgent || "";
    // Celular, tablet, Chromebook e Mac não têm versão: tudo fica à vista.
    if (platform ? !/^(Windows|Linux)$/i.test(platform) : /Android|iPhone|iPad|iPod|CrOS|Macintosh/i.test(ua)) return { show: [], say: T.none };
    if (/^Windows$/i.test(platform) || /Windows/i.test(ua)) return { show: ["windows"], say: T.windows };
    if (/^Linux$/i.test(platform) || /X11|Linux/i.test(ua)) {
      // Os arquivos prontos são x86_64: num Linux ARM (quando o navegador conta) nenhum vai primeiro.
      if (/aarch64|arm/i.test(ua)) return { show: [], say: T.none };
      // O navegador não diz a distro, mas alguns pacotes põem o nome dela no userAgent.
      if (/Arch Linux|Manjaro|EndeavourOS|CachyOS|Garuda/i.test(ua)) return { show: ["arch"], say: T.arch };
      if (/Ubuntu|Debian|Fedora|Mint|openSUSE|SUSE|Pop!?_OS|elementary|Zorin|CentOS|Red Hat/i.test(ua)) return { show: ["linux"], say: T.distro };
      return { show: ["arch", "linux"], say: T.linux };
    }
    return { show: [], say: T.none };
  }

  var found = detect();
  var hidden = []; // { rest, open } de cada grupo que escondeu opções
  picks.forEach(function (pick, n) {
    var opts = Array.prototype.slice.call(pick.querySelectorAll("[data-os]"));
    if (!opts.length) return;
    var parent = opts[0].parentNode;
    var hint = document.createElement("p");
    hint.className = "os-hint";
    hint.setAttribute("role", "status");
    hint.textContent = found.say;
    pick.insertBefore(hint, pick.firstChild);
    if (!found.show.length) return;
    var mine = [], rest = [];
    opts.forEach(function (o) { (found.show.indexOf(o.dataset.os) >= 0 ? mine : rest).push(o); });
    if (!mine.length) return;
    mine.sort(function (a, b) { return found.show.indexOf(a.dataset.os) - found.show.indexOf(b.dataset.os); });
    // O que é do visitante vai primeiro; o resto fica escondido atrás de um botão.
    mine.concat(rest).forEach(function (o) { parent.appendChild(o); });
    mine.forEach(function (o) {
      o.classList.add("mine");
      var b = o.querySelector(".btn");
      if (b) b.classList.add("primary");
    });
    if (!rest.length) return;
    var id = "os-rest-" + n;
    rest.forEach(function (o, i) { o.hidden = true; o.id = o.id || id + "-" + i; });
    var more = document.createElement("button");
    more.type = "button";
    more.className = "btn os-more";
    more.setAttribute("aria-controls", rest.map(function (o) { return o.id; }).join(" "));
    function setOpen(open) {
      rest.forEach(function (o) { o.hidden = !open; });
      more.setAttribute("aria-expanded", open ? "true" : "false");
      more.textContent = open ? T.less + " ↑" : T.more + " ↓";
    }
    setOpen(false);
    more.addEventListener("click", function () { setOpen(more.getAttribute("aria-expanded") !== "true"); });
    pick.appendChild(more);
    hidden.push({ rest: rest, open: setOpen });
  });

  // Um link pode apontar para dentro de uma opção escondida: o índice "Nesta página",
  // a busca ou um endereço compartilhado. Aí os outros sistemas abrem e a página vai até lá.
  function target(hash) {
    if (!hash || hash.length < 2) return null;
    var id = hash.slice(1);
    try { id = decodeURIComponent(id); } catch (e) {}
    return document.getElementById(id);
  }
  function reveal(el) {
    var opened = false;
    hidden.forEach(function (h) {
      if (h.rest.some(function (o) { return o.hidden && o.contains(el); })) { h.open(true); opened = true; }
    });
    return opened;
  }
  // Ao abrir a página: as opções mudaram de ordem, então a rolagem do navegador pode ter errado.
  var first = target(location.hash);
  if (first && Array.prototype.some.call(picks, function (p) { return p.contains(first); })) {
    reveal(first);
    first.scrollIntoView();
  }
  // Clique num link para esta página: abre antes, e o navegador rola até o lugar certo.
  document.addEventListener("click", function (e) {
    var a = e.target.closest && e.target.closest("a[href*='#']");
    if (!a || a.origin !== location.origin || a.pathname !== location.pathname) return;
    var el = target(a.hash);
    if (el) reveal(el);
  });
  // Mudou o endereço de outro jeito (a busca, o voltar do navegador).
  window.addEventListener("hashchange", function () {
    var el = target(location.hash);
    if (el && reveal(el)) el.scrollIntoView();
  });
})();
