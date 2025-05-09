module ifidreg(
    input clk,
    input rst_n,
    input [31:0] instrmem_instr_data,
    input checkpre_flush,
    input feedforward_stall,
    input [31:0] instr_addr_i,
    output [31:0] decoder_instr,
    output [31:0] instr_addr_o
);
    // 流水线寄存器（包含指令和地址）
    reg [31:0] pipeline_reg;
    reg [31:0] addr_reg;  // 新增地址寄存器

    //==============================
    // 流水线控制逻辑（优先级：冲刷 > 阻塞 > 正常传输）
    //==============================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // 异步复位：清空流水线（输出NOP指令和0地址）
            pipeline_reg <= 32'h00000013;  // ADDI x0, x0, 0 (NOP)
            addr_reg <= 32'd0;
        end
        else begin
            casez ({checkpre_flush, feedforward_stall})
                2'b1?: begin
                    // 冲刷优先（插入气泡）
                    pipeline_reg <= 32'h00000013;
                    addr_reg <= 32'd0;
                end
                2'b01: begin
                    // 保持当前状态（阻塞）
                    // 两个寄存器都保持原值
                end
                default: begin
                    // 正常传输
                    pipeline_reg <= instrmem_instr_data;
                    addr_reg <= instr_addr_i;
                end
            endcase
        end
    end

    // 输出连接
    assign decoder_instr = pipeline_reg;
    assign instr_addr_o = addr_reg;  // 直接使用寄存器输出
endmodule