#!/usr/bin/env bun
/**
 * maestro CLI — S-202 (decide) + S-204 (log/status)
 *
 * Contratos normativos:
 *   docs/architecture/API_SPEC.md   §2 (assinatura, validações, exit codes) e §3 (envelope de erro)
 *   docs/architecture/DATA_MODEL.md §3 (decision record) e §4 (log JSONL)
 *
 * Regras invioláveis respeitadas aqui:
 *   - zero dependências além do stdlib do Bun; sem rede em runtime
 *   - o log só recebe metadados (vocabulário fechado); jamais prompt, jamais caminho completo
 *   - JSONL sempre via JSON.stringify, nunca concatenação manual
 *   - nenhuma métrica usa float (razões são calculadas em centésimos inteiros)
 *
 * Uso: bun src/cli.ts <decide|status|log> [args]
 */

import {
  appendFileSync,
  existsSync,
  mkdirSync,
  readFileSync,
  readdirSync,
  renameSync,
  writeFileSync,
} from "node:fs";
import { basename, dirname, join, resolve } from "node:path";

// ---------------------------------------------------------------- constantes

const MODES = ["direct", "subagent", "multi"] as const;
type Mode = (typeof MODES)[number];

const RE_SESSION = /^[A-Za-z0-9_-]{1,64}$/;
const RE_AGENT = /^[a-z0-9-]+$/;
const RE_PROJECT = /^[A-Za-z0-9._-]{1,48}$/;

const REASON_MAX = 120;
const DEFAULT_TTL_SECONDS = 14400; // 4h — ADR-003 v1.1
const LOG_TAIL_DEFAULT = 20;

/** Vocabulário fechado de eventos (DATA_MODEL §4). */
const EVENTS = [
  "decision",
  "gate_pass",
  "gate_warn",
  "gate_block",
  "override_manual",
  "killswitch",
  "session_end",
] as const;

// -------------------------------------------------------------------- erros

type Category = "config" | "validation" | "env";

class MaestroError extends Error {
  constructor(
    readonly category: Category,
    readonly detail: string,
    readonly fix: string,
  ) {
    super(detail);
    this.name = "MaestroError";
  }
  /** API_SPEC §3: 0 ok · 1 validação · 2 ambiente quebrado. */
  get exitCode(): number {
    return this.category === "validation" ? 1 : 2;
  }
}

const invalid = (detail: string, fix: string) =>
  new MaestroError("validation", detail, fix);
const configErr = (detail: string, fix: string) =>
  new MaestroError("config", detail, fix);
const envErr = (detail: string, fix: string) =>
  new MaestroError("env", detail, fix);

function warn(msg: string): void {
  process.stderr.write(`maestro: aviso: ${msg}\n`);
}

// ------------------------------------------------------------------ tempo

/** ISO-8601 local com offset, precisão de segundos (mesmo formato de `date -Iseconds`). */
function isoLocal(d: Date): string {
  const p = (n: number, w = 2) => String(Math.abs(n)).padStart(w, "0");
  const off = -d.getTimezoneOffset();
  const sign = off >= 0 ? "+" : "-";
  return (
    `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}` +
    `T${p(d.getHours())}:${p(d.getMinutes())}:${p(d.getSeconds())}` +
    `${sign}${p(Math.trunc(off / 60))}:${p(off % 60)}`
  );
}

function ttlSeconds(): number {
  const raw = process.env.MAESTRO_TTL_SECONDS;
  if (!raw) return DEFAULT_TTL_SECONDS;
  const n = Number.parseInt(raw, 10);
  return Number.isFinite(n) && n > 0 ? n : DEFAULT_TTL_SECONDS;
}

/** "2h 13min" a partir de segundos inteiros. */
function humanDuration(totalSeconds: number): string {
  const s = Math.abs(Math.trunc(totalSeconds));
  const h = Math.trunc(s / 3600);
  const m = Math.trunc((s % 3600) / 60);
  if (h > 0) return `${h}h ${String(m).padStart(2, "0")}min`;
  if (m > 0) return `${m}min`;
  return `${s}s`;
}

// ------------------------------------------------------------------ caminhos

function pluginRoot(): string {
  const override = process.env.MAESTRO_PLUGIN_ROOT;
  if (override) return resolve(override);
  return resolve(dirname(import.meta.dir)); // <repo>/src/cli.ts → <repo>
}

