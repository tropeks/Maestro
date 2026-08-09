#!/usr/bin/env bun
// tests/eval/prescribe.ts — S-402, instrumento (A): APROXIMAÇÃO DETERMINÍSTICA.
//
// ATENÇÃO METODOLÓGICA (leia antes de citar qualquer número daqui):
// o roteador real do Maestro é um LLM (ADR-002) — não existe função que decida o
// workflow. Este arquivo NÃO simula o LLM. Ele responde a uma pergunta diferente e
// mais estreita, que é objetivamente decidível:
//
//     "O TEXTO da routing table, lido ao pé da letra, já leva ao roteamento certo?"
//
// Tudo o que ele sabe vem de `routes[].intent` e `execution_heuristics` do YAML. Onde
// a regra precisa de informação que a tabela não dá (contagem de arquivos) ou de um
// léxico que a tabela não declara ("linguagem detectada" — detectada como?), isso está
// marcado ABAIXO como ASSUNÇÃO DA APROXIMAÇÃO e conta contra a tabela no relatório,
// não contra o caso.
//
// Um acerto aqui é evidência forte (a tabela sozinha basta). Um erro aqui é um
// CANDIDATO a defeito da tabela — o LLM pode acertar mesmo assim, usando as descrições
// do roster (always-on) e conhecimento de mundo. Por isso o número deste arquivo é um
// PISO, nunca a métrica da AC da S-402. A métrica da AC sai do instrumento (B),
// julgamento cego de LLM, e do instrumento (C), log real. Ver docs/ROUTING_EVAL.md.
//
// Uso:
//   bun tests/eval/prescribe.ts --tsv        veredito por caso (padrão)
//   bun tests/eval/prescribe.ts --json       o mesmo, estruturado
//   bun tests/eval/prescribe.ts --summary    só os totais
//   bun tests/eval/prescribe.ts --stem       what-if: intents casados por radical
//   bun tests/eval/prescribe.ts --profile    what-if: linguagem vem do .maestro.yaml
//   bun tests/eval/prescribe.ts --cases      matriz CEGA (sem expected), para o juiz
//   bun tests/eval/prescribe.ts --selftest   asserções sobre a própria aproximação
//
// Env: MAESTRO_ROUTING_TABLE, MAESTRO_EVAL_CASES.

import { basename } from "node:path";

const HERE = new URL(".", import.meta.url).pathname;
const REPO = new URL("../../", import.meta.url).pathname;
const TABLE_PATH = process.env.MAESTRO_ROUTING_TABLE ?? `${REPO}config/routing-table.yaml`;
const CASES_PATH = process.env.MAESTRO_EVAL_CASES ?? `${HERE}cases.yaml`;

// ---------------------------------------------------------------------------
// ASSUNÇÕES DA APROXIMAÇÃO (o que a tabela NÃO declara e este arquivo inventou).
// Cada uma é dívida da routing table, listada no relatório de calibração.
// ---------------------------------------------------------------------------
const ASSUMPTIONS = [
  "A1 léxico de linguagem: a heurística diz 'linguagem detectada' sem dizer por quais tokens.",
  "A2 léxico de 'mecânica/repetitiva': idem — sem definição, virou lista de palavras aqui.",
  "A3 precedência entre heurísticas: a tabela não ordena; adotou-se a ordem de declaração.",
  "A4 contagem de arquivos: H1/H2 dependem de nº de arquivos, que o enunciado nunca traz.",
  "A5 sem rota casada → custom: a tabela documenta custom como escape hatch, mas não diz que o não-casamento cai nele.",
];

// ASSUNÇÃO A1 — léxico de linguagem (aproximação, não conteúdo da tabela).
const LANG_LEXICON: Array<[string, RegExp]> = [
  ["golang-pro", /\b(go|golang|goroutine|go\.mod|\.go)\b/],
  ["python-pro", /\b(python|py|django|fastapi|pytest|pydantic|uv|ruff|\.py)\b/],
  ["typescript-pro", /\b(ts|tsx|typescript|javascript|js|react|front|frontend|tela|telinha|componente)\b/],
  ["postgres-pro", /\b(postgres|postgresql|sql|query|tabela|coluna|indice|index|migration|migracao|schema)\b/],
];

