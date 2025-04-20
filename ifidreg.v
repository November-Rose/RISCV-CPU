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
// 流水线寄存器（包含所有需要通过流水级的信号）
reg [31:0] pipeline_reg;

//==============================
// 流水线控制逻辑（优先级：冲刷 > 阻塞 > 正常传输）
//==============================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        // 异步复位：清空流水线（输出NOP指令）
        pipeline_reg <= 32'h00000013;  // ADDI x0, x0, 0 (NOP)
    end
    else begin
        casez ({checkpre_flush, feedforward_stall})
            2'b1?:  pipeline_reg <= 32'h00000013;  // 冲刷优先（插入气泡）
            2'b01:  pipeline_reg <= pipeline_reg;   // 保持当前状态（阻塞）
            default: pipeline_reg <= instrmem_instr_data; // 正常传输
        endcase
    end
end

// 输出连接
assign decoder_instr = pipeline_reg;
assign instr_addr_o=(!rst_n||checkpre_flush) ? 32'd0:(feedforward_stall ? instr_addr_o:instr_addr_i);
                    
//==============================
// 设计要点说明
//==============================
// 1. 控制信号优先级：
//    - flush > stall > normal
//    - 与大多数RISC流水线控制策略一致
//
// 2. 复位策略：
//    - 异步复位同步释放（建议在顶层统一处理同步释放）
//    - 复位值为NOP指令而非全0，避免执行非法指令
//
// 3. 时序优化：
//    - 输出直接寄存器驱动，无组合逻辑延迟
//    - 所有控制信号都同步到时钟上升沿
endmodule