function maestroHome(): string {
  const home = process.env.MAESTRO_HOME;
  if (home) return resolve(home);
  const h = process.env.HOME;
  if (!h) {
    throw envErr(
      "nem MAESTRO_HOME nem HOME estão definidos",
      "exporte MAESTRO_HOME=/caminho/para/.maestro",
    );
  }
  return join(h, ".maestro");
}

const sessionsDir = () => join(maestroHome(), "sessions");
const logDir = () => join(maestroHome(), "logs");
const logFile = () => join(logDir(), "routing.jsonl");
const recordPath = (sessionId: string) =>
  join(sessionsDir(), `${sessionId}.json`);

function ensureDirs(): void {
  try {
    mkdirSync(sessionsDir(), { recursive: true });
    mkdirSync(logDir(), { recursive: true });
  } catch {
    throw envErr(
      `não consegui criar o diretório de estado em ${maestroHome()}`,
      "rode `maestro doctor` e verifique permissões de $MAESTRO_HOME",
    );
  }
}

// --------------------------------------------------------- routing table

interface RoutingTable {
  workflows: string[];
  gateMode: string | null;
}

function loadRoutingTable(): RoutingTable {
  const path =
    process.env.MAESTRO_ROUTING_TABLE ??
    join(pluginRoot(), "config", "routing-table.yaml");

  if (!existsSync(path)) {
    throw configErr(
      "routing-table.yaml não encontrado (instalação incompleta)",
      "rode `maestro doctor`",
    );
  }

  let parsed: unknown;
  try {
    parsed = Bun.YAML.parse(readFileSync(path, "utf8"));
  } catch {
    throw configErr(
      "routing-table.yaml não é YAML válido",
      "rode `maestro doctor` e corrija o arquivo",
    );
  }

  const table = parsed as Record<string, unknown> | null;
  const workflowsRaw = table?.workflows;
  if (
    !workflowsRaw ||
    typeof workflowsRaw !== "object" ||
    Array.isArray(workflowsRaw)
  ) {
    throw configErr(
      "routing-table.yaml não declara a seção `workflows`",
      "rode `maestro doctor`",
    );
  }
  const workflows = Object.keys(workflowsRaw as Record<string, unknown>);
  if (workflows.length === 0) {
    throw configErr(
      "routing-table.yaml não declara nenhum workflow",
      "adicione workflows em config/routing-table.yaml",
    );
  }

  const gate = table?.gate as Record<string, unknown> | undefined;
  const gateMode =
    gate && typeof gate.mode === "string" ? (gate.mode as string) : null;

  return { workflows, gateMode };
}

// -------------------------------------------------------------------- roster

/**
 * Nomes válidos do roster (`agents/*.md`, DATA_MODEL §5), em ordem estável.
 *
 * A identidade do agente é o `name:` do frontmatter; o nome do arquivo é só o
 * fallback para um .md sem frontmatter legível. `maestro doctor` exige que os
 * dois coincidam, então na prática são o mesmo valor — mas aqui não se inventa
 * um segundo nome válido para o mesmo agente: a lista devolvida é exatamente a
 * que aparece no erro de `--agents`, e um nome que a lista mostra tem de
 * funcionar. Roster vazio (diretório ausente, sem .md) devolve [] — quem chama
 * decide o que fazer com isso.
 */
function loadRoster(): string[] {
  const dir = join(pluginRoot(), "agents");
  let files: string[];
  try {
    files = readdirSync(dir).filter((f: string) => f.endsWith(".md"));
  } catch {
    return [];
  }
  const names = new Set<string>();
  for (const f of files) {
    let name = f.slice(0, -3);
    try {
      const head = readFileSync(join(dir, f), "utf8").slice(0, 2048);
      const m = head.match(/^name:\s*"?([A-Za-z0-9._-]+)"?\s*$/m);
      if (m) name = m[1]!;
    } catch {
      /* arquivo ilegível não invalida o roster inteiro */
    }
    if (RE_AGENT.test(name)) names.add(name);
  }
  return [...names].sort();
}

// ---------------------------------------------------------------- argumentos

interface Args {
  positional: string[];
  flags: Map<string, string | true>;
}

function parseArgs(argv: string[]): Args {
  const positional: string[] = [];
  const flags = new Map<string, string | true>();
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i]!;
    if (!a.startsWith("--")) {
      positional.push(a);
      continue;
    }
    const body = a.slice(2);
    if (body.length === 0) continue; // "--" separador
    const eq = body.indexOf("=");
    if (eq >= 0) {
      flags.set(body.slice(0, eq), body.slice(eq + 1));
      continue;
    }
    const next = argv[i + 1];
    if (next !== undefined && !next.startsWith("--")) {
      flags.set(body, next);
      i++;
    } else {
      flags.set(body, true);
    }
  }
  return { positional, flags };
}

