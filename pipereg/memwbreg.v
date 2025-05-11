module memwbreg(
    // 基础控制信号
    input         clk,              // 时钟
    input         rst_n,            // 异步复位（低电平有效）
    input         s_flag_i,
    
    // 来自访存阶段（MEM）的输入
    input         wb_en,            // 写回使能（控制是否写回寄存器堆）
    input  [4:0]  rd,               // 目标寄存器编号
    input  [31:0] result,           // 待写回的数据（来自ALU或存储器）
    
    // 传递到写回阶段（WB）的输出
    output [31:0] regbag_w_data,    // 写入寄存器堆的数据
    output [4:0]  regbag_w_addr,    // 写入寄存器堆的地址
    output        regbag_w_en,       // 寄存器堆写使能
    output        s_flag_o
);

// ===== 寄存器声明 =====
reg [31:0] result_reg;    // 数据寄存器
reg [4:0]  rd_reg;        // 目标寄存器编号寄存器
reg        wb_en_reg;     // 写回使能寄存器
reg        s_flag_reg;
// ===== 时序逻辑（时钟驱动） =====
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        // 异步复位：清空所有寄存器
        result_reg <= 32'h0;
        rd_reg     <= 5'h0;
        wb_en_reg  <= 1'b0;
        s_flag_reg <= 1'b1;
    end
    else begin
        // 时钟上升沿锁存输入信号
        result_reg <= result;
        rd_reg     <= rd;
        wb_en_reg  <= wb_en&&~s_flag_i;
        s_flag_reg <= s_flag_i;
    end
end

// ===== 输出赋值 =====
assign regbag_w_data = result_reg;  // 直接传递数据
assign regbag_w_addr = rd_reg;      // 直接传递目标寄存器地址
assign regbag_w_en   = wb_en_reg;   // 直接传递写使能
assign s_flag_o=s_flag_reg;
endmodule