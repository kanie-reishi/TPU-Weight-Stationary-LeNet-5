import os
import numpy as np

# ==============================================================================
# CONFIGURATION
# ==============================================================================
# Trỏ thư mục này tới nơi chứa file quantization.py của bạn nếu muốn load real data
# Nếu thư mục không tồn tại, script sẽ tạo Mock Data để test.
TRAINED_DATA_DIR = "./trained_data"
OUT_DIR = "../tb/hex"

# Testbench parameters matching a tile of computation
# C_in is 16 (matches the 16 rows of the systolic array)
# C_out is 16 (matches the 16 columns of the systolic array)
# N_pixels is the number of cycles the COMPUTE state runs
N_PIXELS = 25  # e.g., 5x5 spatial pixels
ARRAY_SIZE = 16
RIGHT_SHIFT = 2

# ==============================================================================
# GENERATORS
# ==============================================================================
def load_or_generate_data():
    if os.path.exists(TRAINED_DATA_DIR):
        print(f"Loading trained data from {TRAINED_DATA_DIR}...")
        # Placeholder cho việc load file npy thực tế của bạn
        # ifm = np.load(os.path.join(TRAINED_DATA_DIR, "c5_ifm.npy"))
        # weight = np.load(os.path.join(TRAINED_DATA_DIR, "c5_weight.npy"))
        # bias = np.load(os.path.join(TRAINED_DATA_DIR, "c5_bias.npy"))
        pass
    
    print("Generating Mock Data for Testbench (INT8/INT32)...")
    # IFM: N_pixels sequence, each has 16 values (fed to the 16 rows)
    ifm = np.random.randint(-128, 127, size=(N_PIXELS, ARRAY_SIZE), dtype=np.int8)
    
    # Weights: 16 rows x 16 columns
    weight = np.random.randint(-10, 10, size=(ARRAY_SIZE, ARRAY_SIZE), dtype=np.int8)
    
    # Bias: 16 values
    bias = np.random.randint(0, 50, size=(ARRAY_SIZE,), dtype=np.int32)
    
    return ifm, weight, bias

def simulate_pea_top(ifm, weight, bias, rshift):
    """
    Giả lập chính xác logic tính toán của pea_top.sv (RTL):
    - Mỗi chu kỳ, 16 giá trị IFM được nhân với 16 hàng Weight.
    - Psum cộng dồn theo chiều dọc (16 hàng).
    - Post-processing: + Bias, >> shift (có làm tròn), ReLU, Clamp(127).
    """
    n_pixels = ifm.shape[0]
    expected_ofm = np.zeros((n_pixels, ARRAY_SIZE), dtype=np.int8)
    
    for p in range(n_pixels):
        # 1. Tính Dot product qua 16 hàng cho 16 cột (Vector MAC)
        # psum shape: (16,)
        psum = np.zeros(ARRAY_SIZE, dtype=np.int32)
        for c in range(ARRAY_SIZE): # Column
            for r in range(ARRAY_SIZE): # Row
                psum[c] += int(ifm[p, r]) * int(weight[r, c])
                
        # 2. Post-processing (hành vi y hệt khối Post-processing trong pea_top.sv)
        for c in range(ARRAY_SIZE):
            val = psum[c] + int(bias[c])
            
            # Arithmetic Right Shift with Rounding
            if rshift > 0:
                val = (val + (1 << (rshift - 1))) >> rshift
                
            # ReLU & Saturation
            if val < 0:
                val = 0
            elif val > 127:
                val = 127
                
            expected_ofm[p, c] = val
            
    return expected_ofm

# ==============================================================================
# HEX EXPORT (Two's Complement)
# ==============================================================================
def export_hex(filename, data, is_32bit=False):
    os.makedirs(OUT_DIR, exist_ok=True)
    filepath = os.path.join(OUT_DIR, filename)
    with open(filepath, 'w') as f:
        if is_32bit:
            # Ghi INT32 -> 8 ký tự hex (big-endian)
            for val in data.flatten():
                hex_str = f"{np.uint32(val):08X}"
                f.write(hex_str + "\n")
        else:
            # Ghi INT8 -> 2 ký tự hex
            if len(data.shape) > 1 and data.shape[1] == 16:
                # Ghi 16 bytes trên 1 dòng (cho bus 128-bit)
                for row in data:
                    # Nối 16 bytes lại thành 1 chuỗi hex dài 32 ký tự
                    # Note: SystemVerilog $readmemh reads left-to-right (MSB to LSB).
                    # We will output row[15] down to row[0] so that data_in_left[0] gets row[0].
                    row_hex = "".join([f"{np.uint8(v):02X}" for v in reversed(row)])
                    f.write(row_hex + "\n")
            else:
                for val in data.flatten():
                    f.write(f"{np.uint8(val):02X}\n")
    print(f"Exported {filepath}")

def main():
    ifm, weight, bias = load_or_generate_data()
    expected_ofm = simulate_pea_top(ifm, weight, bias, RIGHT_SHIFT)
    
    print("\n--- Shape Info ---")
    print(f"IFM: {ifm.shape}")
    print(f"Weight: {weight.shape}")
    print(f"Bias: {bias.shape}")
    print(f"Expected OFM: {expected_ofm.shape}")
    
    # Export to hex files for SystemVerilog $readmemh
    # IFM exported as 128-bit words (16 bytes per line)
    export_hex("ifm.hex", ifm, is_32bit=False)
    
    # Weight exported as 128-bit words (16 bytes per line). 
    # Each row of the weight matrix is 16 columns (16 weights).
    export_hex("weight.hex", weight, is_32bit=False)
    
    # Bias exported as 32-bit words
    export_hex("bias.hex", bias, is_32bit=True)
    
    # Expected OFM exported as 128-bit words
    export_hex("expected_ofm.hex", expected_ofm, is_32bit=False)
    
    print("\nDone! Testbench data is ready.")

if __name__ == "__main__":
    main()