function requireValue(args: Args, name: string): string | null {
  const v = args.flags.get(name);
  if (v === undefined) return null;
  if (v === true) {
    throw invalid(
      `--${name} exige um valor`,
      `use --${name} <valor>`,
    );
  }
  return v;
}

function rejectUnknown(args: Args, known: string[]): void {
  for (const k of args.flags.keys()) {
    if (!known.includes(k) && k !== "debug") {
      throw invalid(
        `opção desconhecida --${k}`,
        `opções válidas: ${known.map((x) => `--${x}`).join(", ")}`,
      );
    }
  }
}

// ------------------------------------------------------------------ log I/O

interface LogEvent {
  ts?: string;
  event?: string;
  session_id?: string;
  workflow?: string;
  mode?: string;
  agents?: string[] | string;
  [k: string]: unknown;
}

interface LogRead {
  events: LogEvent[];
  malformed: number;
  exists: boolean;
}

function readLog(): LogRead {
  const path = logFile();
  if (!existsSync(path)) return { events: [], malformed: 0, exists: false };
  let raw: string;
  try {
    raw = readFileSync(path, "utf8");
  } catch {
    throw envErr(
      `não consegui ler ${path}`,
      "verifique permissões ou rode `maestro doctor`",
    );
  }
  const events: LogEvent[] = [];
  let malformed = 0;
  for (const line of raw.split("\n")) {
    const t = line.trim();
    if (t === "") continue;
    try {
      const o = JSON.parse(t) as unknown;
      if (o && typeof o === "object" && !Array.isArray(o)) {
        events.push(o as LogEvent);
      } else {
        malformed++;
      }
    } catch {
      malformed++;
    }
  }
  return { events, malformed, exists: true };
}

/**
 * Append de UMA linha JSONL. Sempre via JSON.stringify.
 * Tenta `flock -n` (regra de integridade do DATA_MODEL); se flock não existir,
 * cai para append O_APPEND (atômico para uma escrita curta em arquivo regular).
 * Falha de log NUNCA aborta o comando — o log é subproduto, não trilho.
 */
function appendLog(obj: Record<string, unknown>): void {
  let line: string;
  try {
    line = `${JSON.stringify(obj)}\n`;
  } catch {
    warn("não consegui serializar o evento de log; linha descartada");
    return;
  }
  const path = logFile();
  try {
    const r = Bun.spawnSync({
      cmd: ["flock", "-n", path, "sh", "-c", 'cat >> "$1"', "sh", path],
      stdin: Buffer.from(line),
      stdout: "ignore",
      stderr: "ignore",
    });
    if (r.exitCode === 0) return;
  } catch {
    /* flock ausente → fallback abaixo */
  }
  try {
    appendFileSync(path, line);
  } catch {
    warn("não consegui escrever no routing.jsonl; evento descartado");
  }
}

/** Nome do projeto corrente (só o basename — nunca o caminho). */
function currentProject(): string | null {
  const dir = process.env.CLAUDE_PROJECT_DIR ?? process.cwd();
  const name = basename(resolve(dir));
  return RE_PROJECT.test(name) ? name : null;
}

// ------------------------------------------------------- wtree (E7 / S-701)

/**
 * Fingerprint de conteúdo do working tree do projeto corrente, via
 * `bin/maestro-wtree` (bash puro; padrão adaptado do gstack-wtree — atribuição
 * no próprio script). Amarra a decisão ao ESTADO do repo, não só ao relógio:
 * o TTL diz "a decisão envelheceu"; o wtree diz "o conteúdo andou".
 * Degradação silenciosa (null): sem git, fora de repo, script ausente ou saída
 * inesperada — o record simplesmente não ganha o campo, nada falha.
 * Precedente do spawn: appendLog já chama flock externo; git é dependência de
 * AMBIENTE (validada pelo doctor), não de código — "zero deps além do stdlib
 * do Bun" segue de pé. O hash vai só ao RECORD (DATA_MODEL §3), nunca ao log:
 * o vocabulário do JSONL (§4) fica intocado.
 */
function computeWtree(): string | null {
  try {
    const script = join(pluginRoot(), "bin", "maestro-wtree");
    if (!existsSync(script)) return null;
    const dir = process.env.CLAUDE_PROJECT_DIR ?? process.cwd();
    const r = Bun.spawnSync({
      cmd: ["bash", script, dir],
      stdout: "pipe",
      stderr: "ignore",
    });
    if (r.exitCode !== 0) return null;
    const out = new TextDecoder().decode(r.stdout).trim();
    return /^[0-9a-f]{40}$/.test(out) ? out : null;
  } catch {
    return null;
  }
}

