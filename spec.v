module cputop(
    input clk,
    input rst_n,
    output [31:0] instrmem_instr_addr,
    input [31:0] instrmem_instr_data,
    output datamem_r_en,
    input [31:0] datamem_datar,
    output datamem_w_en,
    output [31:0] datamem_dataw
);
endmodule



module regbag (
    //========== 时钟与复位 ==========//
    input         clk,       // 全局时钟（上升沿触发）
    input         rst_n,     // 异步低电平复位（0复位，1正常工作）
    
    //========== 读端口1 ==========//
    input         decoder_r_en1,     // 读使能信号1（1有效）
    input  [4:0]  decoder_r_addr1,   // 读地址1（0-31对应x0-x31）
    output [31:0] idexreg_r_data1,   // 读数据1输出（组合逻辑输出）
    
    //========== 读端口2 ==========//
    input         decoder_r_en2,     // 读使能信号2（1有效）
    input  [4:0]  decoder_r_addr2,   // 读地址2（0-31对应x0-x31）
    output [31:0] idexreg_r_data2,   // 读数据2输出（组合逻辑输出）
    
    //========== 写端口 ==========//
    input         wb_w_en,      // 写使能信号（1有效，上升沿写入）
    input  [4:0]  wb_w_addr,   // 写地址（0-31对应x0-x31）
    input  [31:0] wb_w_data     // 写数据（32位）

);
endmodule

module instrmem(
    input clk,
    input rst_n,
    input [31:0] instr_addr,
    output [31:0] instr_data
);
endmodule

module pc (
    //========== 时钟与复位 ==========//
    input         clk,        // 全局时钟（上升沿触发）
    input         rst_n,      // 异步低电平复位（0复位，1正常工作）
    
    //========== 分支预测接口 ==========//
    input         pred_f_en,       // 分支预测使能（1表示预测跳转）
    input  [31:0] pred_f_addr,     // 预测跳转地址（来自分支预测器）
    
    //========== 流水线控制 ==========//
    input         checkpre_flush,      // 冲刷信号（分支预测错误时置1）
    input         feedforward_stall,   // 阻塞信号（数据冲突时置1）
    
    //========== 输出 ==========//
    output reg [31:0] instrmem_addr    // 当前PC值（按4字节对齐，addr[1:0]=00）
);
endmodule


module ifidreg(
    input clk,
    input rst_n,
    input [31:0] instrmem_instr_data,
    input checkpre_flush,
    input feedforward_stall,
    output [31:0] decoder_instr
);
endmodule


// ====================== 译码器 (decoder) ======================
module decoder (
    //========== 输入 ==========//
    input  [31:0] instr,         // 来自IF/ID寄存器的指令
    //input  [31:0] instr_addr_i,  // 当前指令地址（用于PC相对计算）我认为应该是在checkpre里面用此条指令的上一条指令的addr来比较
    
    //========== 输出到ID/EX ==========//
    output [31:0] imm,           // 解码出的立即数（符号扩展后）
    output        imm_en,        // 立即数使用使能
    output [6:0]  op,            // 操作码（instr[6:0]）
    output [7:0]  funct7,        // 功能码高7位（含1位备用）
    output [2:0]  funct3,        // 功能码低3位
    output [4:0]  rd_addr,       // 目标寄存器地址
    output        rd_en,         // 目标寄存器写使能
    //output [31:0] instr_addr_o,  // 传递指令地址（用于JALR等）
    output [4:0]  mem_op,        // 内存操作类型（LB/LH/LW/LBU/LHU/SB/SH/SW）,低3位位datamem里面的op，高2位位r_en和w_enw_en
    output        jump_en,       // 跳转指令使能
    
    //========== 输出到RegBag ==========//
    output [4:0]  rs1_addr,      // 源寄存器1地址
    output        rs1_en,        // 源寄存器1读使能
    output [4:0]  rs2_addr,      // 源寄存器2地址
    output        rs2_en         // 源寄存器2读使能
);
endmodule

