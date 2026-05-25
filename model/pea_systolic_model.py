import numpy as np

class PEASystolicModel:
    def __init__(self, array_size=16):
        self.array_size = array_size
        # PEA Registers
        self.reg_ifm_width = 0
        self.reg_ifm_height = 0
        self.reg_channels_in = 0
        self.reg_channels_out = 0
        self.reg_kernel_size = 0
        self.reg_right_shift = 0

        self.weights = np.zeros((array_size, array_size), dtype=np.int8)
        self.biases = np.zeros(array_size, dtype=np.int32)
        
    def configure(self, w, h, cin, cout, k, rshift):
        self.reg_ifm_width = w
        self.reg_ifm_height = h
        self.reg_channels_in = cin
        self.reg_channels_out = cout
        self.reg_kernel_size = k
        self.reg_right_shift = rshift
        print(f"[Config] W:{w} H:{h} Cin:{cin} Cout:{cout} K:{k} Shift:{rshift}")

    def load_weights_and_bias(self, weights, biases):
        """
        Loads weights into the 16x16 grid and biases into the Post-Processing array.
        weights shape expected: (array_size, array_size) 
        biases shape expected: (array_size,)
        """
        self.weights = np.copy(weights)
        self.biases = np.copy(biases)
        print("[Memory] Loaded Weights and Biases into PEA.")

    def post_processing(self, psum_array):
        """
        Applies Bias, ReLU, and Quantization (Arithmetic Right Shift)
        """
        ofm_array = np.zeros_like(psum_array, dtype=np.int8)
        
        for i in range(len(psum_array)):
            # 1. Vector Adder (Bias Addition)
            val = psum_array[i] + self.biases[i]
            
            # 2. Arithmetic Right Shift Quantization
            val = val >> self.reg_right_shift
            
            # 3. ReLU Activation & Saturation to INT8 (0-127)
            if val < 0:
                val = 0
            elif val > 127:
                val = 127
            
            ofm_array[i] = np.int8(val)
            
        return ofm_array

    def run_compute(self, ifm_data):
        """
        Simulates the AGU Im2Col nested loops and Systolic array propagation
        ifm_data: 3D numpy array (Height, Width, C_in)
        Returns: 2D numpy array (Flattened Output Pixels, min(C_out, array_size))
        """
        out_w = self.reg_ifm_width - self.reg_kernel_size + 1
        out_h = self.reg_ifm_height - self.reg_kernel_size + 1
        
        ofm_result = []

        print("[Compute] Starting nested loops Im2Col AGU...")
        # AGU Nested Loops (matching hardware FSM)
        for out_y in range(out_h):
            for out_x in range(out_w):
                
                psum_accumulator = np.zeros(self.array_size, dtype=np.int32)
                
                # Flattened loop over the filter spatial dimensions and input channels
                row_idx = 0
                for ky in range(self.reg_kernel_size):
                    for kx in range(self.reg_kernel_size):
                        for cin in range(self.reg_channels_in):
                            if row_idx >= self.array_size:
                                break # Safety check for simulation mapping
                            
                            # Hardware AGU: Im2Col address generation
                            ifm_val = ifm_data[out_y + ky, out_x + kx, cin]
                            
                            # Systolic array computation (Vector MAC across the 16 columns)
                            for col_idx in range(self.array_size):
                                w_val = self.weights[row_idx, col_idx]
                                psum_accumulator[col_idx] += int(ifm_val) * int(w_val)
                                
                            row_idx += 1
                
                # Hardware Post Processing at the bottom of the array
                final_ofm = self.post_processing(psum_accumulator)
                ofm_result.append(final_ofm)

        print("[Compute] Completed.")
        return np.array(ofm_result)

# =====================================================================
# Testbench
# =====================================================================
if __name__ == "__main__":
    pea = PEASystolicModel(array_size=16)
    
    # Configure for a mock convolution layer
    # IFM 5x5, 2 Input Channels, 4 Output Channels, Kernel 2x2, Shift 2
    pea.configure(w=5, h=5, cin=2, cout=4, k=2, rshift=2)
    
    # Generate random INT8 Weights and INT32 Biases
    # (Using 16x16 grid, but only first 8 rows (2*2*2) and 4 columns are mathematically active here)
    mock_weights = np.random.randint(-10, 10, size=(16, 16), dtype=np.int8)
    mock_biases = np.random.randint(0, 50, size=16, dtype=np.int32)
    pea.load_weights_and_bias(mock_weights, mock_biases)
    
    # Generate random INT8 IFM Data
    mock_ifm = np.random.randint(0, 127, size=(5, 5, 2), dtype=np.int8)
    
    # Execute Hardware Model
    output = pea.run_compute(mock_ifm)
    
    print("\n--- Simulation Results ---")
    print("IFM Shape (H,W,C):", mock_ifm.shape)
    print("OFM Shape (Flattened_Pixels, Columns):", output.shape)
    print("Sample Output (first pixel across all 16 columns):", output[0])
