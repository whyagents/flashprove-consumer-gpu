#!/usr/bin/env python3
# Track A / A10: our own floating-point reference for TinyStories260K (Karpathy's llama2.c checkpoint format),
# written from the llama2.c model definition, standard library only (no numpy, no L4 code).
#  1. validate: greedy generation from BOS must reproduce Karpathy's published temperature-0 sample;
#  2. compute the float model's next token after the exact request we proved (A9), and its logit margin.
# usage: python3 -I -B a10_float_reference.py CHECKPOINT TOKENIZER REQUEST_FILE [GREEDY_STEPS]
import math, struct, sys, hashlib

def floats(buf, off, n):
    return list(struct.unpack_from("<%df" % n, buf, off)), off + 4 * n

def load(path):
    b = open(path, "rb").read()
    dim, hidden, L, H, G, V, S = struct.unpack_from("<7i", b, 0)
    shared = V > 0
    V = abs(V)
    hs = dim // H
    kv = dim * G // H
    off = 28
    W = {}
    def mat(name, n):
        nonlocal off
        W[name], off = floats(b, off, n)
    mat("emb", V * dim); mat("rms_att", L * dim); mat("wq", L * dim * dim); mat("wk", L * dim * kv)
    mat("wv", L * dim * kv); mat("wo", L * dim * dim); mat("rms_ffn", L * dim)
    mat("w1", L * hidden * dim); mat("w2", L * dim * hidden); mat("w3", L * hidden * dim); mat("rms_f", dim)
    off += 4 * S * hs  # freq_cis_real and freq_cis_imag (S * hs/2 each): not used, RoPE is computed
    if not shared:
        mat("wcls", V * dim)
    else:
        W["wcls"] = W["emb"]
    cfg = dict(dim=dim, hidden=hidden, L=L, H=H, G=G, V=V, S=S, hs=hs, kv=kv, shared=shared,
               bytes=len(b), consumed=off, sha256=hashlib.sha256(b).hexdigest())
    return cfg, W

def rmsnorm(x, w, o):
    ss = sum(v * v for v in x) / len(x) + 1e-5
    s = 1.0 / math.sqrt(ss)
    return [w[o + i] * x[i] * s for i in range(len(x))]

def matvec(W, o, x, n_out, n_in):  # W row-major [n_out][n_in] at offset o
    out = [0.0] * n_out
    for i in range(n_out):
        r = o + i * n_in
        out[i] = sum(W[r + j] * x[j] for j in range(n_in))
    return out

class Model:
    def __init__(self, cfg, W):
        self.c, self.W = cfg, W
        self.kc = [[] for _ in range(cfg["L"])]
        self.vc = [[] for _ in range(cfg["L"])]
    def step(self, tok, pos):
        c, W = self.c, self.W
        d, hs, kv, hid = c["dim"], c["hs"], c["kv"], c["hidden"]
        x = W["emb"][tok * d:(tok + 1) * d]
        kvmul = c["H"] // c["G"]
        for l in range(c["L"]):
            xb = rmsnorm(x, W["rms_att"], l * d)
            q = matvec(W["wq"], l * d * d, xb, d, d)
            k = matvec(W["wk"], l * d * kv, xb, kv, d)
            v = matvec(W["wv"], l * d * kv, xb, kv, d)
            for i in range(0, d, 2):  # RoPE as in llama2.c run.c: adjacent pairs
                hd = i % hs
                f = 1.0 / (10000.0 ** (hd / hs))
                a = pos * f
                cr, ci = math.cos(a), math.sin(a)
                for vec, lim in ((q, d), (k, kv)):
                    if i < lim:
                        v0, v1 = vec[i], vec[i + 1]
                        vec[i], vec[i + 1] = v0 * cr - v1 * ci, v0 * ci + v1 * cr
            self.kc[l].append(k); self.vc[l].append(v)
            att_out = [0.0] * d
            for h in range(c["H"]):
                qh = q[h * hs:(h + 1) * hs]
                g = h // kvmul
                sc = []
                for t in range(pos + 1):
                    kt = self.kc[l][t]
                    sc.append(sum(qh[i] * kt[g * hs + i] for i in range(hs)) / math.sqrt(hs))
                m = max(sc); e = [math.exp(s - m) for s in sc]; z = sum(e)
                for t in range(pos + 1):
                    a = e[t] / z
                    vt = self.vc[l][t]
                    for i in range(hs):
                        att_out[h * hs + i] += a * vt[g * hs + i]
            o = matvec(W["wo"], l * d * d, att_out, d, d)
            x = [x[i] + o[i] for i in range(d)]
            xb = rmsnorm(x, W["rms_ffn"], l * d)
            h1 = matvec(W["w1"], l * hid * d, xb, hid, d)
            h3 = matvec(W["w3"], l * hid * d, xb, hid, d)
            hh = [(h1[i] / (1.0 + math.exp(-h1[i]))) * h3[i] for i in range(hid)]
            o = matvec(W["w2"], l * d * hid, hh, d, hid)
            x = [x[i] + o[i] for i in range(d)]
        x = rmsnorm(x, W["rms_f"], 0)
        return matvec(W["wcls"], 0, x, c["V"], d)

