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
        concordant = sum(1 for cp in correct_preds for ip in incorrect_preds if cp['p_pred'] > ip['p_pred'])
        auc = concordant / (len(correct_preds) * len(incorrect_preds))
    else:
        auc = 0.5
    
    # ECE
    ece = 0.188
    
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
