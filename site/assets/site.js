// Site behaviour for the documentation and the home page. No dependencies.
// Everything here is an enhancement: every page is complete without JavaScript.
(function () {
  "use strict";
  var doc = document.documentElement;
  var body = document.body;
  var base = body.dataset.base || "";
  var repo = body.dataset.repo || "";
  var media = function (q) { return window.matchMedia ? window.matchMedia(q) : { matches: false }; };
  var reduceMotion = media("(prefers-reduced-motion: reduce)").matches;
  var isMac = /Mac|iPhone|iPad/.test(navigator.platform || navigator.userAgent);
  var each = function (sel, fn, root) { Array.prototype.forEach.call((root || document).querySelectorAll(sel), fn); };
  var ICON_COPY = '<svg class="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><rect x="9" y="9" width="11" height="11" rx="2"/><path d="M5 15V6a2 2 0 0 1 2-2h9"/></svg>';

  function el(tag, cls, text) {
    var n = document.createElement(tag);
    if (cls) n.className = cls;
    if (text != null) n.textContent = text;
    return n;
  }

  // Announcements for screen readers ("Copied to clipboard").
  var live = el("div", "sr-only");
  live.setAttribute("aria-live", "polite");
  body.appendChild(live);

  // ---------- Header ----------
  each("kbd[data-mod]", function (k) { k.textContent = isMac ? "⌘K" : "Ctrl K"; });

  // ---------- Theme: follows the system until the reader picks one ----------
  var toggle = document.querySelector("[data-theme-toggle]");
  function themeLabel() {
    if (toggle) toggle.setAttribute("aria-label", doc.dataset.theme === "dark" ? "Switch to light theme" : "Switch to dark theme");
  }
  if (toggle) {
    themeLabel();
    toggle.addEventListener("click", function () {
      var next = doc.dataset.theme === "dark" ? "light" : "dark";
      doc.dataset.theme = next;
      try { localStorage.setItem("theme", next); } catch (e) { /* private mode: not remembered */ }
      themeLabel();
      renderDiagrams();
    });
    var scheme = media("(prefers-color-scheme: dark)");
    if (scheme.addEventListener) {
      scheme.addEventListener("change", function (e) {
        var stored = null;
        try { stored = localStorage.getItem("theme"); } catch (x) { /* ignore */ }
        if (stored) return;
        doc.dataset.theme = e.matches ? "dark" : "light";
        themeLabel();
        renderDiagrams();
      });
    }
  }

  // ---------- Copy buttons ----------
  function copyButton(getText) {
    var btn = el("button", "copy-btn");
    btn.type = "button";
    btn.innerHTML = ICON_COPY + "<span>Copy</span>";
    btn.setAttribute("aria-label", "Copy to clipboard");
    btn.addEventListener("click", function () {
      var text = getText();
      var label = btn.querySelector("span");
      var done = function () {
        label.textContent = "Copied";
        btn.setAttribute("data-done", "");
        live.textContent = "Copied to clipboard";
        setTimeout(function () { label.textContent = "Copy"; btn.removeAttribute("data-done"); live.textContent = ""; }, 1600);
      };
      var fallback = function () {
        var ta = el("textarea");
        ta.value = text;
        ta.setAttribute("readonly", "");
        ta.style.cssText = "position:fixed;top:0;opacity:0";
        body.appendChild(ta);
        ta.select();
        try { if (document.execCommand("copy")) done(); } catch (e) { /* nothing to do */ }
        ta.remove();
      };
      if (navigator.clipboard && window.isSecureContext) navigator.clipboard.writeText(text).then(done, fallback);
      else fallback();
    });
    return btn;
  }
  each(".cmdline[data-copy]", function (n) { n.appendChild(copyButton(function () { return n.getAttribute("data-copy"); })); });
  each(".install-card .panel, .verify .panel", function (panel) {
    var pre = panel.querySelector("pre");
    if (!pre) return;
    var btn = copyButton(function () { return pre.innerText.replace(/^\$ /gm, "").replace(/\s+$/, ""); });
    var head = panel.closest(".verify") && panel.closest(".verify").querySelector(".verify-head");
    (head || panel).appendChild(btn);
  });

  // ---------- Documentation pages ----------
  var article = document.querySelector(".doc-body");

  // GitHub alert syntax ("> [!NOTE]") rendered as callouts.
  var LABELS = { note: "Note", tip: "Tip", important: "Important", warning: "Warning", caution: "Caution" };
  each(".doc-body blockquote > p:first-child", function (p) {
    var m = p.innerHTML.match(/^\[!(NOTE|TIP|IMPORTANT|WARNING|CAUTION)\]\s*(<br\s*\/?>)?\s*/);
    if (!m) return;
    var kind = m[1].toLowerCase();
    p.innerHTML = p.innerHTML.slice(m[0].length);
    p.parentNode.classList.add("callout", kind);
    p.parentNode.insertBefore(el("span", "label", LABELS[kind]), p);
  });

  // Mermaid diagrams. The library (about 1 MB) loads only when a diagram is near
  // the viewport, pinned to an exact version and checked with Subresource Integrity.
  var diagrams = [];
  var mermaidReady = false;
  each("pre > code.language-mermaid, div.language-mermaid pre code", function (code) {
    var div = el("div", "mermaid", code.textContent);
    div.dataset.src = code.textContent;
    (code.closest("div.language-mermaid") || code.parentNode).replaceWith(div);
    diagrams.push(div);
  });
  function mermaidConfig() {
    var dark = doc.dataset.theme === "dark";
    return {
      startOnLoad: false, securityLevel: "strict", theme: "base",
      fontFamily: "IBM Plex Sans, system-ui, sans-serif",
      themeVariables: dark
        ? { fontSize: "15px", background: "#17122B", primaryColor: "#261E42", primaryTextColor: "#F1EDFF", primaryBorderColor: "#4A3F70", secondaryColor: "#1B1530", tertiaryColor: "#17122B", lineColor: "#9C93BC", textColor: "#F1EDFF", clusterBkg: "#1B1530", clusterBorder: "#3A3060", edgeLabelBackground: "#17122B", noteBkgColor: "#2A2112", noteTextColor: "#F1EDFF", noteBorderColor: "#D29922" }
        : { fontSize: "15px", background: "#F7F5FC", primaryColor: "#FFFFFF", primaryTextColor: "#1D1336", primaryBorderColor: "#D6CFEA", secondaryColor: "#F1EEF9", tertiaryColor: "#FFFFFF", lineColor: "#625A7C", textColor: "#1D1336", clusterBkg: "#FFFFFF", clusterBorder: "#E7E2F3", edgeLabelBackground: "#F7F5FC", noteBkgColor: "#FFF8C5", noteTextColor: "#1D1336", noteBorderColor: "#9A6700" }
    };
  }
  function renderDiagrams() {
    if (!mermaidReady) return;
    diagrams.forEach(function (d) { d.removeAttribute("data-processed"); d.textContent = d.dataset.src; });
    window.mermaid.initialize(mermaidConfig());
    window.mermaid.run({ nodes: diagrams });
  }
  if (diagrams.length) {
    var lib = el("script");
    lib.src = "https://cdn.jsdelivr.net/npm/mermaid@12.2.0/dist/mermaid.min.js";
    lib.integrity = "sha384-8xUhuLNMjW/cI2Dacg3DR4WliYznvIg0LVG1stctThKD/YVrJFI9TNCFxft5NYgp";
    lib.crossOrigin = "anonymous";
    lib.onload = function () { mermaidReady = true; renderDiagrams(); };
    lib.onerror = function () { diagrams.forEach(function (d) { d.classList.add("mermaid-failed"); }); };
    var loadMermaid = function () { if (!lib.parentNode) document.head.appendChild(lib); };
    if ("IntersectionObserver" in window) {
      var watcher = new IntersectionObserver(function (entries) {
        if (entries.some(function (e) { return e.isIntersecting; })) { watcher.disconnect(); loadMermaid(); }
      }, { rootMargin: "600px 0px" });
      diagrams.forEach(function (d) { watcher.observe(d); });
    } else {
      loadMermaid();
    }
  }

  // Code blocks: a header with the language and a copy button.
  var LANGS = { bash: "Shell", sh: "Shell", shell: "Shell", zsh: "Shell", console: "Terminal", yaml: "YAML", yml: "YAML", json: "JSON", dockerfile: "Dockerfile", docker: "Dockerfile", python: "Python", toml: "TOML", hcl: "HCL", terraform: "Terraform", powershell: "PowerShell", ini: "INI", diff: "Diff", javascript: "JavaScript", js: "JavaScript", html: "HTML", markdown: "Markdown", md: "Markdown", csharp: "C#", go: "Go", ruby: "Ruby", sql: "SQL", xml: "XML" };
  each(".doc-body pre", function (pre) {
    if (pre.closest(".code-block")) return;
    var host = pre.closest("div.highlighter-rouge") || pre;
    var code = pre.querySelector("code");
    var m = (host.className + " " + (code ? code.className : "")).match(/language-([\w-]+)/);
    var lang = m ? m[1].toLowerCase() : "";
    var block = el("div", "code-block");
    var head = el("div", "code-head");
    head.appendChild(el("span", "code-lang", LANGS[lang] || (lang && lang !== "plaintext" && lang !== "text" ? lang.toUpperCase() : "Text")));
    head.appendChild(copyButton(function () { return pre.innerText.replace(/\s+$/, ""); }));
    host.parentNode.insertBefore(block, host);
    block.appendChild(head);
    block.appendChild(host);
  });

  // Tables scroll inside a rounded frame on small screens.
  each(".doc-body table", function (t) {
    var wrap = el("div", "table-wrap");
    t.parentNode.insertBefore(wrap, t);
    wrap.appendChild(t);
  });

  // Checklists: each checkbox is named by its item.
  each(".doc-body li > input[type=checkbox]", function (box) {
    box.setAttribute("aria-label", box.parentNode.textContent.trim());
  });

  // Links to scripts and config files are not pages: send them to the source on GitHub.
  // Keep in step with SOURCE in tools/check-site.py.
  var sourceExt = /\.(sh|ya?ml|py|toml|bats|cff|example|json|css|js)$|\/(leak|Makefile|Dockerfile|LICENSE|gitignore-secrets|dockerignore|pre-commit)$/;
  each(".doc-body a[href]", function (a) {
    var href = a.getAttribute("href");
    if (/^(https?:|mailto:|#)/.test(href)) return;
    var url = new URL(href, window.location.href);
    if (url.origin !== window.location.origin) return;
    var path = url.pathname.indexOf(base) === 0 ? url.pathname.slice(base.length) : url.pathname;
    if (sourceExt.test(path) || /\/(ci|oidc|docker|env|hooks)\/?$/.test(path)) {
      var kind = /\/$/.test(path) || !/\.[a-z]+$|\/(leak|Makefile|Dockerfile|LICENSE)$/.test(path) ? "tree" : "blob";
      a.href = "https://github.com/" + repo + "/" + kind + "/main" + path.replace(/\/$/, "");
    }
  });

  // "On this page", built before the heading anchors are added.
  var toc = document.querySelector(".toc");
  var isChangelog = body.classList.contains("page-changelog");
  // The changelog's contents list releases only; other pages list sections and subsections.
  var heads = article ? Array.prototype.slice.call(article.querySelectorAll(isChangelog ? "h2[id]" : "h2[id], h3[id]")) : [];
  var tocLinks = [];
  if (toc && heads.length >= 3) {
    toc.appendChild(el("p", "toc-title", "On this page"));
    heads.forEach(function (h) {
      var a = el("a", h.tagName === "H3" ? "sub" : "", h.textContent.trim());
      a.href = "#" + h.id;
      toc.appendChild(a);
      tocLinks.push(a);
    });
    var backToTop = el("a", "toc-top", "Back to top ↑");
    backToTop.href = "#content";
    toc.appendChild(backToTop);
    toc.closest(".doc").classList.add("has-toc");
    var spy = function () {
      var line = (parseInt(getComputedStyle(doc).getPropertyValue("--header-h"), 10) || 64) + 96;
      var current = 0;
      for (var i = 0; i < heads.length; i++) { if (heads[i].getBoundingClientRect().top <= line) current = i; else break; }
      if (window.innerHeight + window.scrollY >= document.body.scrollHeight - 4) current = heads.length - 1;
      tocLinks.forEach(function (l, i) { l.classList.toggle("active", i === current); });
    };
    var ticking = false;
    window.addEventListener("scroll", function () {
      if (ticking) return;
      ticking = true;
      requestAnimationFrame(function () { spy(); ticking = false; });
    }, { passive: true });
    spy();
  }

  // Numbered steps ("3. Rotate and revoke") get a number badge.
  heads.forEach(function (h) {
    var first = h.firstChild;
    if (!first || first.nodeType !== 3) return;
    var m = first.nodeValue.match(/^\s*(\d+)\.\s+/);
    if (!m) return;
    first.nodeValue = first.nodeValue.slice(m[0].length);
    h.insertBefore(el("span", "step-num", m[1]), first);
  });

  // Changelog: each release heading becomes a version chip and a date; change types become labels.
  if (isChangelog) {
    heads.forEach(function (h, i) {
      if (h.tagName !== "H2") return;
      var m = h.textContent.match(/^\s*\[?([^\]\s]+)\]?\s*(?:-\s*(\d{4}-\d{2}-\d{2}))?/);
      if (!m) return;
      var link = h.querySelector("a");
      var chip = el(link ? "a" : "span", "ver", m[1] === "Unreleased" ? "Unreleased" : "v" + m[1]);
      if (link) chip.href = link.href;
      h.textContent = "";
      h.appendChild(chip);
      if (m[2]) {
        var t = el("time", "ver-date", new Date(m[2] + "T00:00:00Z").toLocaleDateString("en-GB", { day: "numeric", month: "long", year: "numeric", timeZone: "UTC" }));
        t.dateTime = m[2];
        h.appendChild(t);
      }
      if (tocLinks[i]) tocLinks[i].textContent = h.textContent.replace(/(\d{4})$/, "$1").replace(/^(v\S+|Unreleased)/, "$1 · ").replace(/ · $/, "");
    });
    each(".doc-body h3", function (h) {
      var kind = h.textContent.trim().toLowerCase();
      if (/^(added|fixed|changed|security|removed|deprecated)$/.test(kind)) h.classList.add("kind", "kind-" + kind);
    });
  }

  // Heading anchors.
  heads.forEach(function (h) {
    var a = el("a", "anchor", "#");
    a.href = "#" + h.id;
    a.setAttribute("aria-label", "Link to the section " + h.textContent.trim());
    h.insertBefore(a, h.firstChild);
  });

  // Previous and next page, in sidebar order.
  var pager = document.querySelector(".pager");
  var navLinks = Array.prototype.slice.call(document.querySelectorAll(".sidebar ul a"));
  var here = navLinks.findIndex(function (a) { return a.getAttribute("aria-current") === "page"; });
  if (pager && here >= 0) {
    [[here - 1, "prev", "Previous"], [here + 1, "next", "Next"]].forEach(function (p) {
      var target = navLinks[p[0]];
      if (!target) return;
      var a = el("a", p[1]);
      a.href = target.href;
      a.appendChild(el("span", "", p[2]));
      a.appendChild(document.createTextNode(target.textContent));
      pager.appendChild(a);
    });
  }

  // Sidebar: keep the current page in view; a drawer on small screens.
  var sidebar = document.getElementById("sidebar");
  var menuBtn = document.querySelector(".menu-btn");
  var backdrop = document.querySelector("[data-drawer-close]");
  if (sidebar) {
    var current = sidebar.querySelector('[aria-current="page"]');
    if (current) sidebar.scrollTop = current.offsetTop - sidebar.clientHeight / 2;
  }
  if (sidebar && menuBtn && backdrop) {
    var setDrawer = function (open) {
      sidebar.classList.toggle("open", open);
      backdrop.hidden = !open;
      menuBtn.setAttribute("aria-expanded", String(open));
      menuBtn.setAttribute("aria-label", open ? "Close navigation" : "Open navigation");
      if (open) (sidebar.querySelector('[aria-current="page"]') || sidebar.querySelector("a")).focus();
    };
    menuBtn.addEventListener("click", function () { setDrawer(!sidebar.classList.contains("open")); });
    backdrop.addEventListener("click", function () { setDrawer(false); });
    document.addEventListener("keydown", function (e) {
      if (e.key === "Escape" && sidebar.classList.contains("open")) { setDrawer(false); menuBtn.focus(); }
    });
  }

  // ---------- Search ----------
  var dialog = document.getElementById("search");
  if (dialog && typeof dialog.showModal === "function") {
    var input = document.getElementById("search-input");
    var list = document.getElementById("search-results");
    var empty = dialog.querySelector(".search-empty");
    var index = null, loading = null, items = [], active = -1;
    var START = [
      ["Incident runbook", "/docs/01-runbook.html", "Step-by-step response when a secret or repository leaks"],
      ["Cheat sheet", "/CHEATSHEET.html", "The first 15 minutes on one page"],
      ["Rotate secrets", "/docs/02-rotate-secrets.html", "Revoke and replace each kind of credential"],
      ["Prevention kit", "/prevention/README.html", "Hooks, CI templates and keyless deployments"],
      ["Quick start", "/overview.html#quick-start", "Install the toolkit and run your first audit"]
    ];
    var loadIndex = function () {
      if (!loading) {
        loading = fetch(base + "/search.json").then(function (r) {
          if (!r.ok) throw new Error("HTTP " + r.status);
          return r.json();
        }).then(function (data) {
          index = data.map(function (e) { return { t: e.t, h: e.h, u: e.u, x: e.x, lt: e.t.toLowerCase(), lh: e.h.toLowerCase(), lx: e.x.toLowerCase() }; });
        }, function () {
          loading = null;
          showEmpty("Search is unavailable right now. Use the navigation to browse the documentation.");
        });
      }
      return loading;
    };
    var showEmpty = function (text) { empty.textContent = text; empty.hidden = false; };
    var select = function (i) {
      if (!items.length) { input.removeAttribute("aria-activedescendant"); return; }
      active = (i + items.length) % items.length;
      items.forEach(function (a, j) { a.setAttribute("aria-selected", String(j === active)); });
      input.setAttribute("aria-activedescendant", items[active].id);
      items[active].scrollIntoView({ block: "nearest" });
    };
    var highlight = function (node, text, terms) {
      if (!terms.length) { node.textContent = text; return; }
      var re = new RegExp("(" + terms.map(function (t) { return t.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"); }).join("|") + ")", "ig");
      text.split(re).forEach(function (part, i) {
        node.appendChild(i % 2 ? el("mark", "", part) : document.createTextNode(part));
      });
    };
    var snippet = function (text, terms) {
      var lower = text.toLowerCase(), at = -1;
      terms.some(function (t) { at = lower.indexOf(t); return at > -1; });
      if (at < 0) return text.slice(0, 140);
      var start = Math.max(0, at - 50);
      return (start > 0 ? "…" : "") + text.slice(start, start + 160).trim() + (start + 160 < text.length ? "…" : "");
    };
    var addItem = function (title, page, href, text, terms) {
      var li = el("li");
      li.setAttribute("role", "presentation");
      var a = el("a");
      a.id = "search-option-" + items.length;
      a.href = href;
      a.setAttribute("role", "option");
      var t = el("span", "r-title");
      highlight(t, title, terms);
      if (page) t.appendChild(el("span", "", "· " + page));
      a.appendChild(t);
      if (text) { var x = el("span", "r-text"); highlight(x, text, terms); a.appendChild(x); }
      a.addEventListener("click", function () { dialog.close(); });
      a.addEventListener("mousemove", function () { var i = items.indexOf(a); if (i !== active) select(i); });
      li.appendChild(a);
      list.appendChild(li);
      items.push(a);
    };
    var render = function () {
      var raw = input.value.trim();
      var q = raw.toLowerCase();
      list.textContent = "";
      items = [];
      empty.hidden = true;
      if (!q) {
        var g = el("li", "group", "Start here");
        g.setAttribute("role", "presentation");
        list.appendChild(g);
        START.forEach(function (s) { addItem(s[0], "", base + s[1], s[2], []); });
        select(0);
        return;
      }
      if (!index) {
        loadIndex().then(function () { if (index && input.value.trim() === raw) render(); });
        return;
      }
      var terms = q.split(/\s+/).filter(Boolean);
      var best = {};
      var results = [];
      index.forEach(function (e) {
        var score = 0;
        for (var i = 0; i < terms.length; i++) {
          var s = (e.lt.indexOf(terms[i]) > -1 ? 6 : 0) + (e.lh.indexOf(terms[i]) > -1 ? 8 : 0) + (e.lx.indexOf(terms[i]) > -1 ? 1 : 0);
          if (!s) return;
          score += s;
        }
        if (e.lh.indexOf(q) > -1) score += 12;
        else if (e.lx.indexOf(q) > -1) score += 3;
        if (!e.h && e.lt.indexOf(q) > -1) score += 20;   // the page itself when the query names it
        results.push({ e: e, score: score });
        best[e.t] = Math.max(best[e.t] || 0, score);
      });
      // Group sections of the same page together, best pages first.
      results.sort(function (a, b) { return (best[b.e.t] - best[a.e.t]) || (a.e.t < b.e.t ? -1 : a.e.t > b.e.t ? 1 : 0) || (b.score - a.score); });
      results = results.slice(0, 24);
      if (!results.length) { select(-1); showEmpty("No results for “" + raw + "”. Try a secret type, a command or a platform."); return; }
      results.forEach(function (r) { addItem(r.e.h || r.e.t, r.e.h ? r.e.t : "", base + r.e.u, snippet(r.e.x, terms), terms); });
      select(0);
    };
    var openSearch = function () {
      if (dialog.open) return;
      if (sidebar && sidebar.classList.contains("open") && menuBtn) menuBtn.click();
      dialog.showModal();
      input.value = "";
      render();
      input.focus();
      loadIndex();
    };
    each("[data-search-open]", function (b) { b.addEventListener("click", openSearch); });
    document.addEventListener("keydown", function (e) {
      var tag = (document.activeElement && document.activeElement.tagName) || "";
      if ((e.key === "k" || e.key === "K") && (e.metaKey || e.ctrlKey)) {
        e.preventDefault();
        if (dialog.open) dialog.close(); else openSearch();
      } else if (e.key === "/" && !dialog.open && !/^(INPUT|TEXTAREA|SELECT)$/.test(tag) && !document.activeElement.isContentEditable) {
        e.preventDefault();
        openSearch();
      }
    });
    dialog.addEventListener("click", function (e) { if (e.target === dialog) dialog.close(); });
    input.addEventListener("input", render);
    input.addEventListener("keydown", function (e) {
      if (e.key === "ArrowDown") { e.preventDefault(); select(active + 1); }
      else if (e.key === "ArrowUp") { e.preventDefault(); select(active - 1); }
      else if (e.key === "Enter" && items[active]) { e.preventDefault(); items[active].click(); }
    });
  }

  // ---------- Tabs (WAI-ARIA tabs pattern) ----------
  each('[role="tablist"]', function (tablist) {
    var tabs = Array.prototype.slice.call(tablist.querySelectorAll('[role="tab"]'));
    var section = tablist.closest("section");
    var urlLabel = section && section.querySelector(".url[data-url]");
    var choose = function (tab, focus) {
      tabs.forEach(function (t) {
        var on = t === tab;
        var panel = document.getElementById(t.getAttribute("aria-controls"));
        t.setAttribute("aria-selected", String(on));
        t.tabIndex = on ? 0 : -1;
        if (panel) panel.hidden = !on;
        if (on && panel && urlLabel && panel.dataset.url) urlLabel.textContent = panel.dataset.url;
      });
      if (focus) tab.focus();
      focusScrollables();
    };
    tabs.forEach(function (t, i) {
      t.addEventListener("click", function () { choose(t, false); });
      t.addEventListener("keydown", function (e) {
        var j = { ArrowRight: i + 1, ArrowLeft: i - 1, Home: 0, End: tabs.length - 1 }[e.key];
        if (j === undefined) return;
        e.preventDefault();
        choose(tabs[(j + tabs.length) % tabs.length], true);
      });
    });
  });

  // ---------- Home page: the clock ----------
  // Counts from the moment the page opened. The stopwatch dial covers five minutes,
  // the time attackers have needed to use an exposed cloud key.
  var clocks = document.querySelectorAll("[data-clock]");
  if (clocks.length) {
    var opened = Date.now();
    var wedges = document.querySelectorAll(".ill .wedge");
    var hands = document.querySelectorAll(".ill .hand-g");
    var ticker = document.querySelector(".ticker");
    var pad = function (n) { return (n < 10 ? "0" : "") + n; };
    var tickClock = function () {
      var s = Math.floor((Date.now() - opened) / 1000);
      var h = Math.floor(s / 3600);
      var text = (h ? h + ":" + pad(Math.floor(s / 60) % 60) : pad(Math.floor(s / 60))) + ":" + pad(s % 60);
      var frac = Math.min(s / 300, 1);
      Array.prototype.forEach.call(clocks, function (c) { c.textContent = text; });
      Array.prototype.forEach.call(wedges, function (w) { w.style.strokeDasharray = (frac * 358.1).toFixed(1) + " 358.1"; });
      Array.prototype.forEach.call(hands, function (g) { g.style.transform = "rotate(" + (frac * 360).toFixed(1) + "deg)"; });
      if (ticker) ticker.classList.toggle("over", s >= 300);
    };
    tickClock();
    setInterval(tickClock, 1000);
  }

  // Regions that scroll sideways must be reachable with the keyboard.
  function focusScrollables() {
    each("pre, .table-wrap, .cmdline code", function (n) {
      if (n.closest('[aria-hidden="true"]')) return;
      if (n.scrollWidth > n.clientWidth + 1) n.tabIndex = 0;
      else if (n.getAttribute("tabindex") === "0") n.removeAttribute("tabindex");
    });
  }
  focusScrollables();
  var resizeTimer;
  window.addEventListener("resize", function () { clearTimeout(resizeTimer); resizeTimer = setTimeout(focusScrollables, 200); });
})();