// ASSUNÇÃO A2 — léxico de tarefa mecânica.
const MECHANICAL = /\b(todos os|todas as|renomeia|renomear|troca todos|padroniza|padronizar|lint|imports?|formatar)\b/;

// ASSUNÇÃO A2b — léxico de arquitetura / review (H4).
const ARCH = /\b(arquitetura|desenho|decidir|alternativa|trade-?off)\b/;
const REVIEW = /\b(revisa|revisar|revisada|review|code review)\b/;

// ---------------------------------------------------------------------------
type Expected = { workflow: string; mode: string; agents: string[] };
type Case = {
  id: string; prompt: string; project?: string; stack?: string; kind?: string;
  expected: Expected; ambiguous?: boolean; competes?: string; rationale?: string;
};
type Prescribed = Expected & { why: string[]; conflicts: string[] };

const norm = (s: string) =>
  s.normalize("NFD").replace(/\p{M}+/gu, "").toLowerCase().replace(/\s+/g, " ").trim();

// radical grosseiro para o modo --stem: corta sufixos verbais/plurais comuns do pt-BR.
const stem = (w: string) =>
  w.replace(/(ar|er|ir|ando|endo|indo|ada|ado|adas|ados|a|o|e|as|os|es|s)$/u, "");

async function loadTable() {
  const raw = await Bun.file(TABLE_PATH).text();
  const y: any = Bun.YAML.parse(raw);
  const routes: Array<{ intent: string; workflow: string }> = y?.routes ?? [];
  const workflows: Record<string, { steps: string[]; gate: string }> = y?.workflows ?? {};
  const heuristics: string[] = y?.execution_heuristics ?? [];
  return { version: y?.version, routes, workflows, heuristics };
}

async function loadCases(): Promise<Case[]> {
  const y: any = Bun.YAML.parse(await Bun.file(CASES_PATH).text());
  return y?.cases ?? [];
}

// --- R-W1: workflow ---------------------------------------------------------
// Cada `intent` é uma lista de frases separadas por vírgula. Casamento LITERAL por
// substring sobre o enunciado normalizado (sem stemming: stemming seria a aproximação
// consertando a tabela por baixo do pano e escondendo o defeito). Empate → ordem de
// declaração em routes[]. Zero casamentos → custom (A5).
function prescribeWorkflow(
  prompt: string,
  routes: Array<{ intent: string; workflow: string }>,
  useStem: boolean,
): { workflow: string; why: string[] } {
  const p = norm(prompt);
  const pStems = new Set(p.split(/[^\p{L}\p{N}.]+/u).filter(Boolean).map(stem));
  let best: { workflow: string; hits: string[] } | null = null;

  for (const r of routes) {
    const phrases = String(r.intent).split(",").map((s) => norm(s)).filter(Boolean);
    const hits: string[] = [];
    for (const ph of phrases) {
      if (p.includes(ph)) { hits.push(ph); continue; }
      if (useStem) {
        const need = ph.split(" ").filter(Boolean).map(stem);
        if (need.length && need.every((t) => pStems.has(t))) hits.push(`${ph}~stem`);
      }
    }
    if (hits.length && (!best || hits.length > best.hits.length)) {
      best = { workflow: r.workflow, hits };
    }
  }
  if (!best) return { workflow: "custom", why: ["R-W1: nenhum intent casou → custom (A5)"] };
  return { workflow: best.workflow, why: [`R-W1: intent «${best.hits.join(" + ")}» → ${best.workflow}`] };
}

// --- R-M1: mode -------------------------------------------------------------
// H1 "edição ≤2 arquivos sem plano → direct"  : inaplicável (A4, sem contagem)
// H2 "feature nova ou >3 arquivos → subagent" : aplicável pela metade (workflow==feature)
// nenhuma heurística produz `multi`.
function prescribeMode(workflow: string): { mode: string; why: string[] } {
  if (workflow === "feature") return { mode: "subagent", why: ["R-M1/H2: workflow feature → subagent"] };
  return { mode: "direct", why: ["R-M1: nenhuma heurística aplicável → direct (fallback; H1 exige contagem de arquivos — A4)"] };
}

