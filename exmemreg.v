module exmemreg(
    // 基础控制信号
    input         clk,                  // 时钟
    input         rst_n,                // 异步复位（低电平有效）
    
    // 来自执行阶段（EX）的数据
    input  [31:0] result_i,             // ALU计算结果（所有指令）
    input  [31:0] result_address_i,     // 访存地址（仅Load指令有效）
    input  [4:0]  rd_i,                 // 目标寄存器编号
    input         wb_en_i,              // 写回使能（来自控制单元）
    input         read_en_i,            // Load指令标志（1=Load，0=其他）
    input  [2:0]  mem_op_i,
    // 传递到访存阶段（MEM）的信号
    output        wb_en_o,              // 写回使能
    output [31:0] result_o,             // ALU结果或待写回数据
    output        read_en_o,            // Load指令标志
    output [31:0] result_address_o,     // 访存地址（仅Load有效）
    output [4:0]  rd_o,                  // 目标寄存器编号
    output [4:0]  mem_op_o
);

// ===== 寄存器声明 =====
reg [31:0] result_reg;           // ALU结果寄存器
reg [31:0] result_address_reg;   // 访存地址寄存器
reg [4:0]  rd_reg;               // 目标寄存器编号寄存器
reg        wb_en_reg;            // 写回使能寄存器
reg        read_en_reg;          // Load指令标志寄存器
reg [2:0]  mem_op_reg;

// ===== 时序逻辑 =====
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        // 异步复位：清空所有寄存器
        result_reg         <= 32'h0;
        result_address_reg <= 32'h0;
        rd_reg             <= 5'h0;
        wb_en_reg          <= 1'b0;
        read_en_reg        <= 1'b0;
        mem_op_reg         <= 3'b0;
    end
    else begin
        // 时钟上升沿锁存输入信号
        result_reg         <= result_i;
        result_address_reg <= (read_en_i) ? result_address_i : 32'h0; // 仅Load指令保存地址
        rd_reg             <= rd_i;
        wb_en_reg          <= wb_en_i;
        read_en_reg        <= read_en_i;
        mem_op_reg         <= mem_op_i;
    end
end

// ===== 输出赋值 =====
assign result_o         = result_reg;
assign result_address_o = (read_en_reg) ? result_address_reg : 32'h0; // 非Load指令输出0
assign rd_o             = rd_reg;
assign wb_en_o          = wb_en_reg;
assign read_en_o        = read_en_reg;
assign mem_op_o         = mem_op_reg;

endmodule