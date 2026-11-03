#!/usr/bin/env python3
"""auditoria.py — o portão `auditoria` (R5 do integrador): o PR não traz vulnerabilidade conhecida NOVA.

Audita os lockfiles do repo duas vezes, no HEAD e no primeiro pai (no PR o checkout é o merge de teste, e HEAD^1
é a base; no push da main, é a main de antes), com o banco de avisos de agora. Sai 1 se o HEAD tem um par
(pacote, aviso) que a base não tem; o que já estava na base é dívida e só aparece no relatório. Assim um aviso
publicado hoje contra uma dependência antiga não tranca todo PR do repo, e quem acrescenta ou sobe pacote
vulnerável é barrado.

Cobertura: pnpm-lock.yaml (`pnpm audit`), package-lock.json (`npm audit`), uv.lock e poetry.lock (versões
fixadas lidas do TOML, `pip-audit --no-deps`) e requirements*.txt (`pip-audit`). Sem lockfile nenhum, diz isso
e sai 0. Ferramenta que falha (rede, formato) sai 2: na dúvida, vermelho.

Uso: python3 auditoria.py [--base REF]      (fonte: tropeks/vulcan .github/actions/portoes/auditoria.py; fica em .github/actions/ para ser T3)
"""
from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
import tomllib

LOCKS_NODE = ("pnpm-lock.yaml", "package-lock.json")
LOCKS_PY = ("uv.lock", "poetry.lock")


def git(*args: str) -> str:
    return subprocess.run(["git", *args], capture_output=True, text=True, check=True).stdout


def lockfiles() -> list[str]:
    nomes = LOCKS_NODE + LOCKS_PY
    saida = []
    for c in git("ls-files", "-z").split("\0"):
        base = c.rsplit("/", 1)[-1]
        if "node_modules/" in c:
            continue
        if base in nomes or (base.startswith("requirements") and base.endswith(".txt")):
            saida.append(c)
    return sorted(saida)


def conteudo(ref: str | None, caminho: str) -> str | None:
    if ref is None:
        try:
            with open(caminho, encoding="utf-8") as f:
                return f.read()
        except FileNotFoundError:
            return None
    r = subprocess.run(["git", "show", f"{ref}:{caminho}"], capture_output=True, text=True)
    return r.stdout if r.returncode == 0 else None


class FalhaFerramenta(RuntimeError):
    pass


def roda(cmd: list[str], cwd: str, ok=(0, 1)) -> str:
    r = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True)
    if r.returncode not in ok:
        raise FalhaFerramenta(f"{' '.join(cmd[:3])} saiu {r.returncode}: {(r.stderr or r.stdout)[-400:]}")
    return r.stdout


# ───────────── Node ─────────────

def audita_node(ref: str | None, caminho: str) -> set[tuple[str, str, str]]:
    pasta = os.path.dirname(caminho)
    lock = conteudo(ref, caminho)
    pkg = conteudo(ref, os.path.join(pasta, "package.json"))
    if lock is None or pkg is None:
        return set()
    with tempfile.TemporaryDirectory() as tmp:
        for nome, txt in ((caminho.rsplit("/", 1)[-1], lock), ("package.json", pkg),
                          ("pnpm-workspace.yaml", conteudo(ref, os.path.join(pasta, "pnpm-workspace.yaml")))):
            if txt is not None:
                with open(os.path.join(tmp, nome), "w", encoding="utf-8") as f:
                    f.write(txt)
        if caminho.endswith("pnpm-lock.yaml"):
            dados = json.loads(roda(["pnpm", "audit", "--json"], tmp) or "{}")
            return {(a.get("module_name", "?"), str(a.get("github_advisory_id") or a.get("id")),
                     a.get("severity", "?")) for a in (dados.get("advisories") or {}).values()}
        dados = json.loads(roda(["npm", "audit", "--json", "--package-lock-only"], tmp) or "{}")
        achados = set()
        for nome, v in (dados.get("vulnerabilities") or {}).items():
            for via in v.get("via", []):
                if isinstance(via, dict):
                    achados.add((nome, str(via.get("url", "").rsplit("/", 1)[-1] or via.get("source")),
                                 via.get("severity", "?")))
        return achados


# ───────────── Python ─────────────

def fixados_do_lock(txt: str, caminho: str) -> list[str]:
    d = tomllib.loads(txt)
    linhas = []
    for p in d.get("package", []):
        fonte = p.get("source") or {}
        if caminho.endswith("uv.lock") and ("editable" in fonte or "virtual" in fonte or "directory" in fonte):
            continue  # o próprio projeto e os membros do workspace não estão no PyPI
        if "version" in p:
            linhas.append(f"{p['name']}=={p['version']}")
    return linhas


def audita_py(ref: str | None, caminho: str) -> set[tuple[str, str, str]]:
    txt = conteudo(ref, caminho)
    if txt is None:
        return set()
    with tempfile.TemporaryDirectory() as tmp:
        req = os.path.join(tmp, "requirements.txt")
        extra = []
        if caminho.endswith((".lock",)):
            linhas = fixados_do_lock(txt, caminho)
            if not linhas:
                return set()
            txt = "\n".join(linhas) + "\n"
            extra = ["--no-deps", "--disable-pip"]
        with open(req, "w", encoding="utf-8") as f:
            f.write(txt)
        saida = roda([sys.executable, "-m", "pip_audit", "-r", req, "--format", "json", "--progress-spinner", "off",
                      *extra], tmp)
        dados = json.loads(saida or "{}")
        deps = dados.get("dependencies", dados if isinstance(dados, list) else [])
        return {(d["name"], v["id"], "?") for d in deps for v in d.get("vulns", [])}


def audita(ref: str | None, caminho: str) -> set[tuple[str, str, str]]:
    nome = caminho.rsplit("/", 1)[-1]
    return audita_node(ref, caminho) if nome in LOCKS_NODE else audita_py(ref, caminho)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", default="HEAD^1", help="ref da base (padrão: primeiro pai)")
    a = ap.parse_args()
    locks = lockfiles()
    if not locks:
        print("auditoria: nenhum lockfile ou requirements*.txt no repo: nada a auditar")
        return 0
    base_ok = subprocess.run(["git", "rev-parse", "--verify", "-q", a.base], capture_output=True).returncode == 0
    novos_total = 0
    try:
        for c in locks:
            head = audita(None, c)
            base = audita(a.base, c) if base_ok else set()
            chave = lambda s: {(p, i) for p, i, _ in s}  # noqa: E731
            novos = sorted(x for x in head if (x[0], x[1]) not in chave(base))
            print(f"== {c}: {len(head)} aviso(s) no head, {len(base)} na base, {len(novos)} novo(s)")
            for p, i, sev in novos:
                print(f"   NOVO  {p}  {i}  ({sev})")
            for p, i, sev in sorted(x for x in head if x not in novos)[:40]:
                print(f"   dívida {p}  {i}  ({sev})")
            novos_total += len(novos)
    except (FalhaFerramenta, json.JSONDecodeError, tomllib.TOMLDecodeError) as e:
        print(f"auditoria: ferramenta falhou, sem veredito: {e}", file=sys.stderr)
        return 2
    if novos_total:
        print(f"auditoria: {novos_total} vulnerabilidade(s) nova(s) neste PR: suba ou troque o pacote")
        return 1
    print("auditoria: nenhuma vulnerabilidade nova")
    return 0


if __name__ == "__main__":
    if shutil.which("git") is None:
        sys.exit("auditoria: sem git")
    sys.exit(main())
