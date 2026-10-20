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
  realpathSync,
  renameSync,
  statSync,
  writeFileSync,
} from "node:fs";
import { basename, dirname, join, resolve, sep } from "node:path";

// ---------------------------------------------------------------- constantes

const MODES = ["direct", "subagent", "multi"] as const;
type Mode = (typeof MODES)[number];

const RE_SESSION = /^[A-Za-z0-9_-]{1,64}$/;
const RE_AGENT = /^[a-z0-9-]+$/;
const RE_PROJECT = /^[A-Za-z0-9._-]{1,48}$/;

const REASON_MAX = 120;
const DEFAULT_TTL_SECONDS = 14400; // 4h — ADR-003 v1.1
const LOG_TAIL_DEFAULT = 20;

// E17/S-1701 — profundidade/perfil/brief regido do decision record.
const DEPTH_VALUES = ["standard", "deep", "day-zero"] as const;
const PROFILE_VALUES = ["prototipo", "piloto", "produto"] as const;
const BRIEF_MARKERS = ["essencia:", "impacto:", "approach:"] as const;
const BRIEF_MARKER_MAX = 200;
const BRIEF_TOTAL_MAX = 700;

/** Vocabulário fechado de eventos (DATA_MODEL §4). */
const EVENTS = [
  "decision",
  "gate_pass",
  "gate_warn",
  "gate_block",
  "override_manual",
  "killswitch",
  "session_end",
  "conduct", // E17/S-1701 — verbo bash de mutação do record (flags/approach)
  // Eventos emitidos pelos verbos bash (common.sh é a autoridade; esta lista só
  // decide o que `maestro log --summary` agrega em vez de jogar em unknownEvent).
  "habit_warn",
  "consent_grant",
  "consent_revoke",
  "outcome",
  "budget_warn",
  "order_create",
  "order_accept",
  "upgrade",
  "delegation", // E23a — funil planned/started/received/accepted
  "intent", // E22 — direção versionada
  "verify", // E23b — verificações obrigatórias por área
  "route_fix", // ordem 030 — correção de rota
  "turno_teto", // ordem 046 — teto de bloqueios do Stop de turno
  "turno_timeout", // ordem 056 — o check do Stop estourou o teto de tempo (rc 124)
  "conform", // ordem 042/048 — maestro conform --check
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
  // E17/S-1701 — gate DECLARADO por workflow (workflows.<nome>.gate), usado
  // pelo enforcement plan-gated do --brief. Ausente na entry = "none".
  gates: Record<string, string>;
  // E28 — gatilhos determinísticos por domínio (seção `domains:`). null = a
  // tabela não declara nenhum; `gate: domain` sem esta seção é erro de config.
  domains: DomainTriggerMap | null;
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
  const workflowsMap = workflowsRaw as Record<string, unknown>;
  const workflows = Object.keys(workflowsMap);
  if (workflows.length === 0) {
    throw configErr(
      "routing-table.yaml não declara nenhum workflow",
      "adicione workflows em config/routing-table.yaml",
    );
  }

  // E17/S-1701 — gate por workflow (workflows.<nome>.gate). Entry malformada
  // ou sem `gate` string degrada para "none": o enforcement do --brief só age
  // quando o YAML declara "plan" explicitamente.
  const gates: Record<string, string> = {};
  for (const name of workflows) {
    const entry = workflowsMap[name];
    const g =
      entry && typeof entry === "object" && !Array.isArray(entry)
        ? (entry as Record<string, unknown>).gate
        : undefined;
    gates[name] = typeof g === "string" ? g : "none";
  }

  const gate = table?.gate as Record<string, unknown> | undefined;
  const gateMode =
    gate && typeof gate.mode === "string" ? (gate.mode as string) : null;

  const domains = parseDomains(table?.domains);
  if (domains === null && Object.values(gates).includes("domain")) {
    throw configErr(
      "routing-table.yaml declara `gate: domain` sem a seção `domains`",
      "declare domains.security e domains.infrastructure (rode `maestro doctor`)",
    );
  }

  return { workflows, gateMode, gates, domains };
}

// ------------------------------------------- diretoria por domínio (E28)
//
// Contrato mínimo do pedido e da decisão: tropeks/spock:docs/diretoria/
// (CONTRATO.md). O Maestro NÃO decide nada aqui: classifica o plano por regra
// (gatilhos da routing table), registra o pedido no record e diz ao gerente
// que a decisão vem do diretor do domínio, pela Ponte. Timeout nunca aprova:
// sem decisão registrada, o pedido fica pendente até o record expirar.

const DOMAINS = ["security", "infrastructure"] as const;
type Domain = (typeof DOMAINS)[number];
const DOMAIN_TRIGGER_KEYS = ["paths", "keywords", "dockerfile", "other"] as const;
type DomainTriggers = Record<(typeof DOMAIN_TRIGGER_KEYS)[number], string[]>;
type DomainTriggerMap = Partial<Record<Domain, DomainTriggers>>;

