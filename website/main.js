/* Rift landing — Apple-calibre restraint, GSAP under the hood.
   Content is ALWAYS visible without JS: the .js class gates hidden states. */

const REPO = "https://github.com/MustafaPatharia/rift";
document.querySelectorAll("[data-repo-link]").forEach(a => (a.href = REPO));
document.querySelectorAll("[data-release-link]").forEach(a => (a.href = REPO + "/releases/latest"));

const reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

/* ── glass shards: brand motif scattered down the page, scroll+mouse parallax.
   One fixed layer (like the auroras); each shard tracks a document-Y minus a
   depth-scaled scroll, so far shards drift slow, near ones fast. ── */
if (!reduced) {
  const touch = matchMedia("(hover: none)").matches;
  const docH = document.documentElement.scrollHeight;
  const N = touch ? 4 : 7;
  const variants = [
    "polygon(18% 0, 100% 22%, 82% 100%, 0 74%)",
    "polygon(0 12%, 86% 0, 100% 82%, 22% 100%)",
    "polygon(10% 0, 100% 40%, 74% 100%, 0 60%)",
  ];
  const field = document.createElement("div");
  field.className = "shard-field";
  field.setAttribute("aria-hidden", "true");
  const shards = [];
  for (let i = 0; i < N; i++) {
    const el = document.createElement("div");
    el.className = "shard";
    const depth = 0.15 + (i % 4) * 0.14;              // 4 depth tiers
    const w = 90 + Math.random() * 210;
    el.style.left = (Math.random() * 86) + "%";
    el.style.width = w + "px";
    el.style.height = (w * (0.5 + Math.random() * 0.5)) + "px";
    el.style.clipPath = variants[i % variants.length];
    el.style.opacity = 0.45 + depth;                  // nearer = brighter
    field.appendChild(el);
    shards.push({
      el, depth,
      docY: 720 + Math.random() * Math.max(400, docH - 1200),  // skip hero (crack owns it)
      rot: -30 + Math.random() * 60,
    });
  }
  document.body.appendChild(field);

  let sy = scrollY, mx = 0, my = 0, queued = false;
  const draw = () => {
    queued = false;
    for (const s of shards) {
      const ty = s.docY - sy * (1 - s.depth) + my * s.depth * 0.04;
      const tx = mx * s.depth * 0.05;
      s.el.style.transform = `translate3d(${tx}px, ${ty}px, 0) rotate(${s.rot}deg)`;
    }
  };
  const req = () => { if (!queued) { queued = true; requestAnimationFrame(draw); } };
  addEventListener("scroll", () => { sy = scrollY; req(); }, { passive: true });
  if (!touch) addEventListener("mousemove", e => {
    mx = e.clientX - innerWidth / 2; my = e.clientY - innerHeight / 2; req();
  }, { passive: true });
  draw();
}

