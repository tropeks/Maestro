#!/usr/bin/env python3.13
"""tests/eval/laya_engine.py — interface fina do motor de decisão tipada (ordem 034).

Único arquivo Python do spike. Expõe UMA função, `predict`, que recebe estado
(metadado ou o `prompt` de fixture de tests/eval/cases.yaml — nunca dado do
Vitali, nunca PHI) e perguntas tipadas (`choice`/`score`/`noul`, a forma que
`laya.Router.predict` espera — ver laya/agent.py:system_one instalado), e
devolve rótulo + confiança + o checkpoint que respondeu. Trocar o motor
(`laya` → `jev`, quando a ordem 028 rodar) é reescrever o CORPO desta função
mantendo a forma de retorno; laya-spike.sh não sabe o nome do pacote.

Sem efeito: só lê stdin, chama o motor, escreve stdout. Não grava em
~/.maestro/, não chama `maestro decide`, não fala com serviço nenhum (a única
rede é o download do checkpoint para ~/.cache/huggingface, no primeiro uso —
instalação, não runtime, mesma leitura da ordem 034 "Por que esta ordem existe").

Uso (o que laya-spike.sh chama):
    python3.13 laya_engine.py --predict < entrada.jsonl > saida.jsonl
        entrada, uma linha por registro:
            {"id": "...", "state": <dict|str>, "questions": {<qid>: <qdef>}}
        saida, uma linha por registro:
            {"id": "...", "answers": {<qid>: {"choice"|"score"|"noul": ...,
             "p_pred": <float 0..1>, "entropy_confidence": <float 0..1>,
             "probabilities": {<criterio>: <float>}}}, "model": "<checkpoint>",
             "latency_ms": <float>}

        CORREÇÃO DE INSTRUMENTO (feita DEPOIS da primeira rodada da ordem 034,
        com o número já publicado — ver git log): o campo `confidence` que
        `laya.Agent.system_one` devolve NÃO é a probabilidade da classe
        prevista. É `confidence_from_probs` (laya/common.py:200): entropia de
        Shannon normalizada, `1 - H(p)/log(k)` — um índice de "quão decidida"
        ficou a distribuição, que para k=3 quase-uniforme cai perto de 0 (a
        primeira rodada mediu 0,0072 numa pergunta de 3 classes; um posterior
        de argmax nunca fica abaixo de 1/3 — o número impossível era o sinal).
        A probabilidade real da classe prevista é `p_pred =
        probabilities[choice]`, onde `probabilities` já vem pronta no dict de
        resposta (`agent.py:313-320`), depois da temperatura PRÓPRIA do laya
        (`self.temperature[qt]`/`temperature_by_options`, `agent.py:304`).
        `entropy_confidence` fica como coluna SEPARADA e nomeada pelo que é —
        é informativa (mede indecisão), não é o posterior, e Brier/ECE/refit
        de temperatura têm de rodar sobre `p_pred`, nunca sobre ela.
        Excecão: `noul` (pergunta sim/não) já devolve um posterior real em
        `confidence` (`max(p, 1-p)`, `agent.py:329`) — ali `p_pred` é só um
        alias do mesmo valor, não um cálculo novo; nenhuma pergunta deste
        spike usa `noul`, mas o contrato cobre o tipo por completude.

        Falha isolada de UM registro não derruba o lote: sai como
            {"id": "...", "error": "<mensagem>"}
        em stdout mesmo, para o chamador contar falhas sem perder o resto.

    python3.13 laya_engine.py --info
        Uma linha JSON: {"threads": N, "torch": "<versão>", "cache_dir": "..."}
        Threads do torch fixadas ANTES de qualquer import de torch/laya, pela
        variável LAYA_TORCH_THREADS (default 4) — impressas aqui para o
        relatório citar o número real em vigor, não um valor assumido.

Modo de teste (--selftest do driver, SEM exigir torch/laya instalados):
    LAYA_ENGINE_STUB=1 muda o comportamento de `predict()` para uma resposta
    determinística derivada de hash(state, questions) — sem importar torch
    nem laya. Existe só para o harness testar o CONTRATO stdin/stdout sem
    pagar o custo (nem exigir a dependência) do motor real. Nunca usado fora
    de --selftest: laya-spike.sh nunca seta LAYA_ENGINE_STUB ao medir M1/M2.
"""
from __future__ import annotations