module idexreg(
    input clk,
    input rst_n,
    input checkpre_flush,
    input feedforward_stall,
    input [31:0] regbag_data1,
    input [31:0] regbag_data2,
    input decoder_en1,
    input decoder_en2,
    input [31:0] imm,
    input imm_en,
    input [4:0] rd,
    input rd_en,
    input [6:0] op,
    input [7:0] funct7,
    input [2:0] funct3,

    output [6:0] op,
    output [7:0] funct7,
    output [2:0] funct3,
    output [4:0] rd,
    output rd_en,
    output [31:0] imm,
    output imm_en,
    output [31:0] data1,
    output en1,
    output [31:0] data2,
    output en2
);
endmodule


// ====================== ex ======================
module ex (
    input en1,
    input en2,
    input imm_en,
    input [31:0] imm,
    input [31:0] rs1,
    input [31:0] rs2,
    input [4:0] rd_i,
    input rd_en,
    input [6:0] op,
    input [7:0] funct7,
    input [2:0] funct3,
    output [31:0] result,
    output [31:0] result_address,//若需要存入数据存储器
    output [4:0] rd_o,
);
endmodule
module alu (
    input  [31:0] a,          // 操作数1（rs1）
    input  [31:0] b,          // 操作数2（rs2 或立即数）
    input  [3:0]  alu_op,     // ALU操作码（由控制器生成）
    output reg [31:0] result, // 运算结果
    output zero               // 结果是否为0（用于分支判断）
);

    // ALU操作码定义（与控制器对应）
    localparam OP_ADD  = 4'b0000;
    localparam OP_SUB  = 4'b0001;
    localparam OP_SLL  = 4'b0010;
    localparam OP_SLT  = 4'b0011;
    localparam OP_SLTU = 4'b0100;
    localparam OP_XOR  = 4'b0101;
    localparam OP_SRL  = 4'b0110;
    localparam OP_SRA  = 4'b0111;
    localparam OP_OR   = 4'b1000;
    localparam OP_AND  = 4'b1001;

    // 移位量（仅取b的低5位，RISC-V规范）
    wire [4:0] shamt = b[4:0];

    always @(*) begin
        case (alu_op)
            OP_ADD:  result = a + b;                    // ADD/ADDI
            OP_SUB:  result = a - b;                    // SUB
            OP_SLL:  result = a << shamt;               // SLL/SLLI
            OP_SLT:  result = ($signed(a) < $signed(b)) ? 32'd1 : 32'd0; // SLT/SLTI
            OP_SLTU: result = (a < b) ? 32'd1 : 32'd0;  // SLTU/SLTIU
            OP_XOR:  result = a ^ b;                    // XOR/XORI
            OP_SRL:  result = a >> shamt;               // SRL/SRLI
            OP_SRA:  result = $signed(a) >>> shamt;      // SRA/SRAI
            OP_OR:   result = a | b;                    // OR/ORI
            OP_AND:  result = a & b;                    // AND/ANDI
            default: result = 32'b0;                    // 默认值
        endcase
    end

    // 判断结果是否为0（用于BEQ/BNE等分支指令）
    assign zero = (result == 32'b0);

endmodule



module feedforward(//含选择op1与op2，op1与op2直接接入alu
    input clk,  //时钟脉冲
    input rst_n,
    input [4:0] rs1,
    input [4:0] rs2,
    input [31:0] imm,
    input [31:0] data1,
    input [31:0] data2,
    input rs1_en,
    input rs2_en,
    input imm_en,
    //input jump_en,
    input load,//wire load=mem_op[3];
    //input [6:0] opcode,
    input [4:0] decode_rd,
    input [31:0] exdata,
    input [31:0] memdata,

    output stall,
    output [31:0] op1,
    output [31:0] op2,
    //output [4:0]alu_op
);
endmodule


module exmemreg(
    input clk,
    input rst_n,
    input [31:0] ex_result,
    input [3:0] sel,
    input [4:0] rd,
    output read_en,
    output write_en,
    output wb_en,
    output [31:0] result,
    output [31:0] result_address,
    output [4:0] rd
);
endmodule

module memwbreg(
    input clk,
    input rst_n,
    input wb_en,//rd_en
    input [4:0] rd,
    input [31:0] datamem_dataout,
    input [31:0] result_address,
    output [31:0] regbag_w_data,
    output [4:0] regbag_w_addr,
    output regbag_w_en
);
endmodule

module predecode(
    input 
);
endmodule

module pred(
    input predecode_en,
    input predecode_addr,
    output pc_jumpen,
    output pc_jumpaddr
);
endmodule