if (window.gsap && !reduced) {
  document.documentElement.classList.add("js");
  gsap.registerPlugin(ScrollTrigger);

  /* ── hero: eyebrow → headline → subtitle → keycaps → command bar stagger ── */
  gsap.to(".hero .reveal", {
    opacity: 1, y: 0, duration: 0.9, ease: "power3.out", stagger: 0.1, delay: 0.15,
  });

  /* ── scroll reveals; feature cells + vision cols stagger as a group ── */
  const group = (parent, items) => {
    gsap.to(items, {
      opacity: 1, y: 0, duration: 0.8, ease: "power3.out", stagger: 0.08,
      scrollTrigger: { trigger: parent, start: "top 82%" },
    });
  };
  group(".grid", ".grid .reveal");
  group(".v-cols", ".v-cols .reveal");
  gsap.utils.toArray(
    "section .reveal:not(.grid .reveal):not(.v-cols .reveal):not(.window), footer .reveal"
  ).forEach(el => {
    gsap.to(el, {
      opacity: 1, y: 0, duration: 0.85, ease: "power3.out",
      scrollTrigger: { trigger: el, start: "top 88%" },
    });
  });

  /* ── showcase window: Apple product-shot entrance (rise + settle) ── */
  gsap.fromTo(".window",
    { opacity: 0, y: 70, scale: 0.955 },
    { opacity: 1, y: 0, scale: 1, duration: 1.1, ease: "power3.out",
      scrollTrigger: { trigger: ".window", start: "top 85%" } });

  /* ── statement lede: Apple-style word light-up as you scroll ── */
  document.querySelectorAll(".statement .lede, .privacy .lede").forEach(lede => {
    lede.innerHTML = lede.textContent.trim().split(/\s+/)
      .map(w => `<span class="wd">${w}</span>`).join(" ");
    gsap.to(lede.querySelectorAll(".wd"), {
      color: "#f5f5f7", stagger: 0.35, ease: "none",
      scrollTrigger: { trigger: lede, start: "top 78%", end: "top 32%", scrub: 0.6 },
    });
  });

  /* ── laptop: product-shot physics — rises flat out of a slight tilt ── */
  gsap.to(".laptop", {
    y: -34, ease: "none",
    scrollTrigger: { trigger: ".hero", start: "60% bottom", end: "bottom top", scrub: true },
  });
  gsap.fromTo(".laptop .screen",
    { rotationX: 10, scale: 0.97, transformPerspective: 900, transformOrigin: "50% 0%" },
    { rotationX: 0, scale: 1, ease: "none",
      scrollTrigger: { trigger: ".laptop", start: "top 92%", end: "top 45%", scrub: 0.5 } });

  /* ── feature icons draw themselves in ── */
  document.querySelectorAll(".cell svg").forEach(svg => {
    const shapes = svg.querySelectorAll("path, rect, circle, line");
    shapes.forEach(s => {
      try {
        const len = s.getTotalLength();
        gsap.fromTo(s, { strokeDasharray: len, strokeDashoffset: len },
          { strokeDashoffset: 0, duration: 1.1, ease: "power2.inOut",
            scrollTrigger: { trigger: svg.closest(".cell"), start: "top 85%" } });
      } catch (_) { /* non-geometry element — skip */ }
    });
  });

  /* ── island: eq dance, scrubbers drift, auto-demo once ── */
  document.querySelectorAll(".p-eq i").forEach((bar, i) => {
    gsap.to(bar, {
      height: () => 5 + Math.random() * 8,
      duration: 0.28 + i * 0.07, yoyo: true, repeat: -1, ease: "sine.inOut",
    });
  });
  gsap.to(".ic-scrub i", { width: "86%", duration: 16, yoyo: true, repeat: -1, ease: "none" });
  gsap.to(".wp-scrub i", { width: "90%", duration: 18, yoyo: true, repeat: -1, ease: "none" });

  const island = document.getElementById("island");
  if (island) {
    ScrollTrigger.create({
      trigger: ".laptop", start: "top 70%", once: true,
      onEnter: () => {
        setTimeout(() => island.classList.add("expand"), 500);
        setTimeout(() => island.classList.remove("expand"), 2800);
      },
    });
  }

  /* ── mouse life ─────────────────────────────────────── */
  /* auroras lean toward the cursor (layered depths) */
  const followers = [
    { el: ".wrap-a", fx: 0.05, fy: 0.04 },
    { el: ".wrap-b", fx: -0.07, fy: 0.06 },
    { el: ".wrap-c", fx: 0.04, fy: -0.05 },
  ].map(f => ({
    x: gsap.quickTo(f.el, "x", { duration: 1.2, ease: "power2.out" }),
    y: gsap.quickTo(f.el, "y", { duration: 1.2, ease: "power2.out" }),
    fx: f.fx, fy: f.fy,
  }));
  /* laptop + app window tilt gently toward the pointer */
  const tilts = [".laptop", ".window"].map(sel => {
    const el = document.querySelector(sel);
    return el && {
      el,
      rx: gsap.quickTo(el, "rotationX", { duration: 0.7, ease: "power2.out" }),
      ry: gsap.quickTo(el, "rotationY", { duration: 0.7, ease: "power2.out" }),
    };
  }).filter(Boolean);
  tilts.forEach(t => gsap.set(t.el, { transformPerspective: 1100 }));

  window.addEventListener("mousemove", e => {
    const dx = e.clientX - innerWidth / 2, dy = e.clientY - innerHeight / 2;
    followers.forEach(f => { f.x(dx * f.fx); f.y(dy * f.fy); });
    tilts.forEach(t => {
      const r = t.el.getBoundingClientRect();
      if (r.bottom < -80 || r.top > innerHeight + 80) return;   // off-screen: skip
      const nx = (e.clientX - r.left - r.width / 2) / r.width;
      const ny = (e.clientY - r.top - r.height / 2) / r.height;
      t.rx(-ny * 3.2); t.ry(nx * 3.2);
    });
  }, { passive: true });

  /* glass glare follows the pointer inside cards */
  document.querySelectorAll(".cell, .dl-glass").forEach(card => {
    card.addEventListener("mousemove", e => {
      const r = card.getBoundingClientRect();
      card.style.setProperty("--mx", (e.clientX - r.left) + "px");
      card.style.setProperty("--my", (e.clientY - r.top) + "px");
    }, { passive: true });
  });

  /* ── magnetic primary buttons ── */
  document.querySelectorAll(".btn-solid").forEach(btn => {
    btn.addEventListener("mousemove", e => {
      const r = btn.getBoundingClientRect();
      gsap.to(btn, {
        x: (e.clientX - r.left - r.width / 2) * 0.22,
        y: (e.clientY - r.top - r.height / 2) * 0.34,
        duration: 0.3, ease: "power2.out",
      });
    });
    btn.addEventListener("mouseleave", () =>
      gsap.to(btn, { x: 0, y: 0, duration: 0.5, ease: "elastic.out(1, 0.45)" }));
  });
}