// --------------------------------------------------------- decision record

interface DecisionRecord {
  session_id: string;
  ts: string;
  expires_at: string;
  workflow: string;
  mode: Mode;
  agents?: string[];
  reason?: string;
  wtree?: string;
}

function readRecord(sessionId: string): DecisionRecord | null {
  const p = recordPath(sessionId);
  if (!existsSync(p)) return null;
  try {
    const o = JSON.parse(readFileSync(p, "utf8")) as DecisionRecord;
    return o && typeof o === "object" ? o : null;
  } catch {
    return null;
  }
}

// ---------------------------------------------------------------- comando: decide

function cmdDecide(args: Args): number {
  rejectUnknown(args, ["session", "workflow", "mode", "agents", "reason"]);

  // --session (obrigatório)
  const session = requireValue(args, "session");
  if (!session) {
    throw invalid(
      "--session é obrigatório",
      "use o session_id que o bloco <maestro-routing> injetou: maestro decide --session <id> ...",
    );
  }
  if (!RE_SESSION.test(session)) {
    throw invalid(
      "--session inválido (esperado 1-64 chars em [A-Za-z0-9_-])",
      "use o session_id literal informado pelo hook SessionStart",
    );
  }

  const table = loadRoutingTable();

  // --workflow
  const workflow = requireValue(args, "workflow");
  if (!workflow) {
    throw invalid(
      "--workflow é obrigatório",
      `escolha um de: ${table.workflows.join(", ")}`,
    );
  }
  if (!table.workflows.includes(workflow)) {
    throw invalid(
      `workflow '${workflow}' não existe na routing-table`,
      `escolha um de: ${table.workflows.join(", ")}`,
    );
  }

  // --mode
  const modeRaw = requireValue(args, "mode");
  if (!modeRaw) {
    throw invalid("--mode é obrigatório", `escolha um de: ${MODES.join(", ")}`);
  }
  if (!(MODES as readonly string[]).includes(modeRaw)) {
    throw invalid(
      `mode '${modeRaw}' inválido`,
      `escolha um de: ${MODES.join(", ")}`,
    );
  }
  const mode = modeRaw as Mode;

  // --agents
  const agentsRaw = requireValue(args, "agents");
  let agents: string[] | undefined;

  if (mode === "direct") {
    if (agentsRaw !== null) {
      throw invalid(
        "--agents não se aplica a mode=direct (o record de direct não tem agentes)",
        "remova --agents ou use --mode subagent|multi",
      );
    }
  } else {
    if (agentsRaw === null || agentsRaw.trim() === "") {
      throw invalid(
        `mode '${mode}' exige --agents`,
        "informe --agents a,b,c (nomes do roster)",
      );
    }
    const parts = agentsRaw.split(",").map((s) => s.trim());
    for (const a of parts) {
      if (!RE_AGENT.test(a)) {
        throw invalid(
          `nome de agente inválido: '${a}' (esperado [a-z0-9-])`,
          "use --agents a,b,c com nomes kebab-case do roster",
        );
      }
    }
    const seen = new Set<string>();
    agents = [];
    for (const a of parts) {
      if (seen.has(a)) {
        warn(`agente duplicado ignorado: ${a}`);
        continue;
      }
      seen.add(a);
      agents.push(a);
    }
    if (mode === "multi" && agents.length < 2) {
      throw invalid(
        "mode 'multi' exige pelo menos 2 agentes",
        "use --mode subagent para um único agente",
      );
    }

    // Validação contra o roster (API_SPEC §2: "agentes precisam existir no
    // roster"). A transição acontece sozinha: instalação sem `agents/*.md`
    // (ou com o diretório ausente) só avisa — falhar aí puniria o usuário por
    // uma instalação incompleta, que é assunto do doctor. Com roster presente,
    // nome desconhecido é erro de validação (exit 1) e a mensagem carrega a
    // lista inteira de nomes válidos: é o que torna o erro acionável sem abrir
    // o repo.
    const roster = loadRoster();
    if (roster.length === 0) {
      warn(
        "roster vazio (agents/ sem .md) — nomes de agente não validados; rode `maestro doctor`",
      );
    } else {
      const unknown = agents.filter((a) => !roster.includes(a));
      if (unknown.length > 0) {
        throw invalid(
          `agente(s) fora do roster: ${unknown.join(", ")}`,
          `agentes disponíveis: ${roster.join(", ")}`,
        );
      }
    }
  }

  // --reason (único texto livre permitido; ≤120 chars — mitigação de vazamento de prompt)
  let reason: string | undefined;
  const reasonRaw = requireValue(args, "reason");
  if (reasonRaw !== null) {
    // normaliza: remove controles e colapsa espaços (nada de quebra de linha no record)
    const clean = reasonRaw
      .replace(/[\u0000-\u001f\u007f]/g, " ")
      .replace(/\s+/g, " ")
      .trim();
    if (clean.length > REASON_MAX) {
      warn(
        `--reason truncado em ${REASON_MAX} caracteres (tinha ${clean.length})`,
      );
      reason = clean.slice(0, REASON_MAX);
    } else if (clean.length > 0) {
      reason = clean;
    }
  }

  // ---- gravação
  ensureDirs();

  const now = new Date();
  const ts = isoLocal(now);
  const expires = isoLocal(new Date(now.getTime() + ttlSeconds() * 1000));
  const wtree = computeWtree(); // E7/S-701: ~200ms; aqui no CLI, jamais no gate

  const record: DecisionRecord = {
    session_id: session,
    ts,
    expires_at: expires,
    workflow,
    mode,
    ...(agents ? { agents } : {}),
    ...(reason ? { reason } : {}),
    ...(wtree ? { wtree } : {}),
  };

  const target = recordPath(session);
  const existed = existsSync(target);
  const tmp = `${target}.tmp.${process.pid}`;
  try {
    // write+rename = idempotente por sessão (sobrescreve, nunca duplica)
    writeFileSync(tmp, `${JSON.stringify(record)}\n`, { mode: 0o600 });
    renameSync(tmp, target);
  } catch {
    throw envErr(
      `não consegui gravar o decision record em ${sessionsDir()}`,
      "rode `maestro doctor` e verifique permissões de $MAESTRO_HOME",
    );
  }

  const project = currentProject();
  appendLog({
    ts,
    event: "decision",
    session_id: session,
    workflow,
    mode,
    ...(agents ? { agents } : {}),
    ...(project ? { project } : {}),
  });

  const alvo = agents ? ` agentes=${agents.join(",")}` : "";
  process.stdout.write(
    `${existed ? "decisão atualizada" : "decisão registrada"}: ` +
      `sessão=${session} workflow=${workflow} mode=${mode}${alvo}\n` +
      `válida até ${expires} (TTL ${humanDuration(ttlSeconds())})\n`,
  );
  return 0;
}