// --- R-A1: agentes ----------------------------------------------------------
// Ordem de declaração das heurísticas (A3): H3 mecânica → H4 arquitetura/review →
// H5 linguagem. Acumula e reporta conflito quando mais de uma dispara.
function prescribeAgents(prompt: string): { agents: string[]; why: string[]; conflicts: string[] } {
  const p = norm(prompt);
  const why: string[] = [];
  const conflicts: string[] = [];
  const fired: string[] = [];

  if (MECHANICAL.test(p)) { fired.push("dev-junior"); why.push("R-A1/H3: tarefa mecânica → dev-junior (A2)"); }
  if (ARCH.test(p)) { fired.push("engenheiro"); why.push("R-A1/H4: arquitetura → engenheiro (A2b)"); }
  if (REVIEW.test(p)) { fired.push("revisor"); why.push("R-A1/H4: review → revisor (A2b)"); }
  const langs = LANG_LEXICON.filter(([, re]) => re.test(p)).map(([a]) => a);
  if (langs.length) { why.push(`R-A1/H5: linguagem → ${langs.join(", ")} (A1)`); }

  if (fired.length && langs.length) {
    conflicts.push(`H3/H4 (${fired.join(",")}) × H5 (${langs.join(",")}) — tabela não declara precedência (A3)`);
    return { agents: fired, why, conflicts };            // ordem de declaração: H3/H4 vencem
  }
  const agents = fired.length ? fired : langs;
  if (!agents.length) why.push("R-A1: nenhuma heurística de agente disparou → []");
  return { agents, why, conflicts };
}

// what-if `--profile`: simula a linguagem chegando do profile do projeto
// (.maestro.yaml `languages`/`experts`, DATA_MODEL §2) em vez de ser adivinhada no
// enunciado. NÃO é vazamento de gabarito — `stack` é fato do repositório, disponível
// em runtime; `expected` continua invisível para o prescritor.
const STACK_TOKENS: Record<string, string> = {
  go: "go", python: "python", py: "python", ts: "ts", react: "ts",
  postgres: "postgres", sql: "postgres",
};
function profileTokens(stack?: string): string {
  if (!stack) return "";
  const toks = norm(stack).split(/[^a-z0-9]+/).map((t) => STACK_TOKENS[t]).filter(Boolean);
  return toks.length ? ` ${[...new Set(toks)].join(" ")}` : "";
}

function prescribe(
  c: Case, table: Awaited<ReturnType<typeof loadTable>>, useStem: boolean, useProfile: boolean,
): Prescribed {
  const w = prescribeWorkflow(c.prompt, table.routes, useStem);
  const m = prescribeMode(w.workflow);
  const a = prescribeAgents(c.prompt + (useProfile ? profileTokens(c.stack) : ""));
  return { workflow: w.workflow, mode: m.mode, agents: a.agents, why: [...w.why, ...m.why, ...a.why], conflicts: a.conflicts };
}

const sameSet = (a: string[], b: string[]) =>
  a.length === b.length && [...a].sort().join(",") === [...b].sort().join(",");

type Verdict = {
  id: string; prompt: string; ambiguous: boolean;
  expected: Expected; got: Prescribed;
  okWorkflow: boolean; okMode: boolean; okAgents: boolean; ok: boolean;
};

function judgeAll(cases: Case[], table: any, useStem: boolean, useProfile: boolean): Verdict[] {
  return cases.map((c) => {
    const got = prescribe(c, table, useStem, useProfile);
    const okWorkflow = got.workflow === c.expected.workflow;
    const okMode = got.mode === c.expected.mode;
    const okAgents = sameSet(got.agents, c.expected.agents ?? []);
    return {
      id: c.id, prompt: c.prompt, ambiguous: !!c.ambiguous,
      expected: c.expected, got,
      okWorkflow, okMode, okAgents, ok: okWorkflow && okMode && okAgents,
    };
  });
}

const mark = (b: boolean) => (b ? "ok " : "XX ");
const fmtAgents = (a: string[]) => (a.length ? a.join("+") : "—");

function renderTsv(vs: Verdict[]) {
  const out: string[] = [];
  out.push(["caso", "amb", "wf.esp", "wf.presc", "", "mode.esp", "mode.presc", "", "agents.esp", "agents.presc", "", "veredito"].join("\t"));
  for (const v of vs) {
    out.push([
      v.id, v.ambiguous ? "amb" : "",
      v.expected.workflow, v.got.workflow, mark(v.okWorkflow),
      v.expected.mode, v.got.mode, mark(v.okMode),
      fmtAgents(v.expected.agents ?? []), fmtAgents(v.got.agents), mark(v.okAgents),
      v.ok ? "ACERTO" : "ERRO",
    ].join("\t"));
  }
  return out.join("\n");
}

