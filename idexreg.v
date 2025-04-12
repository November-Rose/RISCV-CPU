module idexreg(
    input clk,
    input rst_n,
    input checkpre_flush,
    input feedforward_stall,

    input [31:0] regbag_data1,
    input [31:0] regbag_data2,
    input en1_i,
    input en2_i,
    input decoder_en1_i,
    input decoder_en2_i,
    input [31:0] imm_i,
    input imm_en_i,
    input [4:0] rd_i,
    input rd_en_i,
    input [6:0] op_i,
    input [7:0] funct7_i,
    input [2:0] funct3_i,
    input [4:0] mem_op_i,
    input jump_en_i,
    input [31:0] pc_i,

    output [6:0] op_o,
    output [7:0] funct7_o,
    output [2:0] funct3_o,
    output [4:0] rd_o,
    output rd_en_o,
    output [31:0] imm_o,
    output imm_en_o,
    output [31:0] data1_o,
    output en1_o,
    output [31:0] data2_o,
    output en2_o,
    output [4:0] mem_op_o,
    output jump_en_o,
    output [31:0] pc_o
);

// 流水线寄存器（包含所有需要通过流水级的信号）
reg [31:0] data1_reg;
reg [31:0] data2_reg;
reg en1_reg;
reg en2_reg;
reg [31:0] imm_reg;
reg imm_en_reg;
reg [4:0] rd_reg;
reg rd_en_reg;
reg [6:0] op_reg;
reg [7:0] funct7_reg;
reg [2:0] funct3_reg;
reg [4:0] mem_op_reg;
reg jump_en_reg;
reg [31:0] pc_reg;

//==============================
// 流水线控制逻辑（优先级：冲刷 > 阻塞 > 正常传输）
//==============================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        // 异步复位：清空流水线（输出NOP指令对应的控制信号）
        data1_reg <= 32'h0;
        data2_reg <= 32'h0;
        en1_reg <= 1'b0;
        en2_reg <= 1'b0;
        imm_reg <= 32'h0;
        imm_en_reg <= 1'b0;
        rd_reg <= 5'h0;
        rd_en_reg <= 1'b0;
        op_reg <= 7'b0010011; // ADDI操作码
        funct7_reg <= 8'h0;
        funct3_reg <= 3'b0;
        mem_op_reg <= 5'h0;
        jump_en_reg <= 1'b0;
        pc_reg <= 32'h0;
    end
    else begin
        casez ({checkpre_flush, feedforward_stall})
            2'b1?: begin  // 冲刷优先（插入气泡）
                data1_reg <= 32'h0;
                data2_reg <= 32'h0;
                en1_reg <= 1'b0;
                en2_reg <= 1'b0;
                imm_reg <= 32'h0;
                imm_en_reg <= 1'b0;
                rd_reg <= 5'h0;
                rd_en_reg <= 1'b0;
                op_reg <= 7'b0010011; // ADDI操作码（NOP）
                funct7_reg <= 8'h0;
                funct3_reg <= 3'b0;
                mem_op_reg <= 5'h0;
                jump_en_reg <= 1'b0;
                pc_reg <= pc_i; // 保持PC值不变
            end
            2'b01: begin  // 保持当前状态（阻塞）
                // 所有寄存器保持不变
            end
            default: begin // 正常传输
                data1_reg <= regbag_data1;
                data2_reg <= regbag_data2;
                en1_reg <= decoder_en1_i & en1_i;
                en2_reg <= decoder_en2_i & en2_i;
                imm_reg <= imm_i;
                imm_en_reg <= imm_en_i;
                rd_reg <= rd_i;
                rd_en_reg <= rd_en_i;
                op_reg <= op_i;
                funct7_reg <= funct7_i;
                funct3_reg <= funct3_i;
                mem_op_reg <= mem_op_i;
                jump_en_reg <= jump_en_i;
                pc_reg <= pc_i;
            end
        endcase
    end
end

// 输出连接
assign op_o = op_reg;
assign funct7_o = funct7_reg;
assign funct3_o = funct3_reg;
assign rd_o = rd_reg;
assign rd_en_o = rd_en_reg;
assign imm_o = imm_reg;
assign imm_en_o = imm_en_reg;
assign data1_o = data1_reg;
assign en1_o = en1_reg;
assign data2_o = data2_reg;
assign en2_o = en2_reg;
assign mem_op_o = mem_op_reg;
assign jump_en_o = jump_en_reg;
assign pc_o = pc_reg;

//==============================
// 设计要点说明
//==============================
// 1. 控制信号优先级：
//    - flush > stall > normal
//    - 与大多数RISC流水线控制策略一致
//
// 2. 复位策略：
//    - 异步复位同步释放（建议在顶层统一处理同步释放）
//    - 复位值为NOP指令对应的控制信号
//
// 3. 时序优化：
//    - 所有输出直接寄存器驱动，无组合逻辑延迟
//    - 所有控制信号都同步到时钟上升沿
//
// 4. 特殊处理：
//    - 冲刷时保持PC值不变，便于调试和异常处理
//    - 使能信号(en1/en2)是源寄存器使能和译码器使能的与结果
endmodule