// ---------------------------------------------------------------- comando: status

/** Resolve a sessão corrente: --session > env do Claude Code > record mais recente. */
function resolveSession(args: Args): { id: string; origin: string } | null {
  const explicit = requireValue(args, "session");
  if (explicit) {
    if (!RE_SESSION.test(explicit)) {
      throw invalid(
        "--session inválido (esperado 1-64 chars em [A-Za-z0-9_-])",
        "confira o session_id",
      );
    }
    return { id: explicit, origin: "--session" };
  }
  for (const key of ["CLAUDE_SESSION_ID", "MAESTRO_SESSION_ID"]) {
    const v = process.env[key];
    if (v && RE_SESSION.test(v)) return { id: v, origin: `$${key}` };
  }
  // fallback: record mais recente em disco
  try {
    const dir = sessionsDir();
    const files = readdirSync(dir).filter((f: string) => f.endsWith(".json"));
    let best: { id: string; mtime: number } | null = null;
    for (const f of files) {
      const st = Bun.file(join(dir, f));
      const m = st.lastModified;
      if (!best || m > best.mtime) best = { id: f.slice(0, -5), mtime: m };
    }
    if (best) return { id: best.id, origin: "record mais recente" };
  } catch {
    /* diretório inexistente é caso normal */
  }
  return null;
}

function formatEvent(e: LogEvent): string {
  const skip = new Set(["ts", "event"]);
  const parts: string[] = [];
  for (const [k, v] of Object.entries(e)) {
    if (skip.has(k) || v === undefined || v === null) continue;
    parts.push(`${k}=${Array.isArray(v) ? v.join(",") : String(v)}`);
  }
  const ts = typeof e.ts === "string" ? e.ts : "?";
  const ev = typeof e.event === "string" ? e.event : "?";
  return `${ts}  ${ev.padEnd(15)} ${parts.join(" ")}`.trimEnd();
}

