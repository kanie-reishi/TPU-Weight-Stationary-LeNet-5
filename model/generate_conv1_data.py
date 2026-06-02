import sys
import os
import json
import numpy as np
import hw_simulation

def generate_hex():
    # Load weights
    weights, rs = hw_simulation.load_weights()
    
    # 1. Image
    # Get a "5" from MNIST
    import torchvision
    import torchvision.transforms as T
    ds = torchvision.datasets.MNIST(
        "./data", train=False, download=True,
        transform=T.Compose([T.Pad(2), T.ToTensor()]) # 32x32 padded
    )
    
    # Find a '5'
    target_img = None
    for img, label in ds:
        if int(label) == 5:
            target_img = (img.numpy() * 255).round().astype(np.uint8) # [1, 32, 32]
            break
            
    if target_img is None:
        target_img = (ds[0][0].numpy() * 255).round().astype(np.uint8)

    # 2. Extract Conv1 weights and bias
    c1_w = weights["c1_w"] # [6, 1, 5, 5]
    c1_b = weights["c1_b"] # [6]
    
    # Pad weights to 16 channels
    # WGT layout: [cout=16, cin=1, kH=5, kW=5]
    w_padded = np.zeros((16, 1, 5, 5), dtype=np.int8)
    w_padded[:6, :, :, :] = c1_w
    
    # Bias layout: [cout=16]
    b_padded = np.zeros((16,), dtype=np.int32)
    b_padded[:6] = c1_b
    
    # 3. Simulate hardware forward pass to get exact IFM and expected OFM
    pred, mid = hw_simulation.hw_forward(target_img, weights, rs, verbose=False)
    
    # OFM: c1_out is [6, 28, 28]
    # Pad OFM to 16 channels
    ofm_padded = np.zeros((16, 28, 28), dtype=np.uint8)
    ofm_padded[:6, :, :] = mid["c1_out"]
    
    # 4. Format into HEX files
    out_dir = '../tb/hex_conv1'
    os.makedirs(out_dir, exist_ok=True)
    
    # Write IFM (32x32 = 1024 bytes -> 1024 lines of 128-bit)
    ifm_flat = target_img.flatten() # 1024 elements
    with open(f'{out_dir}/ifm.hex', 'w') as f:
        for val in ifm_flat:
            # Each pixel takes 1 word (16 channels padded, but since cin=1, it's just the pixel at LSB)
            hex_str = f'{val:02x}'
            # Pad to 128-bit (32 hex characters)
            hex_str = hex_str.zfill(32)
            f.write(f'{hex_str}\n')
            
    # Write Weights (16 cout * 5 * 5 = 400 tiles, each tile has 16 cin words -> 400 lines of 128-bit)
    with open(f'{out_dir}/weight.hex', 'w') as f:
        for y in range(5):
            for x in range(5):
                # Word 0: valid weights for cin=0
                chunk = [int(w_padded[cout, 0, y, x]) for cout in range(16)]
                chunk = [(b + 256) % 256 for b in chunk]
                hex_str = ''.join(f'{b:02x}' for b in reversed(chunk))
                f.write(f'{hex_str}\n')
                # Words 1..15: padded weights for cin=1..15
                for _ in range(15):
                    f.write('00'*16 + '\n')
                
    # Write Bias (16 lines of 32-bit)
    with open(f'{out_dir}/bias.hex', 'w') as f:
        for cout in range(16):
            val = int(b_padded[cout])
            if val < 0: val += (1 << 32)
            f.write(f'{val:08x}\n')
            
    # Write OFM (16 channels * 28 * 28 = 12544 bytes -> 784 lines of 128-bit)
    with open(f'{out_dir}/expected_ofm.hex', 'w') as f:
        for y in range(28):
            for x in range(28):
                chunk = [ofm_padded[cout, y, x] for cout in range(16)]
                hex_str = ''.join(f'{b:02x}' for b in reversed(chunk))
                f.write(f'{hex_str}\n')

    print("Generated HEX files in tb/hex_conv1/")

if __name__ == '__main__':
    generate_hex()
