#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Evaluate accuracy ONLY (no fine-tuning) for a tiny CNN initialized from Verilog .mem dumps.

Architecture:
    Conv2d(1 -> 16, k=3, stride=1, padding=0)  # 28 -> 26
    ReLU
    MaxPool2d(2,2)                             # 26 -> 13
    Flatten (16*13*13 = 2704)
    Linear(2704 -> 1)                          # binary logit (0 vs 1)

Expected files in --mem-dir:
    conv_w.mem : 144 int8 hex (two's complement)      = 16 * 3 * 3
    conv_b.mem : 16  int32 hex (two's complement)
    fc_w.mem   : 2704 int8 hex (two's complement)     = 1 * (16*13*13)
    fc_b.mem   : 1   int32 hex (two's complement)

Usage:
    python eval_from_mem.py --mem-dir /path/to/mems --data-dir ./data --batch-size 512

It prints: test accuracy (%) on MNIST digits {0,1} only.
"""

import argparse
from pathlib import Path
from typing import List

import torch
import torch.nn as nn
import torch.nn.functional as F
from torch.utils.data import DataLoader, Subset
from torchvision import datasets, transforms


# ---------------------- Parse helpers ----------------------

def parse_hex_signed(hex_str: str, bits: int) -> int:
    v = int(hex_str, 16)
    if v >= (1 << (bits - 1)):
        v -= (1 << bits)
    return v


def load_mem_ints(path: Path, bits: int) -> List[int]:
    vals = []
    with open(path, "r", encoding="utf-8", errors="ignore") as f:
        for raw in f:
            s = raw.strip()
            if not s or s.startswith("//"):
                continue
            vals.append(parse_hex_signed(s, bits))
    return vals


def load_and_build_tensors(mem_dir: Path, device: torch.device):
    conv_w_path = mem_dir / "conv_w.mem"
    conv_b_path = mem_dir / "conv_b.mem"
    fc_w_path   = mem_dir / "fc_w.mem"
    fc_b_path   = mem_dir / "fc_b.mem"

    for p in [conv_w_path, conv_b_path, fc_w_path, fc_b_path]:
        if not p.exists():
            raise FileNotFoundError(f"Missing file: {p}")

    conv_w_i8 = load_mem_ints(conv_w_path, 8)
    conv_b_i32 = load_mem_ints(conv_b_path, 32)
    fc_w_i8 = load_mem_ints(fc_w_path, 8)
    fc_b_i32 = load_mem_ints(fc_b_path, 32)

    # Heuristic scaling (adjust if your dumps used different fixed-point ranges)
    W8_SCALE = 128.0     # ~[-1,1]
    CONV_B_SCALE = 4096.0
    FC_B_SCALE = 32768.0

    conv_w = torch.tensor(conv_w_i8, dtype=torch.float32, device=device) / W8_SCALE
    conv_w = conv_w.view(16, 1, 3, 3).contiguous()

    conv_b = torch.tensor(conv_b_i32, dtype=torch.float32, device=device) / CONV_B_SCALE
    conv_b = conv_b.view(16).contiguous()

    fc_w = torch.tensor(fc_w_i8, dtype=torch.float32, device=device) / W8_SCALE
    fc_w = fc_w.view(1, 16 * 13 * 13).contiguous()

    fc_b = torch.tensor(fc_b_i32, dtype=torch.float32, device=device) / FC_B_SCALE
    fc_b = fc_b.view(1).contiguous()

    return conv_w, conv_b, fc_w, fc_b


# ---------------------- Model ----------------------

class TinyBinaryCNN(nn.Module):
    def __init__(self):
        super().__init__()
        self.conv = nn.Conv2d(1, 16, kernel_size=3, stride=1, padding=0, bias=True)
        self.pool = nn.MaxPool2d(2, 2)
        self.fc = nn.Linear(16 * 13 * 13, 1, bias=True)

    def forward(self, x):
        x = self.conv(x)        # [B,16,26,26]
        x = F.relu(x, inplace=True)
        x = self.pool(x)        # [B,16,13,13]
        x = torch.flatten(x, 1)
        x = self.fc(x)          # [B,1] (logit)
        return x


# ---------------------- Data loaders ----------------------

def mnist_01_loader(data_dir: Path, batch_size: int, split: str):
    assert split in ("train", "test")
    tfm = transforms.Compose([transforms.ToTensor()])
    dset = datasets.MNIST(str(data_dir), train=(split == "train"), transform=tfm, download=True)

    # keep only labels 0 and 1
    idx = [i for i, y in enumerate(dset.targets.tolist()) if y in (0, 1)]
    sub = Subset(dset, idx)
    loader = DataLoader(sub, batch_size=batch_size, shuffle=False, num_workers=2, pin_memory=True)
    return loader


@torch.no_grad()
def evaluate(model: nn.Module, loader: DataLoader, device: torch.device, threshold: float = 0.5):
    model.eval()
    total = 0
    correct = 0
    pos = neg = tp = tn = fp = fn = 0

    for x, y in loader:
        x = x.to(device, non_blocking=True)
        y = y.to(device, non_blocking=True).long()
        logits = model(x).squeeze(1)                 # [B]
        probs = torch.sigmoid(logits)
        pred = (probs >= threshold).long()

        total += y.numel()
        correct += (pred == y).sum().item()

        pos += (y == 1).sum().item()
        neg += (y == 0).sum().item()
        tp += ((pred == 1) & (y == 1)).sum().item()
        tn += ((pred == 0) & (y == 0)).sum().item()
        fp += ((pred == 1) & (y == 0)).sum().item()
        fn += ((pred == 0) & (y == 1)).sum().item()

    acc = 100.0 * correct / max(1, total)
    return {
        "accuracy": acc,
        "total": total, "pos": pos, "neg": neg,
        "tp": tp, "tn": tn, "fp": fp, "fn": fn
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--mem-dir", type=str, default=".", help="Directory with conv_w.mem/conv_b.mem/fc_w.mem/fc_b.mem")
    ap.add_argument("--data-dir", type=str, default="./data", help="Directory for MNIST data")
    ap.add_argument("--batch-size", type=int, default=512)
    ap.add_argument("--threshold", type=float, default=0.5, help="Decision threshold on sigmoid(logit)")
    ap.add_argument("--seed", type=int, default=42)
    args = ap.parse_args()

    torch.manual_seed(args.seed)
    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    print(f"[Info] device={device}")

    conv_w, conv_b, fc_w, fc_b = load_and_build_tensors(Path(args.mem_dir), device)
    model = TinyBinaryCNN().to(device)
    with torch.no_grad():
        model.conv.weight.copy_(conv_w)
        model.conv.bias.copy_(conv_b)
        model.fc.weight.copy_(fc_w)
        model.fc.bias.copy_(fc_b)

    test_loader = mnist_01_loader(Path(args.data_dir), args.batch_size, split="test")
    metrics = evaluate(model, test_loader, device, threshold=args.threshold)

    print("[Eval/Test 0vs1] accuracy: {:.2f}%  (N={})".format(metrics["accuracy"], metrics["total"]))
    print("  Confusion matrix (label first):")
    print("    TP: {tp}   FN: {fn}   (positives={pos})".format(**metrics))
    print("    FP: {fp}   TN: {tn}   (negatives={neg})".format(**metrics))


if __name__ == "__main__":
    main()