function cmdStatus(args: Args): number {
  rejectUnknown(args, ["session"]);
  const out: string[] = [];
  out.push("maestro — status");

  const killswitch = process.env.MAESTRO_OFF === "1";
  out.push(
    `  kill-switch : ${killswitch ? "ATIVO (MAESTRO_OFF=1) — hooks desligados" : "inativo"}`,
  );
  out.push(`  estado em   : ${maestroHome()}`);

  let gateMode = "?";
  try {
    gateMode = loadRoutingTable().gateMode ?? "?";
  } catch {
    gateMode = "indisponível (routing-table ilegível)";
  }
  out.push(`  gate.mode   : ${gateMode}`);

  const sess = resolveSession(args);
  out.push("");
  if (!sess) {
    out.push("Sessão: nenhuma identificada.");
    out.push(
      "  Nenhuma decisão registrada. Registre com: maestro decide --session <id> --workflow <w> --mode <m>",
    );
  } else {
    out.push(`Sessão: ${sess.id}  (origem: ${sess.origin})`);
    const rec = readRecord(sess.id);
    if (!rec) {
      out.push(
        "  Nenhuma decisão registrada para esta sessão. Registre com: maestro decide --session " +
          `${sess.id} --workflow <w> --mode <m>`,
      );
    } else {
      const agents = Array.isArray(rec.agents) ? rec.agents.join(",") : "—";
      out.push(`  workflow  : ${rec.workflow ?? "?"}`);
      out.push(`  mode      : ${rec.mode ?? "?"}`);
      out.push(`  agentes   : ${agents}`);
      out.push(`  registrada: ${rec.ts ?? "?"}`);
      const expMs = rec.expires_at ? Date.parse(rec.expires_at) : Number.NaN;
      if (Number.isNaN(expMs)) {
        out.push(`  validade  : desconhecida (expires_at ausente/ilegível)`);
      } else {
        const deltaSec = Math.trunc((expMs - Date.now()) / 1000);
        out.push(
          deltaSec > 0
            ? `  validade  : válida por mais ${humanDuration(deltaSec)} (expira ${rec.expires_at})`
            : `  validade  : EXPIRADA há ${humanDuration(deltaSec)} — registre uma nova decisão`,
        );
      }
      if (rec.reason) out.push(`  motivo    : ${rec.reason}`);
      // E7/S-701: freshness de conteúdo — comparação feita AQUI (CLI, sem NFR
      // de latência), nunca no pre-tool-gate (<50ms; o wtree custa ~200ms).
      // Limitação honesta: compara contra o diretório corrente; `status` rodado
      // de outro projeto reporta divergência sem significado — a mensagem
      // aponta isso em vez de fingir certeza.
      if (rec.wtree) {
        const cur = computeWtree();
        if (!cur) {
          out.push(
            "  conteúdo  : não verificável daqui (sem git neste diretório)",
          );
        } else if (cur === rec.wtree) {
          out.push("  conteúdo  : inalterado desde a decisão (wtree confere)");
        } else {
          out.push(
            "  conteúdo  : ALTERADO desde a decisão (wtree difere) — decisão possivelmente stale; re-registre se o plano mudou",
          );
        }
      }
    }
  }

  const log = readLog();
  out.push("");
  if (!log.exists) {
    out.push(
      "Últimos eventos: log ainda não existe (nenhum evento registrado até agora).",
    );
  } else if (log.events.length === 0) {
    out.push("Últimos eventos: log vazio.");
  } else {
    out.push("Últimos 5 eventos:");
    for (const e of log.events.slice(-5)) out.push(`  ${formatEvent(e)}`);
  }
  if (log.malformed > 0) {
    out.push(`  (${log.malformed} linha(s) ilegível(is) ignorada(s))`);
  }

  process.stdout.write(`${out.join("\n")}\n`);
  return 0;
}

// ------------------------------------------------------------------ comando: log

/** Razão a/b como texto pt-BR com 2 casas, calculada em centésimos INTEIROS (sem float). */
function ratio(a: number, b: number): string {
  if (b === 0) return "—";
  const hundredths = Math.round((a * 100) / b);
  const int = Math.trunc(hundredths / 100);
  const frac = String(Math.abs(hundredths % 100)).padStart(2, "0");
  return `${int},${frac}`;
}

/** Percentual inteiro (0-100). */
function pct(a: number, b: number): string {
  if (b === 0) return "—";
  return `${Math.round((a * 100) / b)}%`;
}

function bump(m: Map<string, number>, k: string, by = 1): void {
  m.set(k, (m.get(k) ?? 0) + by);
}

function sortedEntries(m: Map<string, number>): [string, number][] {
  return [...m.entries()].sort((x, y) => y[1] - x[1] || x[0].localeCompare(y[0]));
}