import hashlib
import json
import os
import sys
import time

STUB_ENV = "LAYA_ENGINE_STUB"
THREADS_ENV = "LAYA_TORCH_THREADS"
DEFAULT_THREADS = 4

_ROUTER = None  # cache de processo: um Router por invocação do CLI, não por linha.


def _configure_threads() -> int:
    """Fixa o número de threads do torch ANTES do primeiro uso e devolve o valor."""
    n = int(os.environ.get(THREADS_ENV, str(DEFAULT_THREADS)))
    import torch  # import tardio: --info/--predict em modo stub nunca paga isto.

    torch.set_num_threads(n)
    return n


def _router():
    global _ROUTER
    if _ROUTER is None:
        _configure_threads()
        from laya import Router

        # Só os dois checkpoints que os corpora deste spike de fato exercitam:
        # M1 é metadado em inglês (nomes de projeto, enum de workflow); M2 é
        # pt-BR verbatim de cases.yaml. `typed-decisions` não corresponde a
        # nenhum dos dois — carregá-lo seria 843 MB de download que o spike
        # não usa, e a ordem pede custo MEDIDO, não custo inflado de propósito.
        # (preload=False no construtor; a seleção real é o .preload() explícito
        # abaixo — passar `models=` no construtor troca o SPEC de origem do
        # checkpoint, não filtra quais preload(), então não serve para isto.)
        _ROUTER = Router(preload=False, max_loaded=2)
        _ROUTER.preload(["english", "multilingual"])
    return _ROUTER


def _stub_predict(state: dict, questions: dict) -> dict:
    """Resposta determinística sem torch/laya — só para --selftest do driver."""
    digest = hashlib.sha256(
        json.dumps({"state": state, "questions": questions}, sort_keys=True, default=str).encode()
    ).digest()
    answers = {}
    for i, (qid, qdef) in enumerate(sorted(questions.items())):
        b = digest[i % len(digest)]
        qtype = qdef.get("type")
        if qtype == "choice":
            keys = sorted((qdef.get("criteria") or {}).keys()) or ["_none_"]
            choice = keys[b % len(keys)]
            # distribuição fake determinística, só para exercitar o contrato
            # {choice, probabilities, p_pred, entropy_confidence} — mesma
            # FORMA que o motor real devolve, sem precisar dele.
            p_pred = round(0.5 + (b / 255.0) * 0.5, 4)
            rest = round((1.0 - p_pred) / max(1, len(keys) - 1), 4) if len(keys) > 1 else 0.0
            probs = {k: (p_pred if k == choice else rest) for k in keys}
            answers[qid] = {
                "type": "choice",
                "choice": choice,
                "probabilities": probs,
                "p_pred": p_pred,
                "entropy_confidence": round(1.0 - (b / 255.0) * 0.3, 4),  # fake, só p/ distinguir dos dois
            }
        elif qtype == "score":
            crit = qdef.get("criteria") or ["0"]
            answers[qid] = {
                "type": "score",
                "score": b % len(crit),
                "entropy_confidence": round(0.5 + (b / 255.0) * 0.5, 4),
            }
        else:  # noul
            p = round(b / 255.0, 4)
            p_pred = round(max(p, 1.0 - p), 4)
            answers[qid] = {
                "type": "noul",
                "noul": p,
                "p_pred": p_pred,
                "entropy_confidence": p_pred,  # noul já é posterior real — ver docstring do módulo
            }
    return {"answers": answers, "model": "stub", "latency_ms": 0.0}


