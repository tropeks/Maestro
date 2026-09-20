#!/usr/bin/env python3.13
"""
Regressão logística multinomial com L2 fixo sobre metadado M1.
NumPy puro, determinístico, sem seed aleatória.
L2 = 0.1 (fixo, declarado antes de qualquer medição).
"""
import json
import sys
import numpy as np

def softmax(logits):
    """Softmax numericamente estável."""
    logits = np.asarray(logits, dtype=np.float64)
    logits = logits - np.max(logits, axis=-1, keepdims=True)
    exps = np.exp(logits)
    return exps / np.sum(exps, axis=-1, keepdims=True)

def one_hot_features(pair):
    """One-hot encode categoriais."""
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
    """Coleta todos os feature names."""
    all_features = {}
    for pair in pairs_list:
        for field in ['project', 'workflow', 'mode', 'tool', 'file_ext']:
            val = pair.get(field)
            if val is None or (isinstance(val, list) and len(val) == 0):
                key = f"{field}=__null__"
                all_features[key] = True
            elif isinstance(val, list):
                for item in val:
                    key = f"{field}={item}"
                    all_features[key] = True
            else:
                key = f"{field}={val}"
                all_features[key] = True
    return sorted(all_features.keys())

def vectorize(pair, feature_names):
    """Converte pair em vetor binário."""
    features = one_hot_features(pair)
    vec = np.array([1.0 if feat in features else 0.0 for feat in feature_names], dtype=np.float64)
    return vec

class LogisticRegression:
    """Multinomial logistic com SGD e L2 fixo."""
    
    def __init__(self, classes, l2=0.1, max_iter=500, learning_rate=0.01):
        self.classes = sorted(classes)
        self.l2 = l2
        self.max_iter = max_iter
        self.learning_rate = learning_rate
        self.W = None
        self.b = None
    
    def fit(self, X, y):
        """SGD simples."""
        X = np.asarray(X, dtype=np.float64)
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
        """Prediz classes e probabilidades."""
        X = np.asarray(X, dtype=np.float64)
        logits = X @ self.W.T + self.b
        probs = softmax(logits)
        pred_idx = np.argmax(probs, axis=1)
        pred_classes = np.array([self.classes[i] for i in pred_idx])
        pred_probs = np.array([probs[i, pred_idx[i]] for i in range(len(pred_idx))])
        return pred_classes, pred_probs

def main():
    data = json.loads(sys.stdin.read())
    adjust = data['ajuste']
    teste = data['teste']
    
    all_pairs = adjust + teste
    feature_names = build_feature_space(all_pairs)
    
    X_adjust = np.array([vectorize(p, feature_names) for p in adjust], dtype=np.float64)
    y_adjust = [p['outcome'] for p in adjust]
    
    X_test = np.array([vectorize(p, feature_names) for p in teste], dtype=np.float64)
    y_test = [p['outcome'] for p in teste]
    test_ids = [p.get('id', f'test-{i}') for i, p in enumerate(teste)]
    
    classes = sorted(set(y_adjust + y_test))
    model = LogisticRegression(classes, l2=0.1, max_iter=500, learning_rate=0.01)
    model.fit(X_adjust, y_adjust)
    
    pred_classes, pred_probs = model.predict(X_test)
    
    for test_id, true_label, pred_class, p_pred in zip(test_ids, y_test, pred_classes, pred_probs):
        correct = 1 if pred_class == true_label else 0
        record = {
            'id': test_id,
            'true_label': true_label,
            'predicted': pred_class,
            'p_pred': float(p_pred),
            'correct': correct
        }
        print(json.dumps(record))

if __name__ == '__main__':
    main()