function cmdLog(args: Args): number {
  rejectUnknown(args, ["summary", "limit"]);
  const log = readLog();

  if (!log.exists) {
    process.stdout.write(
      `maestro — log\n  ${logFile()} ainda não existe.\n` +
        "  Nenhum evento foi registrado (hooks nunca rodaram ou o kill-switch está ativo).\n",
    );
    return 0;
  }

  const summary = args.flags.has("summary");
  if (!summary) {
    const limRaw = requireValue(args, "limit");
    let limit = LOG_TAIL_DEFAULT;
    if (limRaw !== null) {
      const n = Number.parseInt(limRaw, 10);
      if (!Number.isFinite(n) || n <= 0) {
        throw invalid("--limit deve ser um inteiro positivo", "use --limit 50");
      }
      limit = n;
    }
    const out: string[] = [];
    out.push(
      `maestro — log (${log.events.length} evento(s); exibindo os ${Math.min(limit, log.events.length)} últimos)`,
    );
    if (log.events.length === 0) out.push("  (log vazio)");
    for (const e of log.events.slice(-limit)) out.push(`  ${formatEvent(e)}`);
    if (log.malformed > 0) {
      out.push(`  (${log.malformed} linha(s) inválida(s) ignorada(s))`);
    }
    out.push("  dica: `maestro log --summary` mostra o painel agregado.");
    process.stdout.write(`${out.join("\n")}\n`);
    return 0;
  }

  // -------------------------------------------------- agregação (--summary)
  const byEvent = new Map<string, number>();
  const byMode = new Map<string, number>();
  const byAgent = new Map<string, number>();
  const byWorkflow = new Map<string, number>();
  const byCommand = new Map<string, number>();
  const decisionsPerSession = new Map<string, number>();
  const passPerSession = new Map<string, number>();
  let unknownEvent = 0;
  let firstTs: string | null = null;
  let lastTs: string | null = null;

  for (const e of log.events) {
    const ev = typeof e.event === "string" ? e.event : "";
    if (!(EVENTS as readonly string[]).includes(ev)) {
      unknownEvent++;
      continue;
    }
    bump(byEvent, ev);
    if (typeof e.ts === "string") {
      if (firstTs === null) firstTs = e.ts;
      lastTs = e.ts;
    }
    const sid = typeof e.session_id === "string" ? e.session_id : "(sem sessão)";

    if (ev === "decision") {
      bump(decisionsPerSession, sid);
      if (typeof e.mode === "string") bump(byMode, e.mode);
      if (typeof e.workflow === "string") bump(byWorkflow, e.workflow);
      const ag = Array.isArray(e.agents)
        ? e.agents
        : typeof e.agents === "string" && e.agents !== ""
          ? e.agents.split(",")
          : [];
      for (const a of ag) if (typeof a === "string" && a !== "") bump(byAgent, a);
    } else if (ev === "gate_pass") {
      bump(passPerSession, sid);
    } else if (ev === "override_manual") {
      const c = typeof e.cmd === "string" ? e.cmd : "(sem nome)";
      bump(byCommand, c);
    }
  }

  const g = (k: string) => byEvent.get(k) ?? 0;
  const decisions = g("decision");
  const overrides = g("override_manual");
  const routed = decisions + overrides;
  const pass = g("gate_pass");
  const warnN = g("gate_warn");
  const block = g("gate_block");

  const out: string[] = [];
  out.push("maestro — resumo do routing.jsonl");
  out.push(
    `  arquivo: ${logFile()}  ·  ${log.events.length} evento(s)` +
      (log.malformed > 0 ? `  ·  ${log.malformed} linha(s) inválida(s)` : ""),
  );
  if (firstTs && lastTs) out.push(`  janela : ${firstTs}  →  ${lastTs}`);
  if (unknownEvent > 0) {
    out.push(`  aviso  : ${unknownEvent} evento(s) fora do vocabulário fechado`);
  }

  out.push("");
  out.push("ROTEAMENTO (métrica principal — ADR-008)");
  out.push(`  decisões registradas (decision) : ${decisions}`);
  out.push(`  overrides manuais (override_manual): ${overrides}`);
  out.push(
    `  taxa de roteamento automático   : ${pct(decisions, routed)} (${decisions}/${routed})`,
  );
  out.push(`  taxa de override manual         : ${pct(overrides, routed)}`);
  if (byCommand.size > 0) {
    out.push("  comandos usados no override:");
    for (const [k, v] of sortedEntries(byCommand)) out.push(`    /${k}: ${v}`);
  }

  out.push("");
  out.push("GATE (S-203)");
  out.push(`  gate_pass  : ${pass}`);
  out.push(`  gate_warn  : ${warnN}`);
  out.push(`  gate_block : ${block}`);
  out.push(
    `  edits_per_decision : ${ratio(pass, decisions)} gate_pass por decision record` +
      (decisions === 0 ? "  (sem decisões ainda)" : ""),
  );
  out.push(
    "    ↑ ADR-008: valor alto = um único record liberando a sessão inteira.",
  );
  const worst = [...passPerSession.entries()]
    .map(([sid, p]) => ({ sid, p, d: decisionsPerSession.get(sid) ?? 0 }))
    .sort((a, b) => b.p - a.p || a.sid.localeCompare(b.sid))
    .slice(0, 3);
  if (worst.length > 0) {
    out.push("  sessões com mais gate_pass:");
    for (const w of worst) {
      out.push(
        `    ${w.sid}: ${w.p} gate_pass / ${w.d} decisão(ões)` +
          (w.d === 0 ? "  ← passes sem decisão registrada" : ` = ${ratio(w.p, w.d)}`),
      );
    }
  }

  out.push("");
  out.push("DISTRIBUIÇÃO DAS DECISÕES");
  if (byMode.size === 0) {
    out.push("  (nenhuma decisão registrada)");
  } else {
    out.push("  por mode:");
    for (const [k, v] of sortedEntries(byMode)) {
      out.push(`    ${k.padEnd(9)} ${String(v).padStart(4)}  ${pct(v, decisions)}`);
    }
    if (byWorkflow.size > 0) {
      out.push("  por workflow:");
      for (const [k, v] of sortedEntries(byWorkflow)) {
        out.push(`    ${k.padEnd(9)} ${String(v).padStart(4)}  ${pct(v, decisions)}`);
      }
    }
    if (byAgent.size > 0) {
      out.push("  agentes mais roteados:");
      for (const [k, v] of sortedEntries(byAgent)) {
        out.push(`    ${k.padEnd(20)} ${String(v).padStart(4)}`);
      }
    } else {
      out.push("  agentes: nenhum (todas as decisões em mode=direct)");
    }
  }

  const others = (["killswitch", "session_end"] as const)
    .map((k) => `${k}=${g(k)}`)
    .join("  ");
  out.push("");
  out.push(`OUTROS EVENTOS  ${others}`);

  process.stdout.write(`${out.join("\n")}\n`);
  return 0;
}

