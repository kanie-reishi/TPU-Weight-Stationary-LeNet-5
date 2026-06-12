`timescale 1ns / 1ps

// ============================================================================
// TOP-LEVEL TESTBENCH: tb_v1_eval
// ============================================================================
// Chức năng: Đánh giá hiệu năng V1 (Ping-Pong + Line Buffer + Max Pooling)
// ============================================================================

module tb_v1_eval();

    // =========================================================
    // PARAMETERS & SIGNALS
    // =========================================================
    localparam AXI_AWIDTH = 40;
    localparam AXI_DWIDTH = 128; // Changed to match SRAM_DWIDTH (128)

    // CONV + POOL Settings (From generate_golden_conv_pool.py)
    localparam IFM_W = 28;
    localparam IFM_H = 28;
    localparam C_IN = 1;
    localparam C_OUT = 6;
    localparam K_SIZE = 5;
    localparam OUT_W = 24;
    localparam OUT_H = 24;
    localparam RIGHT_SHIFT = 2;
    localparam RELU_EN = 1;
    
    localparam POOL_K = 2;
    localparam POOL_W = OUT_W / POOL_K;
    localparam POOL_H = OUT_H / POOL_K;

    localparam COUT_TILES = (C_OUT + 15) / 16;
    localparam NUM_PASSES = (C_IN * K_SIZE * K_SIZE + 15) / 16;

    logic clk;
    logic rst_n;

    // --- AXI-Lite Slave (CPU -> FPGA) ---
    logic                    s_axi_awvalid;
    logic                    s_axi_awready;
    logic [31:0]             s_axi_awaddr;
    logic                    s_axi_wvalid;
    logic                    s_axi_wready;
    logic [31:0]             s_axi_wdata;
    
    logic                    s_axi_arvalid;
    logic                    s_axi_arready;
    logic [31:0]             s_axi_araddr;
    logic                    s_axi_rvalid;
    logic                    s_axi_rready;
    logic [31:0]             s_axi_rdata;
    logic [1:0]              s_axi_rresp;
    
    logic                    s_axi_bready;
    logic                    s_axi_bvalid;
    logic [1:0]              s_axi_bresp;

    // --- AXI-Full Master (FPGA -> DDR) ---
    logic [AXI_AWIDTH-1:0]   m_axi_araddr;
    logic [7:0]              m_axi_arlen;
    logic [2:0]              m_axi_arsize;
    logic [1:0]              m_axi_arburst;
    logic                    m_axi_arvalid;
    logic                    m_axi_arready;
    
    logic [AXI_DWIDTH-1:0]   m_axi_rdata;
    logic                    m_axi_rlast;
    logic                    m_axi_rvalid;
    logic                    m_axi_rready;

    logic [AXI_AWIDTH-1:0]   m_axi_awaddr;
    logic [7:0]              m_axi_awlen;
    logic [2:0]              m_axi_awsize;
    logic [1:0]              m_axi_awburst;
    logic                    m_axi_awvalid;
    logic                    m_axi_awready;

    logic [AXI_DWIDTH-1:0]   m_axi_wdata;
    logic                    m_axi_wlast;
    logic                    m_axi_wvalid;
    logic                    m_axi_wready;

    logic [1:0]              m_axi_bresp;
    logic                    m_axi_bvalid;
    logic                    m_axi_bready;

    logic                    finish_irq_o;

    // =========================================================
    // INSTANTIATION
    // =========================================================
    tensor_processing_unit_top #(
        .AXI_AWIDTH(AXI_AWIDTH),
        .AXI_DWIDTH(AXI_DWIDTH)
    ) uut (
        .clk(clk), .rst_n(rst_n),
        .s_axi_awvalid(s_axi_awvalid), .s_axi_awready(s_axi_awready), .s_axi_awaddr(s_axi_awaddr),
        .s_axi_wvalid(s_axi_wvalid), .s_axi_wready(s_axi_wready), .s_axi_wdata(s_axi_wdata),
        .s_axi_arvalid(s_axi_arvalid), .s_axi_arready(s_axi_arready), .s_axi_araddr(s_axi_araddr),
        .s_axi_rvalid(s_axi_rvalid), .s_axi_rready(s_axi_rready), .s_axi_rdata(s_axi_rdata), .s_axi_rresp(s_axi_rresp),
        .s_axi_bready(s_axi_bready), .s_axi_bvalid(s_axi_bvalid), .s_axi_bresp(s_axi_bresp),

        .m_axi_araddr(m_axi_araddr), .m_axi_arlen(m_axi_arlen), .m_axi_arsize(m_axi_arsize),
        .m_axi_arburst(m_axi_arburst), .m_axi_arvalid(m_axi_arvalid), .m_axi_arready(m_axi_arready),
        .m_axi_rdata(m_axi_rdata), .m_axi_rlast(m_axi_rlast), .m_axi_rvalid(m_axi_rvalid), .m_axi_rready(m_axi_rready),
        
        .m_axi_awaddr(m_axi_awaddr), .m_axi_awlen(m_axi_awlen), .m_axi_awsize(m_axi_awsize),
        .m_axi_awburst(m_axi_awburst), .m_axi_awvalid(m_axi_awvalid), .m_axi_awready(m_axi_awready),
        .m_axi_wdata(m_axi_wdata), .m_axi_wlast(m_axi_wlast), .m_axi_wvalid(m_axi_wvalid), .m_axi_wready(m_axi_wready),
        .m_axi_bresp(m_axi_bresp), .m_axi_bvalid(m_axi_bvalid), .m_axi_bready(m_axi_bready),
        
        .finish_irq_o(finish_irq_o)
    );

    // =========================================================
    // CLOCK & RESET
    // =========================================================
    always #5 clk = ~clk; // 100MHz (10ns period)

    initial begin
        #500000; // 500us timeout
        $display("[WATCHDOG] Simulation timeout reached! Force terminating...");
        $finish;
    end

    // =========================================================
    // AXI-LITE BFM (Master)
    // =========================================================
    task axi_lite_write(input logic [31:0] addr, input logic [31:0] data);
        begin
            @(posedge clk);
            s_axi_awaddr  <= addr;
            s_axi_awvalid <= 1'b1;
            s_axi_wdata   <= data;
            s_axi_wvalid  <= 1'b1;
            s_axi_bready  <= 1'b1;

            do begin
                @(posedge clk);
            end while (!(s_axi_awready && s_axi_wready));
            
            s_axi_awvalid <= 1'b0;
            s_axi_wvalid  <= 1'b0;

            while (!s_axi_bvalid) begin
                @(posedge clk);
            end
            
            s_axi_bready  <= 1'b0;
        end
    endtask

    task send_instruction(input logic [63:0] inst);
        begin
            axi_lite_write(32'h0000_0004, inst[63:32]);
            axi_lite_write(32'h0000_0000, inst[31:0]);
        end
    endtask

    logic [31:0] mc_mem [0 : NUM_PASSES * 5 - 1];
    task upload_microcode;
        begin
            $readmemh("microcode.hex", mc_mem);
            for (int p = 0; p < NUM_PASSES; p++) begin
                for (int w = 0; w < 5; w++) begin
                    axi_lite_write(32'h0200 + p * 32 + w * 4, mc_mem[p*5 + w]);
                end
            end
        end
    endtask

    // =========================================================
    // AXI-FULL BFM (DDR Memory Mock - Slave)
    // =========================================================
    logic [7:0] ddr_mem [longint];

    // Read Channel
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            m_axi_arready <= 1'b0;
        end else begin
            if (m_axi_arvalid && !m_axi_arready) m_axi_arready <= 1'b1;
            else if (m_axi_arready) m_axi_arready <= 1'b0;
        end
    end

    initial begin
        m_axi_rvalid <= 1'b0;
        m_axi_rlast  <= 1'b0;
        m_axi_rdata  <= '0;
        forever begin
            @(posedge clk);
            if (m_axi_arvalid && m_axi_arready) begin
                logic [AXI_AWIDTH-1:0] r_addr = m_axi_araddr;
                int r_len = m_axi_arlen;
                
                repeat(5) @(posedge clk); // 5 cycles DDR latency

                for (int i = 0; i <= r_len; i++) begin
                    logic [127:0] temp_data = '0;
                    for (int b = 0; b < 16; b++) begin
                        temp_data[b*8 +: 8] = ddr_mem.exists(r_addr + b) ? ddr_mem[r_addr + b] : 8'h00;
                    end
                    
                    m_axi_rdata  <= temp_data;
                    m_axi_rvalid <= 1'b1;
                    m_axi_rlast  <= (i == r_len);
                    
                    wait(m_axi_rready);
                    @(posedge clk);
                    r_addr = r_addr + 16;
                end
                
                m_axi_rvalid <= 1'b0;
                m_axi_rlast  <= 1'b0;
            end
        end
    end

    // Write Channel
    initial begin
        m_axi_awready <= 1'b0;
        m_axi_wready  <= 1'b0;
        m_axi_bvalid  <= 1'b0;
        m_axi_bresp   <= 2'b00;

        forever begin
            @(posedge clk);
            if (m_axi_awvalid && !m_axi_awready) begin
                m_axi_awready <= 1'b1;
                
                fork
                    begin
                        logic [AXI_AWIDTH-1:0] w_addr = m_axi_awaddr;
                        int w_len = m_axi_awlen;
                        int beats = 0;

                        m_axi_wready <= 1'b1;
                        
                        while (beats <= w_len) begin
                            @(posedge clk);
                            if (m_axi_wvalid && m_axi_wready) begin
                                for (int b = 0; b < 16; b++) begin
                                    ddr_mem[w_addr + b] = m_axi_wdata[b*8 +: 8];
                                end
                                w_addr = w_addr + 16;
                                beats++;
                                if (m_axi_wlast) break;
                            end
                        end
                        m_axi_wready <= 1'b0;
                        
                        @(posedge clk);
                        m_axi_bvalid <= 1'b1;
                        wait(m_axi_bready);
                        @(posedge clk);
                        m_axi_bvalid <= 1'b0;
                    end
                join_none
            end else begin
                m_axi_awready <= 1'b0;
            end
        end
    end

    // =========================================================
    // KỊCH BẢN KIỂM THỬ (TEST SEQUENCE)
    // =========================================================
    localparam IFM_ADDR  = 40'h1000_0000;
    localparam WGT_ADDR  = 40'h2000_0000;
    localparam OFM_ADDR  = 40'h3000_0000;

    logic [7:0] ifm_mem_file [0 : IFM_H * IFM_W * 16 - 1];
    logic [7:0] wgt_mem_file [0 : COUT_TILES * (((C_IN*K_SIZE*K_SIZE+15)/16)*16) * 16 - 1];
    logic [7:0] bias_mem_file [0 : COUT_TILES*32 - 1];
    logic [63:0] inst_mem_file [0 : 15];
    logic [7:0] golden_ofm_file [0 : POOL_H * POOL_W * 16 - 1];
    
    // Performance Metrics Variables
    int global_start_time = 0;
    int compute_start_time = 0;
    int compute_end_time = 0;
    int total_cycles = 0;
    int compute_cycles = 0;
    int dma_cycles = 0;

    initial begin
        // Performance Thread
        fork
            begin
                wait(uut.u_ctrl.dma_req_o == 1'b1);
                global_start_time = $time;
            end
            begin
                wait(uut.u_ctrl.mac_start_o == 1'b1);
                compute_start_time = $time;
            end
            begin
                wait(uut.u_ctrl.pool_done_i == 1'b1);
                compute_end_time = $time;
            end
        join_none

        clk = 0;
        rst_n = 0;
        s_axi_awvalid = 0; s_axi_wvalid = 0; s_axi_arvalid = 0; s_axi_rready = 0; s_axi_bready = 0;
        
        $readmemh("ifm.hex", ifm_mem_file);
        $readmemh("wgt.hex", wgt_mem_file);
        $readmemh("bias.hex", bias_mem_file);
        $readmemh("instructions.hex", inst_mem_file);
        $readmemh("golden_ofm.hex", golden_ofm_file);

        ddr_mem.delete();
        for (int i = 0; i < $size(ifm_mem_file); i++) ddr_mem[IFM_ADDR + i] = ifm_mem_file[i];
        for (int i = 0; i < $size(wgt_mem_file); i++) ddr_mem[WGT_ADDR + i] = wgt_mem_file[i];

        begin
            automatic int total_wgt_elements = C_IN * K_SIZE * K_SIZE;
            automatic int padded_elements_per_tile = ((total_wgt_elements + 15) / 16) * 16;
            automatic int bias_base_word = COUT_TILES * padded_elements_per_tile;
            for (int i = 0; i < $size(bias_mem_file); i++) begin
                ddr_mem[WGT_ADDR + (bias_base_word * 16) + i] = bias_mem_file[i];
            end
        end

        #100 rst_n = 1;
        #100;

        $display("--------------------------------------------------");
        $display("   EVALUATING V1 ARCHITECTURE (CONV + POOL)");
        $display("--------------------------------------------------");

        $display("[+] Sending PEA Array configuration via AXI-Lite...");
        axi_lite_write(32'h0100, IFM_W); // ifm_width
        axi_lite_write(32'h0104, IFM_H); // ifm_height
        axi_lite_write(32'h0108, C_IN);  // channels_in
        axi_lite_write(32'h010C, C_OUT); // channels_out
        axi_lite_write(32'h0110, K_SIZE);// kernel_size
        axi_lite_write(32'h0114, RIGHT_SHIFT); // right_shift
        axi_lite_write(32'h0120, 0); // wgt base
        axi_lite_write(32'h0124, COUT_TILES * NUM_PASSES * 16); // bias base
        axi_lite_write(32'h0128, RELU_EN); // relu enable

        $display("[+] Uploading Window Router Microcode...");
        upload_microcode();

        for(int i = 0; i < 16; i++) begin
            if (inst_mem_file[i] !== 64'bx && inst_mem_file[i] !== 0) begin
                send_instruction(inst_mem_file[i]);
            end
        end

        wait(finish_irq_o);
        
        // Calculate Metrics
        total_cycles = ($time - global_start_time) / 10;
        compute_cycles = (compute_end_time - compute_start_time) / 10;
        dma_cycles = total_cycles - compute_cycles;

        check_results();
        print_metrics();

        $finish;
    end

    task check_results();
        int errors = 0;
        int checked = 0;
        longint offset;
        logic [7:0] hw_val, ref_val;
        
        for (int h = 0; h < POOL_H; h++) begin
            for (int w = 0; w < POOL_W; w++) begin
                for (int cout = 0; cout < C_OUT; cout++) begin
                    offset = (h * POOL_W + w) * 16 + cout;
                    hw_val = ddr_mem.exists(OFM_ADDR + offset) ? ddr_mem[OFM_ADDR + offset] : 8'hXX;
                    ref_val = golden_ofm_file[offset];
                    
                    checked++;
                    if (hw_val !== ref_val) begin
                        $display("[FAIL] At (h=%0d, w=%0d, c=%0d): HW = %0d, REF = %0d", h, w, cout, $signed(hw_val), $signed(ref_val));
                        errors++;
                    end
                end
            end
        end
        
        $display("\n==================================================");
        if (errors == 0) $display("[PASS] All %0d POOLED pixels match perfectly!", checked);
        else             $display("[FAIL] There are %0d / %0d mismatched pixels.", errors, checked);
        $display("==================================================");
    endtask

    task print_metrics();
        real theoretical_macs;
        real available_macs;
        real mac_utilization;
        real compute_bound_ratio;
        
        // 1. MAC Utilization
        theoretical_macs = OUT_W * OUT_H * C_OUT * C_IN * K_SIZE * K_SIZE;
        available_macs = compute_cycles * 256.0; // 16x16 PEA
        mac_utilization = (theoretical_macs * 100.0) / available_macs;
        
        // 2. Compute vs Memory Bound
        compute_bound_ratio = (compute_cycles * 100.0) / total_cycles;

        $display("\n--- [V1 ARCHITECTURE PERFORMANCE METRICS] ---");
        $display("1. Cycle Counts:");
        $display("   - Total Execution Cycles: %0d", total_cycles);
        $display("   - Compute Latency (MAC + POOL): %0d", compute_cycles);
        $display("   - DMA Overhead (Load + Store): %0d", dma_cycles);
        $display("\n2. Compute Efficiency:");
        $display("   - Theoretical MACs: %.0f", theoretical_macs);
        $display("   - Available MAC Capacity (cycles * 256): %.0f", available_macs);
        $display("   - MAC Utilization: %.2f %%", mac_utilization);
        $display("\n3. Compute vs Memory Ratio:");
        $display("   - Compute Time: %.2f %%", compute_bound_ratio);
        $display("   - DMA Transfer Time: %.2f %%", 100.0 - compute_bound_ratio);
        $display("--------------------------------------------------\n");
    endtask

endmodule
