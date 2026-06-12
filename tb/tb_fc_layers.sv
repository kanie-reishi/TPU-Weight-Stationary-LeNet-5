`timescale 1ns / 1ps

module tb_fc_layers();

    // ==========================================
    // Configuration Parameters
    // ==========================================
    localparam AXI_AWIDTH  = 40;
    localparam AXI_DWIDTH  = 128;
    localparam SRAM_AWIDTH = 11;

    localparam C_IN  = 120;
    localparam C_OUT = 84;

    // FC layer (1x1 conv) config - khop voi tb/scripts/generate_fc.py
    localparam IFM_W       = 1;
    localparam IFM_H       = 1;
    localparam K_SIZE      = 1;
    localparam RIGHT_SHIFT = 2;
    localparam RELU_EN     = 1;
    localparam COUT_TILES  = (C_OUT + 15) / 16;
    localparam NUM_PASSES  = (C_IN * K_SIZE * K_SIZE + 15) / 16;
    localparam BIAS_BASE   = COUT_TILES * NUM_PASSES * 16;
    
    // ==========================================
    // Signals Declaration
    // ==========================================
    logic clk;
    logic rst_n;
    
    // AXI-Lite
    logic [31:0] s_axi_awaddr, s_axi_wdata;
    logic s_axi_awvalid, s_axi_wvalid, s_axi_bready;
    logic s_axi_awready, s_axi_wready, s_axi_bvalid;
    logic [1:0]  s_axi_bresp;

    logic [31:0] s_axi_araddr;
    logic        s_axi_arvalid, s_axi_arready;
    logic [31:0] s_axi_rdata;
    logic        s_axi_rvalid, s_axi_rready;
    logic [1:0]  s_axi_rresp;
    
    // AXI-Full (Mock)
    logic [AXI_AWIDTH-1:0] m_axi_araddr, m_axi_awaddr;
    logic [7:0]  m_axi_arlen, m_axi_awlen;
    logic [2:0]  m_axi_arsize, m_axi_awsize;
    logic [1:0]  m_axi_arburst, m_axi_awburst;
    logic        m_axi_arvalid, m_axi_arready;
    logic        m_axi_awvalid, m_axi_awready;
    logic [AXI_DWIDTH-1:0] m_axi_wdata, m_axi_rdata;
    logic        m_axi_wvalid, m_axi_wready, m_axi_wlast;
    logic        m_axi_rvalid, m_axi_rready, m_axi_rlast;
    logic        m_axi_bvalid, m_axi_bready;
    logic [1:0]  m_axi_bresp;
    
    // Interrupt
    logic finish_irq_o;

    // ==========================================
    // INIT DUT
    // ==========================================
    tensor_processing_unit_top #(
        .AXI_AWIDTH(AXI_AWIDTH),
        .AXI_DWIDTH(AXI_DWIDTH),
        .SRAM_AWIDTH(SRAM_AWIDTH)
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .s_axi_awaddr(s_axi_awaddr),   .s_axi_awvalid(s_axi_awvalid), .s_axi_awready(s_axi_awready),
        .s_axi_wdata(s_axi_wdata),     .s_axi_wvalid(s_axi_wvalid),   .s_axi_wready(s_axi_wready),
        .s_axi_bready(s_axi_bready),   .s_axi_bvalid(s_axi_bvalid),   .s_axi_bresp(s_axi_bresp),

        .s_axi_araddr(s_axi_araddr),   .s_axi_arvalid(s_axi_arvalid), .s_axi_arready(s_axi_arready),
        .s_axi_rdata(s_axi_rdata),     .s_axi_rvalid(s_axi_rvalid),   .s_axi_rready(s_axi_rready),
        .s_axi_rresp(s_axi_rresp),

        .m_axi_araddr(m_axi_araddr),   .m_axi_arlen(m_axi_arlen),     .m_axi_arsize(m_axi_arsize),   .m_axi_arburst(m_axi_arburst),
        .m_axi_arvalid(m_axi_arvalid), .m_axi_arready(m_axi_arready),
        .m_axi_rdata(m_axi_rdata),     .m_axi_rvalid(m_axi_rvalid),
        .m_axi_rready(m_axi_rready),   .m_axi_rlast(m_axi_rlast),
        .m_axi_awaddr(m_axi_awaddr),   .m_axi_awlen(m_axi_awlen),     .m_axi_awsize(m_axi_awsize),   .m_axi_awburst(m_axi_awburst),
        .m_axi_awvalid(m_axi_awvalid), .m_axi_awready(m_axi_awready),
        .m_axi_wdata(m_axi_wdata),     .m_axi_wvalid(m_axi_wvalid),
        .m_axi_wlast(m_axi_wlast),     .m_axi_wready(m_axi_wready),
        .m_axi_bvalid(m_axi_bvalid),   .m_axi_bready(m_axi_bready),   .m_axi_bresp(m_axi_bresp),
        .finish_irq_o(finish_irq_o)
    );

    // ==========================================
    // CLOCK & RESET
    // ==========================================
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end
    
    // AXI-Lite Task
    task axi_lite_write(input [31:0] addr, input [31:0] data);
        begin
            @(posedge clk);
            s_axi_awaddr  <= addr;
            s_axi_wdata   <= data;
            s_axi_awvalid <= 1'b1;
            s_axi_wvalid  <= 1'b1;
            s_axi_bready  <= 1'b1;
            do begin
                @(posedge clk);
            end while (!(s_axi_awready && s_axi_wready));
            s_axi_awvalid <= 1'b0;
            s_axi_wvalid  <= 1'b0;
            while (!s_axi_bvalid) @(posedge clk);
            s_axi_bready  <= 1'b0;
        end
    endtask

    task send_instruction(input logic [63:0] inst);
        begin
            axi_lite_write(32'h0000_0004, inst[63:32]);
            axi_lite_write(32'h0000_0000, inst[31:0]);
        end
    endtask

    task upload_microcode(input string filename, input int num_passes);
        begin
            logic [31:0] mc_mem [0 : 40 - 1];
            $readmemh(filename, mc_mem);
            for (int p = 0; p < num_passes; p++) begin
                for (int w = 0; w < 5; w++) begin
                    axi_lite_write(32'h0200 + p * 32 + w * 4, mc_mem[p*5 + w]);
                end
            end
        end
    endtask

    // =========================================================
    // AXI-FULL MASTER BFM (Mock DDR Memory)
    // =========================================================
    logic [7:0] ddr_mem [0:4194303];
    // Anh xa dia chi AXI 40-bit -> chi so ddr_mem 22-bit = {addr[29:28], addr[19:0]}.
    // Dung function de hop le ca khi lam lvalue ghi (iverilog gioi han index lvalue phuc tap).
    function automatic int unsigned ddr_idx(input logic [AXI_AWIDTH-1:0] a);
        ddr_idx = {a[29:28], a[19:0]};
    endfunction
    // Ghi 1 byte mock DDR. iverilog khong cho index lvalue phuc tap, nen tinh index
    // ra bien tam roi gan vao ddr_mem[idx] trong task. (Doc dung macro so hoc ben duoi.)
    task automatic ddr_write(input logic [AXI_AWIDTH-1:0] a, input logic [7:0] d);
        int unsigned idx;
        idx = ddr_idx(a);
        ddr_mem[idx] = d;
    endtask
    // Doc (rvalue): tinh index ra bien tam (ddr_idx khong doc memory nen hop le),
    // roi truy cap ddr_mem[idx]. Khong dung macro `DDR vi cac cho goi thieu backtick.

    // Read Channel BFM
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
                logic [AXI_AWIDTH-1:0] r_addr;
                int r_len;
                r_addr = m_axi_araddr;
                r_len = m_axi_arlen;
                
                repeat(5) @(posedge clk); // 5 cycles memory latency

                for (int i = 0; i <= r_len; i++) begin
                    logic [127:0] temp_data;
                    temp_data = '0;
                    for (int b = 0; b < 16; b++) begin
                        int unsigned ridx;
                        ridx = ddr_idx(r_addr + b);
                        temp_data[b*8 +: 8] = ddr_mem[ridx];
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

    // Write Channel BFM
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
                        logic [AXI_AWIDTH-1:0] w_addr;
                        int w_len;
                        int beats;
                        w_addr = m_axi_awaddr;
                        w_len = m_axi_awlen;
                        beats = 0;

                        m_axi_wready <= 1'b1;
                        
                        while (beats <= w_len) begin
                            @(posedge clk);
                            if (m_axi_wvalid && m_axi_wready) begin
                                for (int b = 0; b < 16; b++) begin
                                    ddr_write(w_addr + b, m_axi_wdata[b*8 +: 8]);
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

    // ==========================================
    // Temp memory to load hex files
    // ==========================================
    logic [7:0] ifm_mem [0 : 128 - 1];
    logic [7:0] wgt_mem [0 : 12288 - 1];
    logic [7:0] bias_mem [0 : 192 - 1];
    logic [63:0] insts_mem [0 : 10 - 1];
    logic [7:0] golden_ofm_mem [0 : 96 - 1];

    // ==========================================
    // MAIN TEST FLOW
    // ==========================================
    initial begin
        // Reset state
        rst_n = 0;
        s_axi_awvalid = 0; s_axi_wvalid = 0; s_axi_bready = 0;
        s_axi_arvalid = 0; s_axi_rready = 0;
        m_axi_arready = 0; m_axi_awready = 0; m_axi_wready = 0; m_axi_bvalid = 0;
        
        $display("==================================================");
        $display("   [INIT] Pre-loading FC Layer test vectors...");
        $display("==================================================");

        $readmemh("ifm.hex", ifm_mem);
        $readmemh("wgt.hex", wgt_mem);
        $readmemh("bias.hex", bias_mem);
        $readmemh("instructions.hex", insts_mem);
        $readmemh("golden_ofm.hex", golden_ofm_mem);

        // Fill mock DDR
        // ddr_mem.delete();
        for (int i = 0; i < 128; i++)   ddr_write(40'h1000_0000 + i, ifm_mem[i]);
        for (int i = 0; i < 12288; i++) ddr_write(40'h2000_0000 + i, wgt_mem[i]);
        for (int i = 0; i < 192; i++)   ddr_write(40'h2000_0000 + 12288 + i, bias_mem[i]);

        #100;
        rst_n = 1;
        #100;

        $display("==================================================");
        $display("   STARTING STANDALONE FC LAYER TEST              ");
        $display("==================================================");

        // Program PEA config registers (0x100-0x128) via AXI-Lite.
        // Bat buoc: pea_top chi nhan config qua AXI-Lite truc tiep; instruction
        // stream khong nap cac thanh ghi nay. Thieu buoc nay -> config = 0 ->
        // warmup_threshold = 0 -> FSM treo o WARM_UP.
        $display("[+] Sending PEA configuration via AXI-Lite (FC 120->84)...");
        axi_lite_write(32'h0100, IFM_W);       // ifm_width
        axi_lite_write(32'h0104, IFM_H);       // ifm_height
        axi_lite_write(32'h0108, C_IN);        // channels_in
        axi_lite_write(32'h010C, C_OUT);       // channels_out
        axi_lite_write(32'h0110, K_SIZE);      // kernel_size
        axi_lite_write(32'h0114, RIGHT_SHIFT); // right_shift
        axi_lite_write(32'h0120, 0);           // weight base (SRAM word)
        axi_lite_write(32'h0124, BIAS_BASE);   // bias base (SRAM word)
        axi_lite_write(32'h0128, RELU_EN);     // relu enable

        // Upload microcode (8 passes)
        $display("[+] Uploading microcode...");
        upload_microcode("microcode.hex", 8);

        // Send instructions
        $display("[+] Sending hardware instructions to FIFO...");
        for (int i = 0; i < 10; i++) begin
            send_instruction(insts_mem[i]);
        end

        // Wait for execution to finish
        $display("[+] Waiting for TPU execution to complete...");
        wait(finish_irq_o);
        #100;

        // Display outputs and compare
        $display("==================================================");
        $display("   COMPARING OUTPUT FEATURE MAPS WITH GOLDEN      ");
        $display("==================================================");
        begin
            int mismatches;
            logic [7:0] hw_val;
            logic [7:0] golden_val;
            int unsigned oidx;
            mismatches = 0;
            for (int i = 0; i < C_OUT; i++) begin
                oidx = ddr_idx(40'h3000_0000 + i);
                hw_val = ddr_mem[oidx];
                golden_val = golden_ofm_mem[i];
                $display("  Out[%0d]: HW = %0d, Golden = %0d", i, $signed(hw_val), $signed(golden_val));
                if (hw_val !== golden_val) begin
                    mismatches++;
                end
            end
            
            $display("==================================================");
            if (mismatches == 0) begin
                $display("   [PASS] Standalone FC Layer matched Golden 100%%!");
            end else begin
                $display("   [FAIL] Standalone FC Layer has %0d mismatches!", mismatches);
            end
            $display("==================================================");
        end
        $finish;
    end

endmodule