// ---------------------------------------------------------------------- main

const USAGE = `maestro <comando>
  decide --session <id> --workflow <w> --mode <direct|subagent|multi>
         [--agents a,b,c] [--reason "..."]     registra a decisão de roteamento
  status [--session <id>]                      decisão corrente, kill-switch, últimos eventos
  log    [--summary] [--limit N]               eventos do routing.jsonl (--summary = painel)
opções globais: --debug (mostra stack trace)
`;

function main(argv: string[]): number {
  const args = parseArgs(argv);
  const cmd = args.positional[0];

  if (cmd === undefined || args.flags.has("help")) {
    if (cmd === undefined && !args.flags.has("help")) {
      process.stderr.write(
        "maestro: validation: nenhum subcomando informado (fix: use decide, status ou log)\n",
      );
      process.stderr.write(USAGE);
      return 1;
    }
    process.stdout.write(USAGE);
    return 0;
  }

  args.positional.shift();

  switch (cmd) {
    case "decide":
      return cmdDecide(args);
    case "status":
      return cmdStatus(args);
    case "log":
      return cmdLog(args);
    default:
      throw invalid(
        `subcomando desconhecido '${cmd}'`,
        "use decide, status ou log",
      );
  }
}

const debug = process.argv.includes("--debug");
try {
  process.exit(main(process.argv.slice(2)));
} catch (err) {
  if (err instanceof MaestroError) {
    process.stderr.write(
      `maestro: ${err.category}: ${err.detail} (fix: ${err.fix})\n`,
    );
    if (debug && err.stack) process.stderr.write(`${err.stack}\n`);
    process.exit(err.exitCode);
  }
  const msg = err instanceof Error ? err.message : String(err);
  process.stderr.write(
    `maestro: env: falha inesperada: ${msg} (fix: rode \`maestro doctor\`; use --debug para detalhes)\n`,
  );
  if (debug && err instanceof Error && err.stack) {
    process.stderr.write(`${err.stack}\n`);
  }
  process.exit(2);
}