const RE_TARGET = /^[A-Za-z0-9._@+/-]{1,200}$/;
const RE_ORDER_REF = /^[A-Za-z0-9._:#/-]{1,64}$/;
const TARGETS_MAX = 32;
const SCOPE_MAX = 1500; // `domain.scope` é lido pelo gate (bash) numa janela fixa
const EFFECTS_MAX = 8;
const EFFECT_MAX = 120;
// CONTRATO v2 (`rollback_ref`: `<caminho>#<ancora>` resolvível): caminho ASCII relativo ao
// projeto com âncora obrigatória, no mesmo alfabeto do `REF_CAMINHO_RE` do daemon
// (ponte-daemon, domain/diretoria.ts), que o resolve de novo no branch da ordem.
const RE_ROLLBACK_REF = /^([A-Za-z0-9_.][A-Za-z0-9._/-]{0,159})#([a-z0-9][a-z0-9_-]{0,79})$/;
// O daemon recusa o `rollback_ref` inteiro (caminho + âncora) acima de 200 chars (ITEM_MAX,
// CHECK da migração 0045) e o que `ehPlaceholder` acusa (ponte-daemon, domain/diretoria.ts):
// recusar aqui evita o pedido que a Ponte devolveria.
const ROLLBACK_REF_MAX = 200;
const RE_PLACEHOLDER_INTEIRO =
  /(\.\.\.)|(^\s*(\?+|-+|n\/?a|none|null|tbd|todo|pendente|a definir|exemplo|example|placeholder|x{3,})\s*$)|(\b(placeholder|lorem)\b)/i;
const RE_PLACEHOLDER_MARCADOR = /\b(TODO|TBD|FIXME)\b/;
const ROLLBACK_FILE_MAX = 1024 * 1024;

function parseDomains(raw: unknown): DomainTriggerMap | null {
  if (raw === undefined || raw === null) return null;
  if (typeof raw !== "object" || Array.isArray(raw)) {
    throw configErr(
      "routing-table.yaml: `domains` não é um mapa",
      "rode `maestro doctor` e corrija a seção domains",
    );
  }
  const out: DomainTriggerMap = {};
  for (const [name, body] of Object.entries(raw as Record<string, unknown>)) {
    if (!(DOMAINS as readonly string[]).includes(name)) {
      throw configErr(
        `routing-table.yaml: domínio '${name}' fora do vocabulário (${DOMAINS.join(", ")})`,
        "domínio novo entra primeiro em tropeks/spock:docs/diretoria/",
      );
    }
    if (!body || typeof body !== "object" || Array.isArray(body)) {
      throw configErr(
        `routing-table.yaml: domains.${name} não é um mapa`,
        "use paths/keywords/dockerfile/other como listas",
      );
    }
    const b = body as Record<string, unknown>;
    const t = { paths: [], keywords: [], dockerfile: [], other: [] } as DomainTriggers;
    for (const k of DOMAIN_TRIGGER_KEYS) {
      const v = b[k];
      if (v === undefined) continue;
      if (!Array.isArray(v) || !v.every((x) => typeof x === "string" && x.length > 0)) {
        throw configErr(
          `routing-table.yaml: domains.${name}.${k} não é lista de strings`,
          "rode `maestro doctor`",
        );
      }
      t[k] = v as string[];
    }
    if (t.paths.length + t.keywords.length === 0) {
      throw configErr(
        `routing-table.yaml: domains.${name} sem paths nem keywords`,
        "um domínio sem gatilho nunca seria tocado — declare os gatilhos",
      );
    }
    out[name as Domain] = t;
  }
  return out;
}

/** minúsculas, sem acento: o casamento de palavra não depende de grafia. */
function foldText(s: string): string {
  return s.normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase();
}

function escapeRe(s: string): string {
  return s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

/** glob → RegExp ancorada: `**\/` = zero ou mais diretórios, `*` = sem `/`. */
function globToRegExp(glob: string): RegExp {
  let re = "";
  let i = 0;
  while (i < glob.length) {
    if (glob.startsWith("**/", i)) {
      re += "(?:.*/)?";
      i += 3;
    } else if (glob.startsWith("/**", i) && i + 3 === glob.length) {
      re += "(?:/.*)?";
      i += 3;
    } else if (glob.startsWith("**", i)) {
      re += ".*";
      i += 2;
    } else {
      const c = glob[i]!;
      re += c === "*" ? "[^/]*" : c === "?" ? "[^/]" : escapeRe(c);
      i += 1;
    }
  }
  return new RegExp(`^${re}$`, "i");
}

function globMatches(glob: string, target: string): boolean {
  const t = target.replace(/^(\.\/)+/, "").replace(/\/+$/, "");
  if (t.length === 0) return false;
  if (!glob.includes("/")) {
    const base = t.slice(t.lastIndexOf("/") + 1);
    return globToRegExp(glob).test(base);
  }
  return globToRegExp(glob).test(t);
}

/** Domínios tocados pelo plano, cada um com os gatilhos que casaram. */
function classifyPlan(
  domains: DomainTriggerMap,
  text: string,
  targets: string[],
): Map<Domain, string[]> {
  const raw = `${text} ${targets.join(" ")}`;
  const folded = foldText(raw);
  const dockerCtx =
    folded.includes("dockerfile") ||
    targets.some((t) => /(^|\/)dockerfile[^/]*$|\.dockerfile$/i.test(t));
  const hit = new Map<Domain, string[]>();
  for (const d of DOMAINS) {
    const t = domains[d];
    if (!t) continue;
    const why: string[] = [];
    for (const g of t.paths) {
      if (targets.some((x) => globMatches(g, x))) why.push(`path ${g}`);
    }
    for (const k of t.keywords) {
      const re = new RegExp(`(^|[^a-z0-9])${escapeRe(foldText(k))}`);
      if (re.test(folded)) why.push(`keyword ${k}`);
    }
    if (dockerCtx) {
      for (const k of t.dockerfile) {
        const hitK = /^[A-Z_]+$/.test(k)
          ? new RegExp(`(^|[^A-Za-z0-9_])${escapeRe(k)}([^A-Za-z0-9_]|$)`).test(raw)
          : folded.includes(foldText(k));
        if (hitK) why.push(`dockerfile ${k}`);
      }
    }
    for (const k of t.other) {
      if (folded.includes(foldText(k))) why.push(`other ${k}`);
    }
    if (why.length > 0) hit.set(d, why);
  }
  return hit;
}

function sha256Hex(s: string): string {
  const h = new Bun.CryptoHasher("sha256");
  h.update(s);
  return h.digest("hex");
}

/**
 * Carimbo do INTENT do projeto, no MESMO formato de lib/core-intent.sh:
 * `version:` no carimbo e hash = 8 hex do sha256 do corpo (tudo depois da
 * primeira linha `-->`, a partir da linha 2 — o `sed '1,/^-->$/d'` de lá).
 */
function projectIntent(): { version: number; hash: string } | null {
  const dir = process.env.CLAUDE_PROJECT_DIR ?? process.cwd();
  const f = join(dir, ".maestro", "INTENT.md");
  if (!existsSync(f)) return null;
  let raw: string;
  try {
    raw = readFileSync(f, "utf8");
  } catch {
    return null;
  }
  const lines = raw.split("\n");
  let version: number | null = null;
  let stamped: string | null = null;
  for (let i = 0; i < Math.min(lines.length, 20); i++) {
    const l = lines[i]!;
    if (l === "-->") break;
    const m = /^version: ([0-9]{1,9})$/.exec(l);
    if (m && version === null) version = Number(m[1]);
    const h = /^hash: ([0-9a-f]{8})$/.exec(l);
    if (h && stamped === null) stamped = h[1]!;
  }
  if (version === null || version < 1) return null;
  let off = lines[0]!.length + 1;
  let body = "";
  for (let i = 1; i < lines.length; i++) {
    off += lines[i]!.length + 1;
    if (lines[i] === "-->") {
      body = raw.slice(Math.min(off, raw.length));
      break;
    }
  }
  const hash = sha256Hex(body).slice(0, 8);
  // Corpo editado desde o carimbo: a versão não corresponde mais ao texto, e o
  // pedido citaria uma direção que não é a do disco (maestro intent --bump).
  if (stamped !== hash) return null;
  return { version, hash };
}

interface DomainRequest {
  request_id: string;
  project: string;
  order_ref: string | null;
  intent: { version: number; hash: string };
  domain: Domain;
  plan: { ref: string; hash: string };
  targets: string[];
  effects: string[];
  rollback_ref: string;
}

/**
 * Bloco `domain` do record — `status`, `scope`, `cleared` e `cleared_until`
 * PRIMEIRO: o gate os lê por regex numa janela de 4 KiB. `cleared` = domínios
 * com aprovação `approved` espelhada da Ponte (via=ponte) e não vencida;
 * `cleared_until` = a menor validade delas, em epoch (0 = nenhuma). Mesma conta
 * de hooks/lib/domain-record.sh (DOMAIN_RECOMPUTE_JQ).
 */
interface DomainBlock {
  status: string;
  scope?: string;
  cleared: string;
  cleared_until: number;
  requests: DomainRequest[];
  decisions?: Array<Record<string, unknown>>;
}

function splitList(raw: string, sep: RegExp): string[] {
  return raw
    .split(sep)
    .map((s) => s.trim())
    .filter((s) => s.length > 0);
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
  // E14/S-1401 — orçamento declarado (Contract 2 da pesquisa RAD): caps
  // INTEIROS, AND-of-caps, warn-only. steps/minutes são medidos pelo gate;
  // cents é DECLARATIVO (nenhum hook enxerga custo real) — o retro correlaciona.
  budget?: { steps?: number; minutes?: number; cents?: number };
  // E17/S-1701 — profundidade/perfil/brief regido (compilador de intenção).
  depth?: string;
  profile?: string;
  brief?: string;
  // E17/S-1708 — dissenso é trilha, sobrevive ao re-decide da mesma sessão;
  // schema autoritativo em `bin/maestro record_schema_ok`.
  flags?: Array<Record<string, string>>;
  // ordem 024 fatia 1 (H6) — eixo arquivo: frentes paralelas de mode=multi,
  // cada uma sua lista de prefixos de caminho. Schema autoritativo em
  // `lib/core-record.sh record_schema_ok`.
  fronts?: string[][];
  // ordem 024 fatia 1 (H6) — eixo recurso: marca esta frente como MEDIDORA
  // (roda suíte/benchmark). Só existe `true` — ausência é "não mede".
  measures?: true;
  // E28 — gate domain: pedidos ao diretor do domínio e as decisões espelhadas
  // da Ponte. Schema autoritativo em `lib/core-record.sh record_schema_ok`.
  domain?: DomainBlock;
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

// ---------------------------------------------------- ordem 024 fatia 1 (H6)

/** Normaliza um prefixo de caminho para comparação de diretório (trailing `/`). */
function normFrontPath(p: string): string {
  const t = p.trim();
  return t.endsWith("/") ? t : `${t}/`;
}

/** Duas frentes sobrepõem se um prefixo é igual ao outro, ou um contém o outro. */
function pathsOverlap(a: string, b: string): boolean {
  const na = normFrontPath(a);
  const nb = normFrontPath(b);
  return na === nb || na.startsWith(nb) || nb.startsWith(na);
}

/**
 * Eixo RECURSO (H6): existe outra sessão viva (record com `expires_at` no
 * futuro) além de `currentSession`? Degrada em SILÊNCIO — sem diretório de
 * sessões, JSON corrompido ou arquivo ilegível nunca lança: a guarda CALA e
 * o `decide` segue (Prioridades §1, "nunca bloquear trabalho por estar
 * quebrado"). Nenhuma dependência de `jq`: TS já lê JSON nativo.
 */
function otherLiveSessionExists(currentSession: string): boolean {
  let files: string[];
  try {
    files = readdirSync(sessionsDir()).filter((f) => f.endsWith(".json"));
  } catch {
    return false;
  }
  const now = Date.now();
  for (const f of files) {
    if (f === `${currentSession}.json`) continue;
    try {
      const rec = JSON.parse(
        readFileSync(join(sessionsDir(), f), "utf8"),
      ) as { expires_at?: unknown };
      if (typeof rec.expires_at !== "string") continue;
      const exp = Date.parse(rec.expires_at);
      if (Number.isFinite(exp) && exp > now) return true;
    } catch {
      continue;
    }
  }
  return false;
}

// ---------------------------------------------------------------- comando: decide

/**
 * E28 — `gate: domain`. Devolve null quando o workflow não tem esse gate
 * (o record não ganha o campo). Com o gate: exige o plano (brief com approach
 * real — `pendente` não é plano), classifica por regra e, se tocar domínio,
 * exige o contrato mínimo (targets, effects, rollback, INTENT carimbado):
 * nenhum placeholder vale como evidência, então campo faltando é recusa.
 */
function decideDomain(
  args: Args,
  table: RoutingTable,
  workflow: string,
  session: string,
  brief: string | undefined,
  prev: DecisionRecord | null,
): { block: DomainBlock; text: string } | null {
  const targetsRaw = requireValue(args, "targets");
  const effectsRaw = requireValue(args, "effects");
  const rollbackRaw = requireValue(args, "rollback");
  const orderRaw = requireValue(args, "order");
  if (table.gates[workflow] !== "domain") {
    if (targetsRaw ?? effectsRaw ?? rollbackRaw ?? orderRaw) {
      throw invalid(
        `--targets/--effects/--rollback/--order só se aplicam a workflow com gate domain ('${workflow}' não tem)`,
        "remova essas opções ou use um workflow com gate domain (feature, refactor)",
      );
    }
    // Trocar de workflow não apaga um pedido que não liberou: a suspensão
    // sumiria junto com o bloco `domain`.
    const pst = prev?.domain?.status;
    const vivo = prev?.expires_at ? Date.parse(prev.expires_at) > Date.now() : false;
    if (vivo && typeof pst === "string" && pst !== "clear" && pst !== "approved") {
      throw invalid(
        `a sessão tem pedido de domínio ${pst}: trocar para '${workflow}' (sem gate domain) apagaria a suspensão`,
        "espere a decisão pela Ponte, ou decida de novo com gate domain e um plano novo",
      );
    }
    return null;
  }
  if (brief === undefined) {
    throw invalid(
      `workflow '${workflow}' tem gate domain e exige --brief`,
      'o brief é o plano que o gate classifica: --brief "essencia: ...; impacto: ...; approach: <o plano>"',
    );
  }
  const approach = /approach:\s*(.*?)\s*(;|$|essencia:|impacto:)/.exec(brief)?.[1] ?? "";
  if (approach === "" || /^pendente\b/i.test(approach)) {
    throw invalid(
      `workflow '${workflow}' tem gate domain: approach pendente não é plano`,
      "planeje primeiro e decida com o approach real; plano mudou → decida de novo (o decide reclassifica)",
    );
  }

  const targets = targetsRaw === null ? [] : splitList(targetsRaw, /[\s,]+/);
  if (targets.length > TARGETS_MAX) {
    throw invalid(`--targets aceita até ${TARGETS_MAX} caminhos`, "agrupe por diretório (ex.: deploy/)");
  }
  for (const t of targets) {
    if (!RE_TARGET.test(t) || t.split("/").includes("..")) {
      throw invalid(
        `--targets: caminho inválido '${t}'`,
        "caminho relativo ao projeto, sem espaço nem '..', em [A-Za-z0-9._@+/-]",
      );
    }
  }
  const scope = targets.join(" ");
  if (scope.length > SCOPE_MAX) {
    throw invalid(`--targets excede ${SCOPE_MAX} caracteres no total`, "agrupe por diretório (ex.: deploy/)");
  }
  const effects = effectsRaw === null ? [] : splitList(effectsRaw.replace(/[\u0000-\u001f\u007f]/g, " "), /;/);
  if (effects.length > EFFECTS_MAX || effects.some((e) => e.length > EFFECT_MAX)) {
    throw invalid(
      `--effects: até ${EFFECTS_MAX} efeitos separados por ';', cada um com até ${EFFECT_MAX} chars`,
      'use --effects "abre a porta 443 no túnel; reinicia o serviço x"',
    );
  }
  const rollbackTrim = rollbackRaw === null ? "" : rollbackRaw.trim();
  const rollback = rollbackTrim === "" ? "" : resolveRollbackRef(rollbackTrim);
  let orderRef: string | null = null;
  if (orderRaw !== null) {
    if (!RE_ORDER_REF.test(orderRaw)) {
      throw invalid("--order inválido", "use a referência da ordem, ex.: --order 110");
    }
    orderRef = orderRaw;
  }

  // O texto classificado é o MESMO que o roteador do ponte-daemon reclassifica (brief do
  // record, effects, rollback_ref, com os targets como caminhos): o `--reason` não entra no
  // pedido nem no plan.hash, e classificar com ele abria pedido que a Ponte recusa por
  // divergência de domínio (dominio_diverge_do_roteamento).
  const text = [brief, effects.join(" "), rollback].join(" ");
  const hits = classifyPlan(table.domains ?? {}, text, targets);
  if (hits.size === 0) {
    return {
      block: { status: "clear", cleared: "", cleared_until: 0, requests: [] },
      text:
        "gate domain: o plano não toca domínio declarado — segue sem pedido.\n" +
        "  caminho de domínio (domains.*.paths) fora de um plano aprovado continua suspenso no gate.\n",
    };
  }

  const project = currentProject();
  const intent = projectIntent();
  const missing: string[] = [];
  if (targets.length === 0) missing.push("--targets");
  if (effects.length === 0) missing.push("--effects");
  if (rollback === "") missing.push("--rollback");
  if (project === null) missing.push("projeto (nome do diretório)");
  if (intent === null) missing.push("INTENT carimbado e sem edição desde o carimbo (maestro intent --check / --bump)");
  const touched = [...hits.keys()];
  if (missing.length > 0) {
    throw invalid(
      `gate domain: o plano toca ${touched.join(", ")} e o pedido ao diretor exige: ${missing.join(", ")}`,
      "nenhum placeholder vale como evidência — informe os campos reais e decida de novo",
    );
  }

  const planHash = sha256Hex(
    JSON.stringify({ brief, targets, effects, rollback_ref: rollback, order_ref: orderRef }),
  );
  const requests: DomainRequest[] = touched.map((d) => ({
    request_id: `dreq-${sha256Hex(`${project}|${session}|${d}|${planHash}`).slice(0, 16)}`,
    project: project!,
    order_ref: orderRef,
    intent: intent!,
    domain: d,
    // CONTRATO v2 aceita três formas de plan.ref; o Maestro emite só a do brief da sessão
    // (as outras são `<caminho>#<ancora>` no branch da ordem e a da ordem por comando da Ponte).
    plan: { ref: `maestro:sessions/${session}#brief`, hash: planHash },
    targets,
    effects,
    rollback_ref: rollback,
  }));

  // Re-decide do MESMO plano preserva as decisões já espelhadas (mesmo
  // request_id) que não venceram; plano novo = pedido novo, e decisão velha
  // não vale para ele. Vencida, a decisão não cobre execução nova (CONTRATO).
  // INTENT novo suspende as decisões do projeto (CONTRATO v2): decisão dada sob
  // outro carimbo não é preservada, e o pedido volta a esperar o diretor.
  const ids = new Set(requests.map((r) => r.request_id));
  const nowS = Math.floor(Date.now() / 1000);
  const kept = (prev?.domain?.decisions ?? []).filter((x) => {
    const xi = x?.intent as { version?: unknown; hash?: unknown } | undefined;
    return (
      typeof x?.request_id === "string" &&
      ids.has(x.request_id as string) &&
      typeof x.until_epoch === "number" &&
      x.until_epoch > nowS &&
      xi?.version === intent!.version &&
      xi?.hash === intent!.hash
    );
  });
  const block = domainBlock(requests, kept, scope, nowS);

  let out =
    `gate domain: o plano toca ${touched.join(", ")} — pedido ao diretor do domínio registrado (status: ${block.status}).\n` +
    `  edição em ${scope} fica suspensa até a decisão; timeout não aprova.\n`;
  for (const r of requests) {
    out += `  ${r.domain}: ${hits.get(r.domain)!.join(", ")}\n`;
  }
  // v1.27 (API_SPEC §5.4.2 da Enterprise): o pedido entra no campo `domain_requests` do
  // director.ask. As linhas `pedido:` seguem na pergunta para a Ponte anterior à v1.27,
  // que lê o pedido da pergunta e descarta em silêncio o campo que não conhece.
  out +=
    "  com a Ponte: director.ask uma vez com domain_requests = a lista da linha `domain_requests:` abaixo\n" +
    "    (titulo curto; na pergunta, as linhas `pedido:`), depois director.wait em laço. A resposta do\n" +
    "    director.wait é registrada no record sozinha (hook do Maestro) e libera os alvos aprovados; num run\n" +
    "    que espera por director.wait_for, ao retomar chame director.wait uma vez com o decision_id.\n" +
    "  sem a Ponte: leve o pedido ao humano responsável; registro manual não libera, nada segue por silêncio.\n";
  for (const r of requests) out += `pedido: ${JSON.stringify(r)}\n`;
  out += `domain_requests: ${JSON.stringify(requests)}\n`;
  return { block, text: out };
}

/**
 * Revogada (CONTRATO v2): `revoked_at` não nulo. O `revoked` antigo só é lido por
 * compatibilidade (`true`; texto não vazio nos records gravados antes da v2).
 * A mesma conta de DOMAIN_REVOKED_JQ (hooks/lib/domain-record.sh).
 */
function isRevoked(d: Record<string, unknown>): boolean {
  const v = d.revoked;
  return (d.revoked_at ?? null) !== null || v === true || (typeof v === "string" && v.length > 0);
}

/**
 * `--rollback` (CONTRATO v2, `rollback_ref`): `<caminho>#<ancora>` que resolve — o
 * arquivo existe dentro do projeto e a âncora é um título Markdown dele, uma vez só
 * (ambíguo não resolve, como no daemon). Texto livre ("git revert") não é procedimento que o
 * mecanismo resolva: é recusa, como placeholder. O daemon confere de novo no
 * branch da ordem, então o arquivo precisa estar versionado.
 */
function resolveRollbackRef(raw: string): string {
  const hint =
    'aponte o procedimento de reversão versionado no projeto, ex.: --rollback "docs/planos/160.md#rollback"';
  const m = raw.length > ROLLBACK_REF_MAX ? null : RE_ROLLBACK_REF.exec(raw);
  const segs = m === null ? [] : m[1]!.split("/");
  if (
    m === null ||
    segs.some((seg) => seg === "" || seg === "." || seg === ".." || seg === ".git" || seg.toLowerCase().startsWith(".env"))
  ) {
    throw invalid(
      `--rollback não é caminho relativo com âncora (caminho#ancora, ASCII, sem '..', .git ou .env, até ${ROLLBACK_REF_MAX} chars)`,
      hint,
    );
  }
  if (RE_PLACEHOLDER_INTEIRO.test(raw) || RE_PLACEHOLDER_MARCADOR.test(raw)) {
    throw invalid("--rollback parece placeholder ('...', TODO, TBD, FIXME): a Ponte recusa", hint);
  }
  const path = m[1]!;
  const anchor = m[2]!;
  const dir = process.env.CLAUDE_PROJECT_DIR ?? process.cwd();
  let real: string;
  let root: string;
  try {
    root = realpathSync(dir);
    real = realpathSync(join(root, path));
  } catch {
    throw invalid(`--rollback: '${path}' não existe no projeto`, hint);
  }
  if (!real.startsWith(root + sep)) {
    throw invalid(`--rollback: '${path}' sai do projeto`, hint);
  }
  let size: number;
  try {
    const st = statSync(real);
    if (!st.isFile()) throw new Error("não é arquivo");
    size = st.size;
  } catch {
    throw invalid(`--rollback: '${path}' não é arquivo`, hint);
  }
  if (size > ROLLBACK_FILE_MAX) {
    throw invalid(`--rollback: '${path}' grande demais para conferir a âncora`, hint);
  }
  let body = "";
  try {
    body = readFileSync(real, "utf8");
  } catch {
    throw invalid(`--rollback: não consegui ler '${path}'`, hint);
  }
  const vezes = markdownAnchors(body).get(anchor) ?? 0;
  if (vezes !== 1) {
    throw invalid(
      vezes === 0
        ? `--rollback: a âncora #${anchor} não é título Markdown de '${path}'`
        : `--rollback: a âncora #${anchor} aparece ${vezes} vezes em '${path}' (ambígua, a Ponte recusa)`,
      hint,
    );
  }
  return raw;
}

/**
 * Âncoras dos títulos Markdown (`# Título` → `titulo`) e quantas vezes cada uma aparece, na conta
 * do daemon (`secaoDaAncora` e `slugDoTitulo`, ponte-daemon domain/diretoria.ts): título é linha
 * `#`..`######` no início; slug sem acento, minúsculas, só `[a-z0-9 _-]`, espaço vira '-'.
 */
function markdownAnchors(body: string): Map<string, number> {
  const out = new Map<string, number>();
  for (const line of body.split("\n")) {
    const h = /^#{1,6}\s+(.+?)\s*#*\s*$/.exec(line);
    if (h === null) continue;
    const slug = h[1]!
      .normalize("NFD")
      .replace(/[\u0300-\u036f]/g, "")
      .toLowerCase()
      .trim()
      .replace(/[^a-z0-9 _-]/g, "")
      .replace(/ /g, "-");
    if (slug !== "") out.set(slug, (out.get(slug) ?? 0) + 1);
  }
  return out;
}

/**
 * Bloco recalculado — a MESMA conta de hooks/lib/domain-record.sh: o pior pedido
 * vence; aprovação que não veio da Ponte (`via` ≠ ponte) conta como pendente;
 * decisão revogada também; `cleared` só com `approved` via Ponte, não revogado e
 * não vencido.
 */
function domainBlock(
  requests: DomainRequest[],
  decisions: Array<Record<string, unknown>>,
  scope: string,
  nowS: number,
): DomainBlock {
  const order = ["denied", "revise", "escalate", "needs_evidence", "pending", "approved_with_conditions", "approved"];
  let worst = order.length - 1;
  const cleared = new Set<string>();
  let until = 0;
  for (const r of requests) {
    const d = [...decisions].reverse().find((x) => x.request_id === r.request_id);
    let resp = typeof d?.response === "string" ? d.response : "pending";
    if (resp.startsWith("approved") && d?.via !== "ponte") resp = "pending";
    // Revogada (`revoked_at`, `domain.revoke`): deixa de cobrir na hora; o pedido volta a esperar.
    if (d !== undefined && isRevoked(d)) resp = "pending";
    const i = order.indexOf(resp);
    worst = Math.min(worst, i < 0 ? order.indexOf("pending") : i);
    const ue = typeof d?.until_epoch === "number" ? d.until_epoch : 0;
    if (resp === "approved" && ue > nowS) {
      cleared.add(r.domain);
      until = until === 0 ? ue : Math.min(until, ue);
    }
  }
  return {
    status: requests.length === 0 ? "clear" : order[worst]!,
    scope,
    cleared: [...cleared].sort().join(" "),
    cleared_until: until,
    requests,
    ...(decisions.length ? { decisions } : {}),
  };
}

function cmdDecide(args: Args): number {
  rejectUnknown(args, [
    "session", "workflow", "mode", "agents", "reason",
    "max-steps", "max-min", "max-cents", // E14: orçamento declarado
    "depth", "profile", "brief", // E17/S-1701: compilador de intenção
    "fronts", "measures", // ordem 024 fatia 1 — H6, eixo arquivo + eixo recurso
    "targets", "effects", "rollback", "order", // E28 — pedido ao diretor do domínio
  ]);

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

  // ---- ordem 024 fatia 1 (H6) — eixo ARQUIVO: --fronts só faz sentido em
  // mode=multi (é a decisão que declara "estas N frentes correm juntas").
  // Frentes separadas por ';', caminhos de cada frente separados por espaço.
  // Sobreposição de PREFIXO de diretório entre DUAS frentes é recusada aqui —
  // hard-fail de validação (não é falha de guarda de ambiente): duas frentes
  // que disputam o mesmo diretório se destroem na CPU mesmo sem tocar o
  // mesmo arquivo, e é exatamente esse buraco que o eixo arquivo fecha.
  let fronts: string[][] | undefined;
  const frontsRaw = requireValue(args, "fronts");
  if (frontsRaw !== null) {
    if (mode !== "multi") {
      throw invalid(
        "--fronts só se aplica a --mode multi",
        "use --mode multi ou remova --fronts",
      );
    }
    const rawFronts = frontsRaw
      .split(";")
      .map((s) => s.trim())
      .filter((s) => s.length > 0);
    if (rawFronts.length < 2) {
      throw invalid(
        "--fronts exige pelo menos 2 frentes separadas por ';'",
        'use --fronts "a/ b/;c/" (frentes separadas por ; caminhos por espaço)',
      );
    }
    fronts = rawFronts.map((f) =>
      f
        .split(/\s+/)
        .map((p) => p.trim())
        .filter((p) => p.length > 0),
    );
    const emptyIdx = fronts.findIndex((f) => f.length === 0);
    if (emptyIdx >= 0) {
      throw invalid(
        `--fronts: frente ${emptyIdx + 1} não tem nenhum caminho`,
        'cada frente precisa de ao menos um caminho: "a/ b/;c/"',
      );
    }
    for (let i = 0; i < fronts.length; i++) {
      for (let j = i + 1; j < fronts.length; j++) {
        for (const pa of fronts[i]!) {
          for (const pb of fronts[j]!) {
            if (pathsOverlap(pa, pb)) {
              throw invalid(
                `--fronts: '${pa}' (frente ${i + 1}) sobrepõe '${pb}' (frente ${j + 1})`,
                "frentes paralelas exigem caminhos DISJUNTOS — duas frentes que " +
                  "tocam o mesmo diretório se destroem na CPU mesmo sem tocar o " +
                  "mesmo arquivo; separe os caminhos ou junte tudo numa frente só",
              );
            }
          }
        }
      }
    }
  }

  // ---- ordem 024 fatia 1 (H6) — eixo RECURSO: --measures marca esta frente
  // como MEDIDORA (roda suíte/benchmark). Regra: "frentes que DECIDEM
  // paralelizam; frentes que MEDEM correm sozinhas" — mas o INTENT Prioridades
  // §1 proíbe bloquear trabalho, então isto é SÓ aviso, nunca recusa. A guarda
  // (otherLiveSessionExists) já degrada em silêncio sozinha; nada aqui pode
  // derrubar o decide.
  const measures = args.flags.has("measures");
  if (measures && otherLiveSessionExists(session)) {
    warn(
      "--measures: já existe outra sessão viva (não expirada) em " +
        "~/.maestro/sessions — frentes que MEDEM correm sozinhas; considere " +
        "esperar a outra sessão encerrar ou tirar --measures desta frente",
    );
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

  // ---- E14: orçamento declarado (inteiros; float em custo é proibido — CLAUDE.md)
  const budget: { steps?: number; minutes?: number; cents?: number } = {};
  for (const [flag, key, max] of [
    ["max-steps", "steps", 500],
    ["max-min", "minutes", 1440],
    ["max-cents", "cents", 100000],
  ] as const) {
    const raw = requireValue(args, flag);
    if (raw === null) continue;
    const n = Number(raw);
    if (!Number.isInteger(n) || n < 1 || n > max) {
      throw invalid(
        `--${flag} exige inteiro entre 1 e ${max}`,
        "o orçamento é declarado em inteiros: passos, minutos, centavos",
      );
    }
    budget[key] = n;
  }
  const hasBudget = Object.keys(budget).length > 0;

  // ---- E17/S-1701: --depth (heurística de profundidade)
  let depth: string | undefined;
  const depthRaw = requireValue(args, "depth");
  if (depthRaw !== null) {
    if (!(DEPTH_VALUES as readonly string[]).includes(depthRaw)) {
      throw invalid(
        `--depth '${depthRaw}' inválido`,
        `escolha um de: ${DEPTH_VALUES.join(", ")}`,
      );
    }
    depth = depthRaw;
  }
  // ausência de --depth NÃO grava campo: standard é o default semântico, não
  // um valor gravado — só valores explícitos entram no record.

  // ---- E17/S-1701: --profile (obrigatório SSE depth=day-zero)
  let profile: string | undefined;
  const profileRaw = requireValue(args, "profile");
  if (profileRaw !== null) {
    if (!(PROFILE_VALUES as readonly string[]).includes(profileRaw)) {
      throw invalid(
        `--profile '${profileRaw}' inválido`,
        `escolha um de: ${PROFILE_VALUES.join(", ")}`,
      );
    }
    profile = profileRaw;
  }
  if (depth === "day-zero" && !profile) {
    throw invalid(
      "--depth day-zero exige --profile",
      `escolha um de: ${PROFILE_VALUES.join(", ")}`,
    );
  }
  if (profile !== undefined && depth !== "day-zero") {
    throw invalid(
      "--profile só se aplica a --depth day-zero",
      "remova --profile ou use --depth day-zero",
    );
  }

  // ---- E17/S-1701: --brief (essencia:/impacto:/approach: — plano regido)
  // Único texto livre extra além de --reason; mesma normalização (sem
  // controles/quebras de linha) e mesmo espírito de cap — aqui em 3
  // marcadores fixos, cada um ≤200 chars, total ≤700. `approach: pendente` é
  // aceito: o approach nasce pendente no decide e é atualizado depois (verbo
  // de mutação do record, fora deste comando).
  let brief: string | undefined;
  const briefRaw = requireValue(args, "brief");
  if (briefRaw !== null) {
    const clean = briefRaw
      .replace(/[\u0000-\u001f\u007f]/g, " ")
      .replace(/\s+/g, " ")
      .trim();
    if (clean.length > BRIEF_TOTAL_MAX) {
      throw invalid(
        `--brief excede ${BRIEF_TOTAL_MAX} caracteres no total (tinha ${clean.length})`,
        `resuma o brief para caber em ${BRIEF_TOTAL_MAX} chars: "essencia: ...; impacto: ...; approach: ..."`,
      );
    }
    const found = BRIEF_MARKERS.map((marker) => ({
      marker,
      idx: clean.indexOf(marker),
    }));
    const missing = found.filter((f) => f.idx === -1).map((f) => f.marker);
    if (missing.length > 0) {
      throw invalid(
        `--brief sem o(s) marcador(es): ${missing.join(", ")}`,
        `use --brief "essencia: ...; impacto: ...; approach: ..." com os 3 marcadores`,
      );
    }
    const ordered = found.slice().sort((a, b) => a.idx - b.idx);
    for (let i = 0; i < ordered.length; i++) {
      const cur = ordered[i]!;
      const start = cur.idx + cur.marker.length;
      const end = i + 1 < ordered.length ? ordered[i + 1]!.idx : clean.length;
      const content = clean.slice(start, end).replace(/^[\s;]+|[\s;]+$/g, "");
      if (content.length > BRIEF_MARKER_MAX) {
        throw invalid(
          `--brief: marcador '${cur.marker}' excede ${BRIEF_MARKER_MAX} chars (tinha ${content.length})`,
          `resuma o conteúdo de '${cur.marker}' para caber em ${BRIEF_MARKER_MAX} chars`,
        );
      }
    }
    brief = clean;
  }

  // ---- E17/S-1701: enforcement plan-gated — workflow com gate:plan exige brief
  if (table.gates[workflow] === "plan" && brief === undefined) {
    throw invalid(
      `workflow '${workflow}' tem gate plan e exige --brief`,
      'workflow com gate plan exige --brief "essencia: ...; impacto: ...; approach: ..." ' +
        "(approach: pendente é aceito; atualize depois com maestro conduct --approach)",
    );
  }

  // ---- E28: gate domain — o plano segue sem humano; se tocar domínio, o
  // pedido ao diretor do domínio nasce aqui, com o contrato mínimo.
  const prevForDomain = readRecord(session);
  const domainOut = decideDomain(args, table, workflow, session, brief, prevForDomain);

  // ---- gravação
  ensureDirs();

  const now = new Date();
  const ts = isoLocal(now);
  const expires = isoLocal(new Date(now.getTime() + ttlSeconds() * 1000));
  const wtree = computeWtree(); // E7/S-701: ~200ms; aqui no CLI, jamais no gate

  // E17/S-1708: o record é idempotente por sessão (write+rename reescreve do
  // zero) — sem isso, um re-decide na mesma sessão apagaria `flags[]` gravado
  // por `maestro conduct`. A trilha de dissenso é da SESSÃO, não do workflow
  // decidido: sobrevive mesmo quando este decide muda workflow/mode. O decide
  // só PRESERVA; validar o conteúdo das flags é assunto do doctor.
  const prev = prevForDomain;

  const record: DecisionRecord = {
    session_id: session,
    ts,
    expires_at: expires,
    workflow,
    mode,
    // E28: logo depois de `mode`, para caber na janela fixa que o gate lê.
    ...(domainOut ? { domain: domainOut.block } : {}),
    ...(agents ? { agents } : {}),
    ...(reason ? { reason } : {}),
    ...(wtree ? { wtree } : {}),
    ...(hasBudget ? { budget } : {}),
    ...(depth ? { depth } : {}),
    ...(profile ? { profile } : {}),
    ...(brief ? { brief } : {}),
    ...(prev?.flags && Array.isArray(prev.flags) && prev.flags.length
      ? { flags: prev.flags }
      : {}),
    ...(fronts ? { fronts } : {}),
    ...(measures ? { measures: true } : {}),
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

  // E23a/S-2301 — primeira fase do funil de delegação. `decision` já diz que a
  // aposta foi feita; `delegation phase=planned` é o que o `maestro delegation`
  // (e o gate do `outcome accepted`) compara com o `started` que o hook
  // pre-agent.sh emite no disparo real. Sem agents não há delegação a provar.
  if (agents) {
    appendLog({
      ts,
      event: "delegation",
      session_id: session,
      phase: "planned",
      agents,
    });
  }

  const alvo = agents ? ` agentes=${agents.join(",")}` : "";
  process.stdout.write(
    `${existed ? "decisão atualizada" : "decisão registrada"}: ` +
      `sessão=${session} workflow=${workflow} mode=${mode}${alvo}\n` +
      `válida até ${expires} (TTL ${humanDuration(ttlSeconds())})\n`,
  );
  if (domainOut) process.stdout.write(domainOut.text);
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

  // E7/S-705: idade do envelope de capacidades (maestro.capabilities.v1).
  // O envelope é escrito pelo doctor; aqui só se LÊ — e idade é reportada em
  // segundos inteiros via humanDuration (sem float, regra do projeto).
  try {
    const cap = join(maestroHome(), "capabilities.json");
    if (!existsSync(cap)) {
      out.push("  doctor      : nunca rodou (sem capabilities.json — rode `maestro doctor`)");
    } else {
      const o = JSON.parse(readFileSync(cap, "utf8")) as {
        generated_at?: string;
        generated_epoch?: number;
      };
      const age =
        typeof o.generated_epoch === "number" && o.generated_epoch > 0
          ? Math.trunc(Date.now() / 1000) - o.generated_epoch
          : -1;
      out.push(
        `  doctor      : ${o.generated_at ?? "?"}` +
          (age >= 0 ? ` (há ${humanDuration(age)})` : "") +
          (age >= 86400 ? " — envelope velho, rode `maestro doctor`" : ""),
      );
    }
  } catch {
    out.push("  doctor      : capabilities.json ilegível (rode `maestro doctor`)");
  }

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
      if (rec.budget) {
        const b = rec.budget;
        const parts: string[] = [];
        if (b.steps) parts.push(`${b.steps} passo(s)`);
        if (b.minutes) parts.push(`${b.minutes}min`);
        if (b.cents) parts.push(`${b.cents} centavo(s) [declarativo]`);
        out.push(`  orçamento : ${parts.join(" · ")} (AND-of-caps, warn-only)`);
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

  const others = (["killswitch", "session_end", "conduct"] as const)
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
         [--depth standard|deep|day-zero] [--profile prototipo|piloto|produto]
                                                 profundidade do plano (E17); profile obrigatório em day-zero
         [--brief "essencia: ...; impacto: ...; approach: ..."]
                                                 brief regido; exigido com gate plan e gate domain
                                                 (no gate domain, approach real: pendente é recusa)
         [--targets a,b] [--effects "e1; e2"] [--rollback "caminho#ancora"] [--order <ref>]
                                                 gate domain (E28): alvos, efeitos e rollback do plano;
                                                 exigidos quando o plano toca domínio (pedido ao diretor)
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
