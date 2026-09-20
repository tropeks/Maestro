#!/usr/bin/env python3.13
"""
Regressão logística multinomial com validação cruzada 5-fold sobre metadado M1.
"""
import json
import sys
import numpy as np

def softmax(logits):
    logits = np.asarray(logits, dtype=np.float64)
    logits = logits - np.max(logits, axis=-1, keepdims=True)
    exps = np.exp(logits)
    return exps / np.sum(exps, axis=-1, keepdims=True)

def one_hot_features(pair):
    features = {}
    for field in ['project', 'workflow', 'mode', 'tool', 'file_ext']:
        val = pair.get(field)
        if val is None or (isinstance(val, list) and len(val) == 0):
            features[f"{field}=__null__"] = 1
        elif isinstance(val, list):
            for item in val:
                features[f"{field}={item}"] = 1
        else:
            features[f"{field}={val}"] = 1
    return features

def build_feature_space(pairs_list):
    all_features = set()
    for pair in pairs_list:
        for field in ['project', 'workflow', 'mode', 'tool', 'file_ext']:
            val = pair.get(field)
            if val is None or (isinstance(val, list) and len(val) == 0):
                all_features.add(f"{field}=__null__")
            elif isinstance(val, list):
                for item in val:
                    all_features.add(f"{field}={item}")
            else:
                all_features.add(f"{field}={val}")
    return sorted(all_features)

def vectorize(pair, feature_names):
    features = one_hot_features(pair)
    vec = np.array([1.0 if feat in features else 0.0 for feat in feature_names], dtype=np.float64)
    return vec

class LogisticRegression:
    def __init__(self, classes, l2=0.1, max_iter=500, learning_rate=0.01):
        self.classes = sorted(classes)
        self.l2 = l2
        self.max_iter = max_iter
        self.learning_rate = learning_rate
        self.W = None
        self.b = None
    
    def fit(self, X, y):
        X = np.asarray(X, dtype=np.float64)
        if X.shape[0] == 0:
            return
        
        n_samples, n_features = X.shape
        n_classes = len(self.classes)
        
        self.W = np.zeros((n_classes, n_features), dtype=np.float64)
        self.b = np.zeros(n_classes, dtype=np.float64)
        
        class_to_idx = {c: i for i, c in enumerate(self.classes)}
        y_idx = np.array([class_to_idx[label] for label in y], dtype=np.int32)
        
        for iteration in range(self.max_iter):
            for i in range(n_samples):
                x_i = X[i:i+1]
                y_i = y_idx[i]
                
                logits = x_i @ self.W.T + self.b
                probs = softmax(logits)[0]
                
                error = probs.copy()
                error[y_i] -= 1.0
                
                self.b -= self.learning_rate * error
                self.W -= self.learning_rate * np.outer(error, x_i[0])
                self.W -= self.learning_rate * self.l2 * self.W
    
    def predict(self, X):
        X = np.asarray(X, dtype=np.float64)
        if self.W is None or X.shape[0] == 0:
            return np.array([]), np.array([]), np.array([])
        
        logits = X @ self.W.T + self.b
        probs = softmax(logits)
        pred_idx = np.argmax(probs, axis=1)
        pred_classes = np.array([self.classes[i] for i in pred_idx])
        pred_probs = np.array([probs[i, pred_idx[i]] for i in range(len(pred_idx))])
        return pred_classes, pred_probs, probs

def stratified_kfold_split(pairs, k=5):
    """Estratificado por outcome."""
    pairs = list(pairs)
    by_outcome = {}
    for i, p in enumerate(pairs):
        outcome = p['outcome']
        if outcome not in by_outcome:
            by_outcome[outcome] = []
        by_outcome[outcome].append((i, p))
    
    folds = [[] for _ in range(k)]
    for outcome, indices_pairs in by_outcome.items():
        for fold_idx, (orig_idx, pair) in enumerate(indices_pairs):
            fold = fold_idx % k
            folds[fold].append((orig_idx, pair))
    
    return folds

def main():
    data = json.loads(sys.stdin.read())
    pairs = data
    
    if not pairs:
        return
    
    all_classes = sorted(set(p['outcome'] for p in pairs))
    feature_names = build_feature_space(pairs)
    
    # 5-fold CV
    folds = stratified_kfold_split(pairs, k=5)
    
    for fold_idx in range(5):
        test_indices_pairs = folds[fold_idx]
        train_pairs = []
        for f_idx in range(5):
            if f_idx != fold_idx:
                train_pairs.extend([p for _, p in folds[f_idx]])
        
        if not train_pairs or not test_indices_pairs:
            continue
        
        X_train = np.array([vectorize(p, feature_names) for p in train_pairs], dtype=np.float64)
        y_train = [p['outcome'] for p in train_pairs]
        
        model = LogisticRegression(all_classes, l2=0.1)
        model.fit(X_train, y_train)
        
        X_test = np.array([vectorize(p, feature_names) for _, p in test_indices_pairs], dtype=np.float64)
        y_test = [p['outcome'] for _, p in test_indices_pairs]
        test_ids = [p['id'] for _, p in test_indices_pairs]
        
        pred_classes, pred_probs, all_probs = model.predict(X_test)
        
        for test_id, true_label, pred_class, p_pred in zip(test_ids, y_test, pred_classes, pred_probs):
            correct = 1 if pred_class == true_label else 0
            record = {
                'id': test_id,
                'true_label': true_label,
                'predicted': pred_class,
                'p_pred': float(p_pred),
                'correct': correct,
                'fold': fold_idx
            }
            print(json.dumps(record))

if __name__ == '__main__':
    main()
