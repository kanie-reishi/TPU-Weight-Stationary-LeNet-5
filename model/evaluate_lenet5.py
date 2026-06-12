import sys
import torch
import torchvision
import torchvision.transforms as T
import numpy as np
from pathlib import Path

# Add current directory to path
sys.path.append(str(Path(__file__).parent))

from train_golden_model import LeNet5
from hw_simulation import load_weights, hw_forward

def main():
    print("==================================================")
    # 1. Load FP32 model
    print("[1/3] Loading Float32 PyTorch Model...")
    model = LeNet5()
    model.load_state_dict(torch.load("checkpoint/lenet5_float.pt", map_location="cpu"))
    model.eval()

    # 2. Load INT8 weights
    print("[2/3] Loading INT8 Quantized Weights...")
    weights, rs = load_weights()

    # 3. Load 100 test images
    tf = T.Compose([T.Pad(2), T.ToTensor()])
    ds = torchvision.datasets.MNIST("./data", train=False, download=True, transform=tf)
    
    n_images = 100
    print(f"[3/3] Evaluating first {n_images} test images on both models...")
    
    fp32_correct = 0
    int8_correct = 0
    mismatches = 0
    
    print("-" * 60)
    print(f"{'ImageIdx':<10}{'TrueLabel':<12}{'FP32Pred':<12}{'INT8Pred':<12}{'Match':<6}")
    print("-" * 60)
    
    for i in range(n_images):
        img, label = ds[i]
        label = int(label)
        
        # FP32 Forward
        with torch.no_grad():
            logits_fp32 = model(img.unsqueeze(0))
            pred_fp32 = int(logits_fp32.argmax(1).item())
            
        # INT8 Forward
        img_uint8 = (img.numpy() * 255).round().astype(np.uint8)
        pred_int8, _ = hw_forward(img_uint8, weights, rs)
        
        if pred_fp32 == label:
            fp32_correct += 1
        if pred_int8 == label:
            int8_correct += 1
            
        match = "Yes"
        if pred_fp32 != pred_int8:
            match = "NO"
            mismatches += 1
            
        # Print first 15 and any mismatches
        if i < 15 or match == "NO":
            print(f"{i:<10}{label:<12}{pred_fp32:<12}{pred_int8:<12}{match:<6}")
            
    if n_images > 15:
        print("...")
        
    print("-" * 60)
    print("SUMMARY OF ACCURACY COMPILATION:")
    print(f"  - Float32 Model Accuracy  : {fp32_correct}/{n_images} = {fp32_correct/n_images*100:.2f}%")
    print(f"  - Quantized INT8 Accuracy : {int8_correct}/{n_images} = {int8_correct/n_images*100:.2f}%")
    print(f"  - Discrepancies (Mismatches): {mismatches} cases")
    print("==================================================")

if __name__ == "__main__":
    main()