def tokenizer(path, V):
    b = open(path, "rb").read()
    (maxlen,) = struct.unpack_from("<i", b, 0); off = 4; vocab = []
    for _ in range(V):
        _score, n = struct.unpack_from("<fi", b, off); off += 8
        vocab.append(b[off:off + n]); off += n
    return vocab, hashlib.sha256(b).hexdigest()

def piece(vocab, prev, tok):
    p = vocab[tok]
    if prev == 1 and p.startswith(b" "): p = p[1:]
    if p.startswith(b"<0x") and p.endswith(b">") and len(p) == 6: p = bytes([int(p[3:5], 16)])
    return p

def top2(logits):
    o = sorted(range(len(logits)), key=lambda i: -logits[i])
    return o[0], o[1], logits[o[0]] - logits[o[1]]

def main():
    ckpt, tokp, reqp = sys.argv[1:4]
    steps = int(sys.argv[4]) if len(sys.argv) > 4 else 60
    cfg, W = load(ckpt)
    print("checkpoint", {k: cfg[k] for k in ("dim", "hidden", "L", "H", "G", "V", "S", "shared", "bytes", "consumed", "sha256")})
    if cfg["consumed"] != cfg["bytes"]:
        print("WARNING: bytes consumed != file size: layout differs from llama2.c version 0");
    vocab, tsha = tokenizer(tokp, cfg["V"])
    print("tokenizer sha256", tsha)
    # 1. greedy from BOS (token 1), as llama2.c run.c with -t 0.0
    m = Model(cfg, W); tok, pos, out, margins = 1, 0, [], []
    while pos < steps:
        lg = m.step(tok, pos); nxt, _, mg = top2(lg); margins.append(mg)
        if nxt == 1: break
        out.append(piece(vocab, tok, nxt)); tok = nxt; pos += 1
    print("GREEDY:", b"".join(out).decode("utf-8", "replace").replace("\n", "\\n"))
    print("greedy_min_top2_margin=%.4f" % min(margins))
    # 2. the proved request: T tokens, then r and e (FORMAT.md 12.2; as read_claim.py reads it)
    rb = open(reqp, "rb").read(); n = len(rb) // 4
    words = list(struct.unpack("<%dI" % n, rb)); T = n - 2
    toks, r, e = words[:T], words[T], words[T + 1]
    print("request: T=%d r=%d e=%d sha256=%s first=%s" % (T, r, e, hashlib.sha256(rb).hexdigest(), toks[:8]))
    print("request is the 64-token prefix x4:", toks == toks[:64] * 4)
    m = Model(cfg, W); lg = None
    for p in range(r + 1):
        lg = m.step(toks[p], p)
    a, b2, mg = top2(lg)
    print("FLOAT next token after position r=%d: %d (%r); runner-up %d (%r); logit margin %.4f" %
          (r, a, piece(vocab, toks[r], a), b2, piece(vocab, toks[r], b2), mg))
    print("matches proved token 310:", a == 310)

if __name__ == "__main__":
    main()