function summary(vs: Verdict[]) {
  const n = vs.length;
  const c = (f: (v: Verdict) => boolean) => vs.filter(f).length;
  return {
    total: n,
    exato: c((v) => v.ok),
    workflow: c((v) => v.okWorkflow),
    mode: c((v) => v.okMode),
    agents: c((v) => v.okAgents),
    ambiguos_total: c((v) => v.ambiguous),
    ambiguos_ok: c((v) => v.ambiguous && v.ok),
  };
}

// --- selftest: asserções sobre a própria aproximação ------------------------
// A aproximação é código; código precisa de teste (regra de ouro do contrato).
// Aqui NÃO se testa a routing table — testa-se que o prescritor faz o que documenta.
async function selftest(): Promise<number> {
  let fail = 0;
  const t = (name: string, cond: boolean) => {
    console.log(`${cond ? "ok  " : "FAIL"} ${name}`);
    if (!cond) fail = 1;
  };
  const table = await loadTable();

  t("tabela carrega com routes e heuristics", table.routes.length > 0 && table.heuristics.length > 0);
  t("normalização remove acento e caixa", norm("Migração ÍNDICE") === "migracao indice");

  const wf = (p: string, s = false) => prescribeWorkflow(p, table.routes, s).workflow;
  t("R-W1 casa intent literal (quebrou→fix)", wf("o login quebrou") === "fix");
  t("R-W1 sem casamento → custom", wf("escreve um resumo pro meu irmao") === "custom");
  // Esta asserção provava o defeito R1 (routes no infinitivo não casavam o imperativo
  // do Romulo). O R1 foi corrigido — as âncoras foram reescritas no imperativo —, então
  // ela foi invertida: agora prova que a correção pegou, e volta a falhar se alguém
  // devolver as rotas para o infinitivo.
  t("R-W1 imperativo casa (R1 corrigido: adiciona→feature)", wf("adiciona o campo cnpj") === "feature");
  t("R-W1 rota de ship existe (R2 corrigido)", wf("sobe isso pra produção") === "ship");
  t("R-W1 rota de audit existe (R2 corrigido)", wf("dá uma olhada de segurança") === "audit");
  t("R-W1 --stem casa imperativo", wf("adiciona o campo cnpj", true) === "feature");
  t("R-M1 feature → subagent", prescribeMode("feature").mode === "subagent");
  t("R-M1 fix → direct (fallback)", prescribeMode("fix").mode === "direct");
  t("R-M1 nunca prescreve multi", ["fix", "feature", "refactor", "ship", "audit", "custom"]
    .every((w) => prescribeMode(w).mode !== "multi"));
  const a1 = prescribeAgents("arruma o parse em go");
  t("R-A1/H5 detecta go", sameSet(a1.agents, ["golang-pro"]));
  const a2 = prescribeAgents("troca todos os console.log por logger no front");
  t("R-A1 conflito H3×H5 é reportado", a2.conflicts.length === 1 && sameSet(a2.agents, ["dev-junior"]));
  const a3 = prescribeAgents("manda pra producao");
  t("R-A1 sem sinal → nenhum agente", a3.agents.length === 0);

  const cases = await loadCases();
  t("matriz tem ≥12 casos", cases.length >= 12);
  t("todo caso tem expected completo", cases.every((c) =>
    c.expected && typeof c.expected.workflow === "string" && typeof c.expected.mode === "string" && Array.isArray(c.expected.agents)));
  t("workflows esperados existem na tabela", cases.every((c) => c.expected.workflow in table.workflows));
  t("modes esperados são do vocabulário", cases.every((c) => ["direct", "subagent", "multi"].includes(c.expected.mode)));
  const roster = new Set([...new Bun.Glob("*.md").scanSync(`${REPO}agents`)].map((f) => basename(f, ".md")));
  t("agentes esperados existem no roster", cases.every((c) => (c.expected.agents ?? []).every((a) => roster.has(a))));
  t("≥2 casos ambíguos", cases.filter((c) => c.ambiguous).length >= 2);
  t("≥1 caso custom", cases.filter((c) => c.expected.workflow === "custom").length >= 1);
  const ids = cases.map((c) => c.id);
  t("ids únicos", new Set(ids).size === ids.length);

  return fail;
}

