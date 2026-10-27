// Documentation site behaviour: callouts, diagrams, links to source files, mobile menu.
(function () {
  "use strict";
  var base = document.body.dataset.base || "";
  var repo = document.body.dataset.repo || "";

  // GitHub alert syntax ("> [!NOTE]") rendered as styled callouts.
  document.querySelectorAll("blockquote > p:first-child").forEach(function (p) {
    var m = p.innerHTML.match(/^\[!(NOTE|TIP|IMPORTANT|WARNING|CAUTION)\]\s*(<br\s*\/?>)?/);
    if (!m) return;
    var kind = m[1].toLowerCase();
    p.innerHTML = p.innerHTML.slice(m[0].length);
    var label = document.createElement("span");
    label.className = "label";
    label.textContent = kind;
    p.parentNode.classList.add("callout", kind);
    p.parentNode.insertBefore(label, p);
  });

  // Mermaid diagrams: fenced ```mermaid blocks become rendered diagrams.
  var blocks = document.querySelectorAll("pre > code.language-mermaid, div.language-mermaid pre code");
  blocks.forEach(function (code) {
    var div = document.createElement("div");
    div.className = "mermaid";
    div.textContent = code.textContent;
    var wrapper = code.closest("div.language-mermaid") || code.parentNode;
    wrapper.replaceWith(div);
  });
  // The diagram library (about 1 MB) loads only on pages that have a diagram,
  // pinned to an exact version and checked with Subresource Integrity.
  if (blocks.length) {
    var lib = document.createElement("script");
    lib.src = "https://cdn.jsdelivr.net/npm/mermaid@12.2.0/dist/mermaid.min.js";
    lib.integrity = "sha384-8xUhuLNMjW/cI2Dacg3DR4WliYznvIg0LVG1stctThKD/YVrJFI9TNCFxft5NYgp";
    lib.crossOrigin = "anonymous";
    lib.onload = function () {
      var dark = window.matchMedia && window.matchMedia("(prefers-color-scheme: dark)").matches;
      window.mermaid.initialize({ startOnLoad: false, theme: dark ? "dark" : "neutral", securityLevel: "strict" });
      window.mermaid.run({ querySelector: ".mermaid" });
    };
    var load = function () { if (!lib.parentNode) document.head.appendChild(lib); };
    // Wait until a diagram is close to the viewport, so pages open fast.
    if ("IntersectionObserver" in window) {
      var watcher = new IntersectionObserver(function (entries) {
        if (entries.some(function (e) { return e.isIntersecting; })) { watcher.disconnect(); load(); }
      }, { rootMargin: "600px 0px" });
      document.querySelectorAll(".mermaid").forEach(function (d) { watcher.observe(d); });
    } else {
      load();
    }
  }

  // Checklists: give each checkbox the text of its item as an accessible name.
  document.querySelectorAll(".content li > input[type=checkbox]").forEach(function (box) {
    box.setAttribute("aria-label", box.parentNode.textContent.trim());
  });

  // Links to scripts and config files are not part of the site: send them to the source on GitHub.
  var sourceExt = /\.(sh|ya?ml|py|toml|bats|cff|example|json)$|\/(leak|Makefile|Dockerfile|LICENSE|gitignore-secrets|dockerignore|pre-commit)$/;
  document.querySelectorAll(".content a[href]").forEach(function (a) {
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

  // Mobile menu.
  var button = document.querySelector(".menu");
  var sidebar = document.getElementById("sidebar");
  if (button && sidebar) {
    button.addEventListener("click", function () {
      var open = sidebar.classList.toggle("open");
      button.setAttribute("aria-expanded", String(open));
    });
  }
})();

// ---------- Docs and landing enhancements ----------
(function () {
  "use strict";

  // Copy buttons on code blocks and the hero command line.
  function addCopy(container, getText) {
    var btn = document.createElement("button");
    btn.type = "button";
    btn.className = "copy-btn";
    btn.textContent = "Copy";
    btn.setAttribute("aria-label", "Copy to clipboard");
    btn.addEventListener("click", function () {
      if (!navigator.clipboard) return;
      navigator.clipboard.writeText(getText()).then(function () {
        btn.textContent = "Copied";
        btn.setAttribute("data-done", "");
        setTimeout(function () { btn.textContent = "Copy"; btn.removeAttribute("data-done"); }, 1600);
      });
    });
    container.appendChild(btn);
  }
  document.querySelectorAll("pre:not(.term-body)").forEach(function (pre) {
    if (pre.closest(".mermaid")) return;
    var wrap = document.createElement("div");
    wrap.className = "copy-wrap";
    pre.parentNode.insertBefore(wrap, pre);
    wrap.appendChild(pre);
    addCopy(wrap, function () { return pre.innerText.replace(/\s+$/, ""); });
  });
  document.querySelectorAll(".cmdline[data-copy]").forEach(function (el) {
    addCopy(el, function () { return el.getAttribute("data-copy"); });
  });

  // "On this page" contents for long documents.
  var body = document.querySelector(".doc-body");
  var toc = document.querySelector(".toc");
  if (body && toc) {
    var heads = body.querySelectorAll("h2[id], h3[id]");
    if (heads.length >= 4) {
      var title = document.createElement("p");
      title.textContent = "On this page";
      toc.appendChild(title);
      heads.forEach(function (h) {
        var a = document.createElement("a");
        a.href = "#" + h.id;
        a.textContent = h.textContent;
        if (h.tagName === "H3") a.style.paddingLeft = "24px";
        toc.appendChild(a);
      });
      toc.parentNode.classList.add("has-toc");
      if ("IntersectionObserver" in window) {
        var links = toc.querySelectorAll("a");
        var obs = new IntersectionObserver(function (entries) {
          entries.forEach(function (e) {
            if (!e.isIntersecting) return;
            links.forEach(function (l) { l.classList.toggle("active", l.getAttribute("href") === "#" + e.target.id); });
          });
        }, { rootMargin: "-80px 0px -70% 0px" });
        heads.forEach(function (h) { obs.observe(h); });
      }
    }
  }

  // Previous / next page, in sidebar order.
  var pager = document.querySelector(".pager");
  var navLinks = Array.prototype.slice.call(document.querySelectorAll(".sidebar a"));
  var here = navLinks.findIndex(function (a) { return a.getAttribute("aria-current") === "page"; });
  if (pager && here >= 0) {
    [[here - 1, "prev", "Previous"], [here + 1, "next", "Next"]].forEach(function (p) {
      var target = navLinks[p[0]];
      if (!target) return;
      var a = document.createElement("a");
      a.href = target.href;
      a.className = p[1];
      a.innerHTML = "<span>" + p[2] + "</span>";
      a.appendChild(document.createTextNode(target.textContent));
      pager.appendChild(a);
    });
  }

  // Sidebar filter.
  var filter = document.getElementById("filter");
  if (filter) {
    filter.addEventListener("input", function () {
      var q = filter.value.trim().toLowerCase();
      document.querySelectorAll(".sidebar li").forEach(function (li) {
        li.hidden = q !== "" && li.textContent.toLowerCase().indexOf(q) === -1;
      });
      document.querySelectorAll(".sidebar ul").forEach(function (ul) {
        var any = Array.prototype.some.call(ul.children, function (li) { return !li.hidden; });
        ul.hidden = !any;
        if (ul.previousElementSibling) ul.previousElementSibling.hidden = !any;
      });
    });
  }

  // Install tabs (WAI-ARIA tabs pattern: arrow keys move between tabs).
  var tabs = Array.prototype.slice.call(document.querySelectorAll('[role="tab"]'));
  function select(tab) {
    tabs.forEach(function (t) {
      var on = t === tab;
      t.setAttribute("aria-selected", String(on));
      t.tabIndex = on ? 0 : -1;
      document.getElementById(t.getAttribute("aria-controls")).hidden = !on;
    });
    tab.focus();
  }
  tabs.forEach(function (t, i) {
    t.addEventListener("click", function () { select(t); });
    t.addEventListener("keydown", function (e) {
      if (e.key === "ArrowRight") select(tabs[(i + 1) % tabs.length]);
      if (e.key === "ArrowLeft") select(tabs[(i - 1 + tabs.length) % tabs.length]);
    });
  });
})();
