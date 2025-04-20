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
    input         rst_n,        // 异步复位
    input  [31:0] instr_addr,   // 字节地址
    output [31:0] instr_data    // 指令输出
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
    input [31:0] instr_addr_i,
    output [31:0] decoder_instr,
    output [31:0] instr_addr_o
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
endmodule


// ====================== ex ======================
module ex (
    input clk,//仅仅为了串行存储rd，不会打破流水线时序
    input rst_n,
    input en1,
    input en2,
    input imm_en,
    input rd_en,
    input [4:0] rd,
    input [4:0] rs1,
    input [4:0] rs2,
    input [31:0] imm,
    input [31:0] data1,
    input [31:0] data2,
    input [4:0] mem_op,
    input jump_en,
    input [6:0] op,
    input [7:0] funct7,
    input [2:0] funct3,
    input [31:0] exdata,
    input [31:0] memdata,
    input [31:0] pc,//这条指令的pc
    input [31:0] nextpc,//下条指令的pc

    output [31:0] exresult,
    output [31:0] result_address,
    output stall,
    output flush,
    output [31:0] correctpc
);
endmodule

module alu (
    input  [31:0] a,          // 操作数1（来自寄存器rs1）
    input  [31:0] b,          // 操作数2（来自寄存器rs2或立即数imm）
    input  [3:0]  alu_op,     // ALU操作码（由控制器生成）
    output reg [31:0] result, // 运算结果
    output zero               // 结果是否为0（用于分支指令判断）
);
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
    input [6:0] opcode,//用于分支指令
    input [31:0] pc,
    //input [2:0] func3,
    input [4:0] decode_rd,
    input [4:0] rd_en,
    input [31:0] exdata,
    input [31:0] memdata,

    output stall,
    output [31:0] op1,
    output [31:0] op2
    //output [4:0]alu_op
);
endmodule


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
    
    // 传递到访存阶段（MEM）的信号
    output        wb_en_o,              // 写回使能
    output [31:0] result_o,             // ALU结果或待写回数据
    output        read_en_o,            // Load指令标志
    output [31:0] result_address_o,     // 访存地址（仅Load有效）
    output [4:0]  rd_o                  // 目标寄存器编号
);
endmodule

module memwbreg(
    // 基础控制信号
    input         clk,              // 时钟
    input         rst_n,            // 异步复位（低电平有效）
    
    // 来自访存阶段（MEM）的输入
    input         wb_en,            // 写回使能（控制是否写回寄存器堆）
    input  [4:0]  rd,               // 目标寄存器编号
    input  [31:0] result,           // 待写回的数据（来自ALU或存储器）
    
    // 传递到写回阶段（WB）的输出
    output [31:0] regbag_w_data,    // 写入寄存器堆的数据
    output [4:0]  regbag_w_addr,    // 写入寄存器堆的地址
    output        regbag_w_en       // 寄存器堆写使能
);
endmodule








