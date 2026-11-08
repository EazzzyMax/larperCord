// Instalação: mostra primeiro o caminho do sistema de quem visita e deixa os
// outros a um clique. Sem JavaScript, todas as opções ficam à vista.
// ?os=arch, ?os=linux ou ?os=windows na URL força uma escolha (para testar).
(function () {
  var picks = document.querySelectorAll("[data-os-pick]");
  if (!picks.length) return;
  var pt = document.documentElement.dataset.lang === "pt";
  var T = pt
    ? { windows: "Mostrando a instalação para Windows, que o seu navegador informou.", linux: "Mostrando a instalação para Linux, que o seu navegador informou. Escolha a linha da sua distro.", distro: "Mostrando a instalação para a sua distro Linux, que o seu navegador informou.", arch: "Mostrando a instalação para Arch Linux.", none: "O larperCord roda em Linux e Windows (x86_64). Escolha o computador onde vai usar:", more: "Outros sistemas", less: "Esconder os outros sistemas" }
    : { windows: "Showing the install for Windows, as your browser reports.", linux: "Showing the install for Linux, as your browser reports. Pick the line for your distro.", distro: "Showing the install for your Linux distro, as your browser reports.", arch: "Showing the install for Arch Linux.", none: "larperCord runs on Linux and Windows (x86_64). Pick the computer you'll use it on:", more: "Other systems", less: "Hide the other systems" };

  // Os sistemas a mostrar primeiro, na ordem, e a frase de cima.
  function detect() {
    var forced = /[?&]os=(arch|linux|windows)\b/.exec(location.search);
    if (forced) return { show: [forced[1]], say: forced[1] === "linux" ? T.distro : T[forced[1]] };
    var platform = "";
    try { platform = (navigator.userAgentData && navigator.userAgentData.platform) || ""; } catch (e) {}
    var ua = navigator.userAgent || "";
    // Celular, tablet, Chromebook e Mac não têm versão: tudo fica à vista.
    if (platform ? !/^(Windows|Linux)$/i.test(platform) : /Android|iPhone|iPad|iPod|CrOS|Macintosh/i.test(ua)) return { show: [], say: T.none };
    if (/^Windows$/i.test(platform) || /Windows/i.test(ua)) return { show: ["windows"], say: T.windows };
    if (/^Linux$/i.test(platform) || /X11|Linux/i.test(ua)) {
      // O navegador não diz a distro, mas alguns pacotes põem o nome dela no userAgent.
      if (/Arch Linux|Manjaro|EndeavourOS|CachyOS|Garuda/i.test(ua)) return { show: ["arch"], say: T.arch };
      if (/Ubuntu|Debian|Fedora|Mint|openSUSE|SUSE|Pop!?_OS|elementary|Zorin|CentOS|Red Hat/i.test(ua)) return { show: ["linux"], say: T.distro };
      return { show: ["arch", "linux"], say: T.linux };
    }
    return { show: [], say: T.none };
  }

  var found = detect();
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
    more.setAttribute("aria-expanded", "false");
    more.setAttribute("aria-controls", rest.map(function (o) { return o.id; }).join(" "));
    more.textContent = T.more + " ↓";
    more.addEventListener("click", function () {
      var open = more.getAttribute("aria-expanded") !== "true";
      rest.forEach(function (o) { o.hidden = !open; });
      more.setAttribute("aria-expanded", open ? "true" : "false");
      more.textContent = open ? T.less + " ↑" : T.more + " ↓";
    });
    pick.appendChild(more);
  });
})();
