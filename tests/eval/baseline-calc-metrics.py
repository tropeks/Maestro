#!/usr/bin/env python3.13
"""Calcula métricas de CV com IC 95% e teste binomial."""
import json
import sys
import math

def wilson_ci(n_successes, n_total, z=1.96):
    """IC 95% binomial (Wilson score)."""
    if n_total == 0:
        return 0, 1
    
    p = n_successes / n_total
    denominator = 1 + z*z / n_total
    
    center = (p + z*z / (2*n_total)) / denominator
    margin = z * math.sqrt(p * (1 - p) / n_total + z*z / (4 * n_total*n_total)) / denominator
    
    return max(0, center - margin), min(1, center + margin)

def expected_calibration_error(preds, n_bins=15):
    """ECE: faixas de largura igual em [0,1], ponderadas pelo n da faixa.

    sum_b (n_b/n) * |media(confianca no b) - media(acerto no b)|; faixa vazia
    nao entra. A definicao vai escrita no cabecalho do TSV, ao lado do numero.
    """
    n = len(preds)
    if n == 0:
        return 0.0
    bins = [[] for _ in range(n_bins)]
    for pr in preds:
        idx = min(int(pr['p_pred'] * n_bins), n_bins - 1)
        bins[idx].append(pr)
    ece = 0.0
    for b in bins:
        if not b:
            continue
        conf_mean = sum(x['p_pred'] for x in b) / len(b)
        acc_mean = sum(x['correct'] for x in b) / len(b)
        ece += (len(b) / n) * abs(conf_mean - acc_mean)
    return ece


def main():
    preds = []
    for line in sys.stdin:
        preds.append(json.loads(line))
    
    if not preds:
        print(json.dumps({"error": "no predictions"}))
        return
    
    n = len(preds)
    n_correct = sum(p['correct'] for p in preds)
    acc = n_correct / n
    
    # IC 95%
    ci_lower, ci_upper = wilson_ci(n_correct, n)
    
    # Brier
    brier = sum((p['p_pred'] - p['correct']) ** 2 for p in preds) / n
    
    # AUC
    correct_preds = [p for p in preds if p['correct'] == 1]
    incorrect_preds = [p for p in preds if p['correct'] == 0]
    
    if len(correct_preds) > 0 and len(incorrect_preds) > 0:
        # empate conta meio ponto: sem isso o AUC sai enviesado para baixo quando
        # muitas predicoes compartilham a mesma confianca.
        concordant = sum(
            1.0 if cp['p_pred'] > ip['p_pred'] else 0.5 if cp['p_pred'] == ip['p_pred'] else 0.0
            for cp in correct_preds for ip in incorrect_preds
        )
        auc = concordant / (len(correct_preds) * len(incorrect_preds))
    else:
        auc = 0.5

    ece = expected_calibration_error(preds)
    
    print(json.dumps({
        "acc": acc,
        "n_correct": n_correct,
        "n_test": n,
        "ci_lower": ci_lower,
        "ci_upper": ci_upper,
        "brier": brier,
        "ece": ece,
        "auc": auc,
        "preds": preds
    }))

if __name__ == '__main__':
    main()
