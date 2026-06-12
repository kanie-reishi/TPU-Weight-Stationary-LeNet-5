`timescale 1ns / 1ps

module tb_sram_banked_5x;

    parameter DWIDTH = 32; // Thu nhỏ lại 32-bit cho dễ debug
    parameter AWIDTH = 4;

    logic clk;
    
    logic [4:0]              ena_i;
    logic [4:0]              wea_i;
    logic [AWIDTH-1:0]       addra_i [0:4];
    logic [DWIDTH-1:0]       dina_i [0:4];
    logic [DWIDTH-1:0]       douta_o [0:4];
    
    logic [4:0]              enb_i;
    logic [4:0]              web_i;
    logic [AWIDTH-1:0]       addrb_i [0:4];
    logic [DWIDTH-1:0]       dinb_i [0:4];
    logic [DWIDTH-1:0]       doutb_o [0:4];

    sram_banked_5x #(
        .DWIDTH(DWIDTH),
        .AWIDTH(AWIDTH)
    ) dut (
        .clk(clk),
        .ena_i(ena_i), .wea_i(wea_i), .addra_i(addra_i), .dina_i(dina_i), .douta_o(douta_o),
        .enb_i(enb_i), .web_i(web_i), .addrb_i(addrb_i), .dinb_i(dinb_i), .doutb_o(doutb_o)
    );

    always #5 clk = ~clk;

    initial begin
        clk = 0;
        ena_i = '0; wea_i = '0; enb_i = '0; web_i = '0;
        for (int i=0; i<5; i++) begin
            addra_i[i] = '0; dina_i[i] = '0;
            addrb_i[i] = '0; dinb_i[i] = '0;
        end
        #15;

        $display("=== STARTING PARALLEL WRITE ===");
        // Write to all 5 banks on Port A simultaneously
        ena_i = 5'b11111;
        wea_i = 5'b11111;
        for (int i=0; i<5; i++) begin
            addra_i[i] = i; // Bank0 ghi địa chỉ 0, Bank1 ghi 1...
            dina_i[i]  = 32'hA000_0000 + i;
        end
        #10;
        
        wea_i = '0;
        ena_i = '0;
        #10;

        $display("=== STARTING PARALLEL READ ===");
        // Read from all 5 banks on Port B simultaneously
        enb_i = 5'b11111;
        for (int i=0; i<5; i++) begin
            addrb_i[i] = i;
        end
        
        #10; // Wait 1 cycle for SRAM read latency
        
        for (int i=0; i<5; i++) begin
            if (doutb_o[i] !== 32'hA000_0000 + i) begin
                $display("ERROR: Bank %0d Read Data Mismatch. Expected %h, Got %h", i, 32'hA000_0000 + i, doutb_o[i]);
                $finish;
            end else begin
                $display("Bank %0d OK: Got %h", i, doutb_o[i]);
            end
        end

        $display("SUCCESS: 5-Bank parallel write/read passed!");
        $finish;
    end
endmodule