// --- main -------------------------------------------------------------------
const argv = process.argv.slice(2);
const has = (f: string) => argv.includes(f);

if (has("--selftest")) process.exit(await selftest());

const table = await loadTable();
const cases = await loadCases();
// O número só vale colado à revisão da tabela que o produziu: a routing table muda
// (o agente A está mexendo nela agora) e um score órfão de revisão é anedota.
const TABLE_SHA = new Bun.CryptoHasher("sha256").update(await Bun.file(TABLE_PATH).text()).digest("hex");

// --- instrumento (B): pontuação do TSV do juiz cego -------------------------
// Entrada: <id>\t<workflow>\t<mode>\t<agentes csv|->. O gabarito (cases.yaml) só é
// aberto AQUI, depois que o juiz já respondeu — a separação entre gerar o prompt e
// pontuar existe para que o juiz nunca possa ter visto o expected.
if (has("--score")) {
  const path = argv[argv.indexOf("--score") + 1];
  if (!path) { console.error("--score exige o caminho do TSV"); process.exit(2); }
  const byId = new Map(cases.map((c) => [c.id, c]));
  const seen = new Set<string>();
  const rows = (await Bun.file(path).text()).split("\n")
    .map((l) => l.replace(/\r$/, "").trim()).filter((l) => l && !l.startsWith("#"));
  let ok = 0, okW = 0, okM = 0, okA = 0, n = 0;
  const errs: string[] = [];
  for (const line of rows) {
    const [id, w, m, aRaw] = line.split("\t").map((x) => (x ?? "").trim());
    const c = byId.get(id);
    if (!c) { console.error(`aviso: id desconhecido no TSV, ignorado: ${id}`); continue; }
    if (seen.has(id)) { console.error(`aviso: id duplicado no TSV, ignorado: ${id}`); continue; }
    seen.add(id);
    const agents = !aRaw || aRaw === "-" ? [] : aRaw.split(",").map((x) => x.trim()).filter(Boolean);
    const dW = w === c.expected.workflow, dM = m === c.expected.mode, dA = sameSet(agents, c.expected.agents ?? []);
    n++; if (dW) okW++; if (dM) okM++; if (dA) okA++;
    if (dW && dM && dA) { ok++; }
    else {
      const diff = [
        !dW && `workflow ${c.expected.workflow}→${w}`,
        !dM && `mode ${c.expected.mode}→${m}`,
        !dA && `agentes ${fmtAgents(c.expected.agents ?? [])}→${fmtAgents(agents)}`,
      ].filter(Boolean).join(" · ");
      errs.push(`- ${id}${c.ambiguous ? " (ambíguo por desenho)" : ""}: ${diff}`);
    }
    console.log(`${dW && dM && dA ? "ok " : "XX "} ${id}\t${w}/${m}/${fmtAgents(agents)}`);
  }
  const missing = cases.filter((c) => !seen.has(c.id)).map((c) => c.id);
  if (missing.length) console.log(`\naviso: casos ausentes no TSV do juiz (contam como erro): ${missing.join(", ")}`);
  const total = cases.length;
  if (errs.length || missing.length) {
    console.log("\n## Divergências juiz × gabarito");
    for (const e of errs) console.log(e);
    for (const m of missing) console.log(`- ${m}: sem resposta do juiz`);
  }
  console.log("");
  console.log(`tabela: ${basename(TABLE_PATH)} v${table.version ?? "?"} sha256:${TABLE_SHA.slice(0, 12)}`);
  console.log(`JULGAMENTO CEGO (${basename(path)}): ${ok}/${total} exatos ` +
    `| workflow ${okW}/${total} | mode ${okM}/${total} | agentes ${okA}/${total}`);
  process.exit(0);
}

