// SentimentOps demo frontend. Talks to the API exactly as in contracts/README.md.
(function () {
  const cfg = window.SENTIMENTOPS_CONFIG || {};
  const API = (cfg.API_BASE_URL || "").replace(/\/+$/, "");
  const MOCK = API === "";

  const $ = (id) => document.getElementById(id);
  const textEl = $("text");
  const btn = $("analyse");

  // ---------- mock backend (used until the real API exists) ----------
  function mockPredict(text) {
    const t = text.toLowerCase();
    const pos = ["love", "great", "good", "fantastic", "excellent", "happy", "amazing", "wonderful"];
    const neg = ["hate", "bad", "terrible", "slow", "awful", "disappointing", "poor", "sad"];
    const p = pos.filter((w) => t.includes(w)).length;
    const n = neg.filter((w) => t.includes(w)).length;
    const label = p > n ? "POSITIVE" : n > p ? "NEGATIVE" : "NEUTRAL";
    return new Promise((resolve) =>
      setTimeout(() => resolve({
        request_id: crypto.randomUUID ? crypto.randomUUID() : String(Date.now()),
        label,
        score: label === "NEUTRAL" ? 0.9 : Math.min(0.55 + 0.15 * Math.abs(p - n), 0.99),
        model_version: "mock",
        latency_ms: 3,
      }), 250)
    );
  }

  // ---------- API calls ----------
  async function callPredict(text) {
    if (MOCK) return mockPredict(text);
    const res = await fetch(`${API}/predict`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ text }),
    });
    const body = await res.json().catch(() => ({}));
    if (!res.ok) throw new Error(body.error || `Request failed (${res.status})`);
    return body;
  }

  async function checkHealth() {
    const box = $("status");
    if (MOCK) {
      box.className = "status";
      $("status-text").textContent = "Mock mode";
      return;
    }
    try {
      const res = await fetch(`${API}/health`);
      const body = await res.json();
      const ok = res.ok && body.status === "ok";
      box.className = "status " + (ok ? "ok" : "down");
      $("status-text").textContent = ok ? `API online · ${body.model_version}` : "API unhealthy";
    } catch {
      box.className = "status down";
      $("status-text").textContent = "API unreachable";
    }
  }

  // ---------- UI ----------
  function showResult(r) {
    $("result").hidden = false;
    const label = $("label");
    label.textContent = r.label;
    label.className = "badge " + r.label;
    $("score").textContent = Math.round(r.score * 100) + "%";
    const bar = $("bar");
    bar.className = "fill " + r.label;
    bar.style.width = Math.round(r.score * 100) + "%";
    $("latency").textContent = r.latency_ms + " ms";
    $("model").textContent = r.model_version;
    $("request-id").textContent = r.request_id;
  }

  function addHistory(text, r) {
    $("history-card").hidden = false;
    const li = document.createElement("li");
    const tag = document.createElement("span");
    tag.className = "tag " + r.label;
    tag.textContent = r.label;
    const txt = document.createElement("span");
    txt.className = "txt";
    txt.textContent = text;
    txt.title = text;
    li.append(tag, txt);
    $("history").prepend(li);
  }

  function showError(msg) {
    const el = $("error");
    el.hidden = !msg;
    el.textContent = msg || "";
  }

  async function analyse() {
    const text = textEl.value.trim();
    if (!text) { showError("Please type some text first."); return; }
    showError("");
    btn.disabled = true;
    btn.textContent = "Analysing…";
    try {
      const r = await callPredict(text);
      showResult(r);
      addHistory(text, r);
    } catch (e) {
      showError(e.message || "Something went wrong.");
    } finally {
      btn.disabled = false;
      btn.textContent = "Analyse";
    }
  }

  btn.addEventListener("click", analyse);
  textEl.addEventListener("keydown", (e) => {
    if (e.key === "Enter" && (e.ctrlKey || e.metaKey)) analyse();
  });
  textEl.addEventListener("input", () => { $("count").textContent = textEl.value.length; });
  document.querySelectorAll(".chip").forEach((c) =>
    c.addEventListener("click", () => {
      textEl.value = c.textContent;
      $("count").textContent = textEl.value.length;
      analyse();
    })
  );

  $("mode").textContent = MOCK
    ? "Mock mode: set API_BASE_URL in config.js to use the live API."
    : `Connected to ${API}`;
  checkHealth();
})();