def predict(state, questions: dict) -> dict:
    """A UMA função da interface: estado + perguntas tipadas -> rótulo + confiança.

    Devolve sempre a mesma forma:
        {"answers": {<qid>: {"choice"|"score"|"noul": ...,
                              "p_pred": <float|None>,
                              "entropy_confidence": <float>,
                              "probabilities": <dict|None>}},
         "model": <checkpoint ou "stub">, "latency_ms": <float>}
    independente de o motor por trás ser laya ou (depois) jev.

    `p_pred` é o número para calibração (Brier/ECE/refit de temperatura):
    a probabilidade REAL da classe prevista, não a entropia. Para `choice`,
    vem de `probabilities[choice]` (o laya já devolve essa distribuição —
    ver docstring do módulo). Para `noul`, o `confidence` do laya JÁ é esse
    posterior (`max(p, 1-p)`); `entropy_confidence` recebe o mesmo valor ali
    porque o laya não calcula um índice de entropia separado para `noul`.
    Para `score` não há "classe prevista" (é valor esperado, não argmax) —
    `p_pred` fica None; nenhuma pergunta deste spike usa `score`.
    """
    if os.environ.get(STUB_ENV):
        return _stub_predict(state, questions)

    router = _router()
    t0 = time.perf_counter()
    raw = router.predict(state, questions)
    latency_ms = (time.perf_counter() - t0) * 1000.0

    answers = {}
    for qid, a in raw.get("answers", {}).items():
        atype = a.get("type")
        entry = {"entropy_confidence": a.get("confidence")}
        if atype == "choice":
            choice = a.get("choice")
            probs = a.get("probabilities") or {}
            entry["choice"] = choice
            entry["probabilities"] = probs
            entry["p_pred"] = probs.get(choice)
        elif atype == "score":
            entry["score"] = a.get("score")
            entry["probabilities"] = a.get("probabilities")
            entry["p_pred"] = None
        else:  # noul: o `confidence` do laya já É o posterior (ver docstring)
            entry["noul"] = a.get("noul")
            entry["p_pred"] = a.get("confidence")
        answers[qid] = entry

    return {
        "answers": answers,
        "model": (raw.get("routing") or {}).get("model"),
        "latency_ms": latency_ms,
    }


# --------------------------------------------------------------------------- CLI
def _cmd_predict() -> int:
    rc = 0
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        rec = None
        try:
            rec = json.loads(line)
            out = predict(rec["state"], rec["questions"])
            out["id"] = rec["id"]
        except Exception as exc:  # falha de UM registro não derruba o lote
            rc = 1
            out = {"id": rec.get("id") if isinstance(rec, dict) else None,
                   "error": str(exc)}
        sys.stdout.write(json.dumps(out) + "\n")
        sys.stdout.flush()
    # Pico de RSS do PROCESSO inteiro até este ponto — medido pelo kernel via
    # getrusage, não estimado. ru_maxrss é KB no Linux. Vai em stderr, numa
    # linha só, para não se misturar ao JSONL de stdout que o driver consome.
    try:
        import resource

        peak_kb = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss
        sys.stderr.write(json.dumps({"peak_rss_kb": peak_kb}) + "\n")
    except (ImportError, OSError) as exc:
        # `resource` é POSIX-only (ausente no Windows) e getrusage pode falhar
        # sob sandbox restrito; não é fatal para o lote — mas o motivo vai pro
        # stderr, não desaparece em silêncio.
        sys.stderr.write(json.dumps({"peak_rss_kb": None, "peak_rss_error": str(exc)}) + "\n")
    return rc


def _cmd_info() -> int:
    if os.environ.get(STUB_ENV):
        print(json.dumps({"threads": 0, "torch": "stub", "cache_dir": None}))
        return 0
    n = _configure_threads()
    import torch

    cache_dir = os.environ.get("HF_HOME") or os.path.expanduser("~/.cache/huggingface")
    print(json.dumps({"threads": n, "torch": torch.__version__, "cache_dir": cache_dir}))
    return 0


def main(argv) -> int:
    if "--predict" in argv:
        return _cmd_predict()
    if "--info" in argv:
        return _cmd_info()
    sys.stderr.write("laya_engine.py: uso: --predict (stdin JSONL) | --info\n")
    return 2


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