// --- instrumento (B'): concordância entre juízes -----------------------------
// O único número desta avaliação que NÃO depende de julgamento nenhum: dois LLMs
// independentes lendo a MESMA tabela ou concordam ou não. Discordância alta numa
// dimensão significa que a tabela é subdeterminada ali — conclusão que não precisa
// de gabarito e portanto não precisa de mim.
if (has("--agree")) {
  const i = argv.indexOf("--agree");
  const [pa, pb] = [argv[i + 1], argv[i + 2]];
  if (!pa || !pb) { console.error("--agree exige dois TSV"); process.exit(2); }
  const read = async (p: string) => {
    const m = new Map<string, { w: string; m: string; a: string[] }>();
    for (const l of (await Bun.file(p).text()).split("\n")) {
      const t = l.replace(/\r$/, "").trim();
      if (!t || t.startsWith("#")) continue;
      const [id, w, mo, aRaw] = t.split("\t").map((x) => (x ?? "").trim());
      m.set(id, { w, m: mo, a: !aRaw || aRaw === "-" ? [] : aRaw.split(",").map((x) => x.trim()).filter(Boolean) });
    }
    return m;
  };
  const A = await read(pa), B = await read(pb);
  let n = 0, aw = 0, am = 0, aa = 0, ax = 0;
  const div: string[] = [];
  for (const c of cases) {
    const x = A.get(c.id), y = B.get(c.id);
    if (!x || !y) continue;
    n++;
    const dw = x.w === y.w, dm = x.m === y.m, da = sameSet(x.a, y.a);
    if (dw) aw++; if (dm) am++; if (da) aa++; if (dw && dm && da) ax++;
    if (!(dw && dm && da)) {
      div.push(`- ${c.id}: ${[!dw && `workflow ${x.w}≠${y.w}`, !dm && `mode ${x.m}≠${y.m}`,
        !da && `agentes ${fmtAgents(x.a)}≠${fmtAgents(y.a)}`].filter(Boolean).join(" · ")}`);
    }
  }
  if (div.length) { console.log("## Onde os dois juízes discordam"); for (const d of div) console.log(d); console.log(""); }
  console.log(`tabela: ${basename(TABLE_PATH)} v${table.version ?? "?"} sha256:${TABLE_SHA.slice(0, 12)}`);
  console.log(`CONCORDÂNCIA ENTRE JUÍZES (${basename(pa)} × ${basename(pb)}): ${ax}/${n} exatos ` +
    `| workflow ${aw}/${n} | mode ${am}/${n} | agentes ${aa}/${n}`);
  process.exit(0);
}

if (has("--cases")) {
  // Matriz CEGA para o instrumento (B): só o que o Romulo diria. Nada de expected,
  // nada de stack, nada de rationale — se vazasse, o juiz estaria copiando o gabarito.
  for (const c of cases) console.log(`${c.id}\t${c.prompt}`);
  process.exit(0);
}

const useStem = has("--stem");
const useProfile = has("--profile");
const vs = judgeAll(cases, table, useStem, useProfile);
const s = summary(vs);

if (has("--json")) {
  console.log(JSON.stringify({ table: TABLE_PATH, table_version: table.version, table_sha256: TABLE_SHA, stem: useStem, profile: useProfile, assumptions: ASSUMPTIONS, summary: s, verdicts: vs }, null, 2));
  process.exit(0);
}

if (!has("--summary")) {
  console.log(renderTsv(vs));
  console.log("");
  const errs = vs.filter((v) => !v.ok);
  if (errs.length) {
    console.log("## Diagnóstico dos erros (candidatos a calibração da tabela)");
    for (const v of errs) {
      const dims = [!v.okWorkflow && "workflow", !v.okMode && "mode", !v.okAgents && "agents"].filter(Boolean).join("+");
      console.log(`- ${v.id} [${dims}]${v.ambiguous ? " (ambíguo por desenho)" : ""}`);
      for (const w of v.got.why) console.log(`    ${w}`);
      for (const k of v.got.conflicts) console.log(`    conflito: ${k}`);
    }
    console.log("");
  }
  console.log("## Assunções desta aproximação (dívida da tabela, não do caso)");
  for (const a of ASSUMPTIONS) console.log(`- ${a}`);
  console.log("");
}

const variant = [useStem && "--stem", useProfile && "--profile"].filter(Boolean).join(" ");
console.log(`tabela: ${basename(TABLE_PATH)} v${table.version ?? "?"} sha256:${TABLE_SHA.slice(0, 12)}`);
console.log(`APROXIMAÇÃO DETERMINÍSTICA${variant ? ` (${variant})` : ""}: ${s.exato}/${s.total} exatos ` +
  `| workflow ${s.workflow}/${s.total} | mode ${s.mode}/${s.total} | agentes ${s.agents}/${s.total} ` +
  `| ambíguos ${s.ambiguos_ok}/${s.ambiguos_total}`);
