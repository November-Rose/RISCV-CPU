module exmemreg(
    // 基础控制信号
    input         clk,          // 时钟
    input         rst_n,        // 异步复位（低电平有效）
    input         stall,
    input         s_flag_i,
    
    // 来自执行阶段（EX）的数据
    input  [31:0] result_i,     // ALU计算结果
    input  [4:0]  rd_i,         // 目标寄存器编号
    input         wb_en_i,      // 写回使能
    input         read_en_i,
    input         update_en_i,
    input         brunch_taken_i,
    
    // 传递到访存阶段（MEM）的信号
    output        wb_en_o,      // 写回使能
    output [31:0] result_o,    // ALU结果
    output [4:0]  rd_o,          // 目标寄存器编号
    output        read_en_o,
    output         update_en_o,
    output         brunch_taken_o,
    output         s_flag_o
);

// ===== 寄存器声明 =====
reg [31:0] result_reg;    // ALU结果寄存器
reg [4:0]  rd_reg;        // 目标寄存器编号寄存器
reg        wb_en_reg;     // 写回使能寄存器
reg        read_en_reg;
reg        update_en_reg;
reg        brunch_taken_reg;
reg        s_flag_reg;
// ===== 时序逻辑 =====
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        // 异步复位：清空所有寄存器
        result_reg <= 32'h0;
        rd_reg     <= 5'h0;
        wb_en_reg  <= 1'b0;
        read_en_reg<= 1'b0;
        update_en_reg<= 1'b0;
        brunch_taken_reg<= 1'b0;
        s_flag_reg<=1'b0;
    end
    else begin
        // 时钟上升沿锁存输入信号
        result_reg <= result_i;
        rd_reg     <= rd_i;
        wb_en_reg  <= wb_en_i;
        read_en_reg<=read_en_i;
        update_en_reg<=update_en_i;
        brunch_taken_reg<=brunch_taken_i;
        s_flag_reg<=s_flag_i||stall;
    end
end

// ===== 输出赋值 =====
assign result_o = result_reg;
assign rd_o     = rd_reg;
assign wb_en_o  = wb_en_reg;
assign read_en_o= read_en_reg;
assign update_en_o=update_en_reg;
assign brunch_taken_o=brunch_taken_reg;
assign s_flag_o=s_flag_reg;
endmodule