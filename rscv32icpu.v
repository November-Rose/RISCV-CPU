module cputop(
    input clk,
    input rst_n,
    output [31:0] instrmem_instr_addr,
    input [31:0] instrmem_instr_data,
    output datamem_r_en,
    input [31:0] datamem_datar,
    output datamem_w_en,
    output [31:0] datamem_dataw
)；
endmodule

module data_mem (
    //========== 时钟与复位 ==========//
    input         clk,          // 时钟信号
    input         rst_n,        // 异步低电平复位
    //========== 存储器控制 ==========//
    input         read_en,      // 异步读使能
    input  [2:0]  mem_op,      // 内存操作类型（见下方编码）
    input         write_en,    // 同步写使能（上升沿触发）
    //========== 数据接口 ==========//
    input  [31:0] datain,      // 写入数据
    input  [31:0] address,     // 字节地址
    output [31:0] dataout      // 读取数据（带符号扩展）
);

    // ================= 存储器参数 =================
    parameter MEM_SIZE_KB = 4;                   // 默认4KB数据存储器
    localparam MEM_DEPTH = MEM_SIZE_KB * 1024;    // 总字节容量
    localparam ADDR_WIDTH = $clog2(MEM_DEPTH);    // 地址线宽度

    // ================= 操作类型编码 =================
    // Load操作 [2:0]:
    localparam LB   = 3'b000;  // 加载字节（有符号扩展）
    localparam LH   = 3'b001;  // 加载半字（有符号扩展）
    localparam LW   = 3'b010;  // 加载字
    localparam LBU  = 3'b100;  // 加载字节（无符号扩展）
    localparam LHU  = 3'b101;  // 加载半字（无符号扩展）
    // Store操作 [2:0]:
    localparam SB   = 3'b000;  // 存储字节
    localparam SH   = 3'b001;  // 存储半字
    localparam SW   = 3'b010;  // 存储字

    // ================= 存储器实现 =================
    reg [7:0] mem [0:MEM_DEPTH-1];  // 按字节组织的存储器

    // ================= 写入逻辑（同步） =================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // 复位时不操作
        end 
        else if (write_en && address < MEM_DEPTH) begin
            case (mem_op)
                SB: begin  // 存储字节（datain[7:0]）
                    mem[address] <= datain[7:0];
                end
                SH: begin  // 存储半字（datain[15:0]，地址需2字节对齐）
                    if (address[0] == 0) begin
                        mem[address]   <= datain[7:0];
                        mem[address+1] <= datain[15:8];
                    end
                end
                SW: begin  // 存储字（datain[31:0]，地址需4字节对齐）
                    if (address[1:0] == 0) begin
                        mem[address]   <= datain[7:0];
                        mem[address+1] <= datain[15:8];
                        mem[address+2] <= datain[23:16];
                        mem[address+3] <= datain[31:24];
                    end
                end
                default: ;  // 其他操作不写入
            endcase
        end
    end

    // ================= 读取逻辑（异步） =================
    wire [31:0] raw_data;  // 原始读取数据（未扩展）
    assign raw_data = (!rst_n || !read_en) ? 32'b0 :
                     (address >= MEM_DEPTH-3) ? 32'b0 :
                     {mem[address+3], mem[address+2],
                      mem[address+1], mem[address]};

    // 根据mem_op进行符号扩展或截断
    reg [31:0] read_data;
    always @(*) begin
        case (mem_op)
            LB:  begin  // 有符号字节扩展
                read_data = {{24{raw_data[7]}},  raw_data[7:0]};
            end
            LH:  begin  // 有符号半字扩展
                read_data = {{16{raw_data[15]}}, raw_data[15:0]};
            end
            LW:  begin  // 读取完整字
                read_data = raw_data;
            end
            LBU: begin  // 无符号字节扩展
                read_data = {24'b0, raw_data[7:0]};
            end
            LHU: begin  // 无符号半字扩展
                read_data = {16'b0, raw_data[15:0]};
            end
            default: read_data = raw_data;  // 默认按字读取
        endcase
    end

    assign dataout = read_data;

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

// 寄存器堆声明（x0始终为0）
reg [31:0] register [1:31];  // x1-x31可写，x0硬连线为0

//==============================
// 写操作（同步时序逻辑）
//==============================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        // 异步复位（所有寄存器清零）
        for (integer i = 1; i < 32; i = i + 1) begin
            register[i] <= 32'b0;
        end
    end
    else if (wb_w_en && (wb_w_addr != 5'b0)) begin
        // 同步写入（x0地址不写入）
        register[wb_w_addr] <= wb_w_data;
    end
end

//==============================
// 读端口1（组合逻辑）
//==============================
assign idexreg_r_data1 = (!decoder_r_en1) ? 32'b0 :          // 读使能关闭时输出0
                         (decoder_r_addr1 == 5'b0) ? 32'b0 :  // x0始终返回0
                         register[decoder_r_addr1];            // 正常读取

//==============================
// 读端口2（组合逻辑）
//==============================
assign idexreg_r_data2 = (!decoder_r_en2) ? 32'b0 :          // 读使能关闭时输出0
                         (decoder_r_addr2 == 5'b0) ? 32'b0 :  // x0始终返回0
                         register[decoder_r_addr2];            // 正常读取


endmodule

module instrmem(
    input         rst_n,        // 异步复位
    input  [31:0] instr_addr,   // 字节地址
    output [31:0] instr_data    // 指令输出
);

// ===== 存储器参数 =====
parameter MEM_DEPTH = 64;       // 64条指令（256字节）
localparam ADDR_WIDTH = $clog2(MEM_DEPTH);

// ===== 存储器声明 =====
reg [31:0] mem [0:MEM_DEPTH-1];

// ===== 存储器初始化（纯组合逻辑）=====
always @(*) begin
    // 默认填充NOP指令（确保未初始化地址返回安全值）
    if(!rst_n)
    begin
    for (integer i = 0; i < MEM_DEPTH; i = i + 1) begin
        mem[i] = 32'h00000013; // ADDI x0, x0, 0 (NOP)
    end
    end

    else begin

    // ===== 冒泡排序程序（RV32I汇编） =====
    // 假设数组首地址在x10，长度在x11
    mem[0]  = 32'h00A00513;   // li a0, 10       (数组长度=10)
    mem[1]  = 32'h06400593;   // li a1, 100      (数组首地址=0x64)
    mem[2]  = 32'hFFA50613;   // addi a2, a0, -1 (n-1 -> 外循环计数器)
    
    // Outer loop (i)
    mem[3]  = 32'h06060463;   // beqz a2, end    (if i==0 -> end)
    mem[4]  = 32'h00050693;   // mv a3, a0       (内循环计数器j)
    mem[5]  = 32'h00168693;   // addi a3, a3, -1 (j--)
    
    // Inner loop (j)
    mem[6]  = 32'h06068063;   // beqz a3, outer_end (if j==0 -> outer_end)
    mem[7]  = 32'h0006A703;   // lw a4, 0(a3)     (load arr[j])
    mem[8]  = 32'h0046A783;   // lw a5, 4(a3)     (load arr[j+1])
    mem[9]  = 32'h00F75863;   // bge a4, a5, no_swap (if arr[j] <= arr[j+1])
    mem[10] = 32'h00E7A023;   // sw a4, 0(a5)     (swap)
    mem[11] = 32'h00F6A223;   // sw a5, 4(a3)     (swap)
    
    // Loop control
    mem[12] = 32'hFFC68693;   // addi a3, a3, -4 (j--)
    mem[13] = 32'hFE1FF06F;   // j inner_loop
    mem[14] = 32'hFFC60613;   // addi a2, a2, -1 (i--)
    mem[15] = 32'hFDFFF06F;   // j outer_loop
    mem[16] = 32'h00000013;   // end: nop
    end
end

// ===== 地址转换与输出 =====
wire [ADDR_WIDTH-1:0] word_addr = instr_addr[ADDR_WIDTH+1:2]; // 字节地址转字地址
assign instr_data = (~rst_n) ? 32'h00000013 :    // 复位时输出NOP
                   (word_addr >= MEM_DEPTH) ? 32'h00000013 : // 越界保护
                   mem[word_addr];                // 正常输出

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
)；
endmodule


module ifidreg(
    input clk,
    input rst_n,
    input checkpre_flush,
    input feedforward_stall,
    input [31:0] instrmem_instr_data,
    
    output [31:0] decoder_instr
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

    // ================= 字段提取 =================
    assign op      = instr[6:0];
    assign funct3  = instr[14:12];
    assign funct7  = {1'b0, instr[31:25]}; // 补零扩展到8位
    assign rd_addr = instr[11:7];
    assign rs1_addr= instr[19:15];
    assign rs2_addr= instr[24:20];
    assign instr_addr_o = instr_addr_i;  // 直传指令地址

    // ================= 立即数生成 =================
    wire [31:0] i_imm = {{20{instr[31]}}, instr[31:20]};                    // I-type
    wire [31:0] s_imm = {{20{instr[31]}}, instr[31:25], instr[11:7]};       // S-type
    wire [31:0] b_imm = {{20{instr[31]}}, instr[7], instr[30:25], instr[11:8], 1'b0}; // B-type
    wire [31:0] u_imm = {instr[31:12], 12'b0};                              // U-type
    wire [31:0] j_imm = {{12{instr[31]}}, instr[19:12], instr[20], instr[30:21], 1'b0}; // J-type

    // ================= 指令类型判断 =================
    wire is_rtype = (op == 7'b0110011); // ADD/SUB等
    wire is_itype = (op == 7'b0010011) || // ADDI等
                    (op == 7'b0000011) || // LOAD
                    (op == 7'b1100111);   // JALR
    wire is_stype = (op == 7'b0100011);   // STORE
    wire is_btype = (op == 7'b1100011);   // Branch
    wire is_utype = (op == 7'b0110111) || // LUI
                    (op == 7'b0010111);    // AUIPC
    wire is_jtype = (op == 7'b1101111);   // JAL

    // ================= 输出控制逻辑 =================
    assign imm = is_itype ? i_imm :
                 is_stype ? s_imm :
                 is_btype ? b_imm :
                 is_utype ? u_imm :
                 is_jtype ? j_imm : 32'b0;
    assign jump_en = (op == 7'b1100111) || (op == 7'b1101111) || (op == 7'b1100011); // JALR/JAL/Branch
    assign imm_en  = is_itype || is_stype || is_btype || is_utype || is_jtype;
    assign rd_en   = !is_stype && !is_btype && (rd_addr != 5'b0); // STORE和BRANCH不写rd
    assign rs1_en  = !is_utype && !is_jtype && (rs1_addr != 5'b0); // LUI/AUIPC/JAL不用rs1
    assign rs2_en  = is_rtype || is_stype || is_btype; // 仅这三类指令需要rs2

    // ================= 内存操作类型（mem_op）生成 =================
    reg [2:0] mem_op_reg;
    reg load;
    reg store;
    always @(*) begin
        if (op == 7'b0000011) begin          // Load指令
            case (funct3)
                3'b000: mem_op_reg = 3'b000; // LB
                3'b001: mem_op_reg = 3'b001; // LH
                3'b010: mem_op_reg = 3'b010; // LW
                3'b100: mem_op_reg = 3'b100; // LBU
                3'b101: mem_op_reg = 3'b101; // LHU
                default: mem_op_reg = 3'b111; // 无效
            endcase
            load=1'd1;
        end
        else if (op == 7'b0100011) begin     // Store指令
            case (funct3)
                3'b000: mem_op_reg = 3'b000; // SB
                3'b001: mem_op_reg = 3'b001; // SH
                3'b010: mem_op_reg = 3'b010; // SW
                default: mem_op_reg = 3'b111; // 无效
            endcase
            store=1'd1;
        end
        else begin
            mem_op_reg = 3'b111;             // 非内存操作（默认值）
            load=1'd0;
            store=1'd0;
        end
    end
    //产生memop
    assign mem_op[2:0] = mem_op_reg;
    assign mem_op[3]=load//r_en
    assign mem_op[4]=store//w_en
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

    // ALU操作码定义（与alu模块一致）
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

    wire load = mem_op[3];
    wire [3:0] alu_op;
    wire [31:0] alu_result;
    wire [31:0] op1, op2;
    wire zero;
    wire result;
    assign exresult=result;
   // 根据opcode和funct生成alu_op的逻辑
always @(*) begin
    case (op)
        // R-type指令
        7'b0110011: begin
            case (funct3)
                3'b000: alu_op = (funct7[5] ? OP_SUB : OP_ADD);  // ADD/SUB
                3'b001: alu_op = OP_SLL;   // SLL
                3'b010: alu_op = OP_SLT;   // SLT (有符号)
                3'b011: alu_op = OP_SLTU;  // SLTU (无符号)
                3'b100: alu_op = OP_XOR;   // XOR
                3'b101: alu_op = (funct7[5] ? OP_SRA : OP_SRL);  // SRL/SRA
                3'b110: alu_op = OP_OR;    // OR
                3'b111: alu_op = OP_AND;   // AND
                default: alu_op = OP_ADD;
            endcase
        end
        
        // I-type算术指令
        7'b0010011: begin
            case (funct3)
                3'b000: alu_op = OP_ADD;   // ADDI
                3'b001: alu_op = OP_SLL;   // SLLI
                3'b010: alu_op = OP_SLT;   // SLTI (有符号)
                3'b011: alu_op = OP_SLTU;  // SLTIU (无符号)
                3'b100: alu_op = OP_XOR;   // XORI
                3'b101: alu_op = (funct7[5] ? OP_SRA : OP_SRL);  // SRLI/SRAI
                3'b110: alu_op = OP_OR;    // ORI
                3'b111: alu_op = OP_AND;   // ANDI
                default: alu_op = OP_ADD;
            endcase
        end
        
        // Load/Store指令
        7'b0000011, 7'b0100011: alu_op = OP_ADD;  // 地址计算
        
        // Branch指令 (需要特殊处理有符号/无符号比较)
        7'b1100011: begin
            case (funct3)
                3'b000: alu_op = OP_SUB;  // BEQ (a == b)
                3'b001: alu_op = OP_SUB;  // BNE (a != b)
                3'b100: alu_op = OP_SLT;  // BLT (有符号 a < b)
                3'b101: alu_op = OP_SLT;  // BGE (有符号 a >= b) - 实际用!(a < b)
                3'b110: alu_op = OP_SLTU; // BLTU (无符号 a < b)
                3'b111: alu_op = OP_SLTU; // BGEU (无符号 a >= b) - 实际用!(a < b)
                default: alu_op = OP_SUB;
            endcase
        end
        
        // JAL/JALR指令
        7'b1101111, 7'b1100111: alu_op = OP_ADD;  // 地址计算
        
        // 其他指令默认使用ADD
        default: alu_op = OP_ADD;
    endcase
end

    // 实例化前馈模块
    feedforward ff (
        .clk(clk),
        .rst_n(rst_n),
        .rs1(rs1),
        .rs2(rs2),
        .imm(imm),
        .data1(data1),
        .data2(data2),
        .rs1_en(en1),
        .rs2_en(en2),
        .imm_en(imm_en),
        .load(load),
        .opcode(op),
        .pc(pc),
        //.func3(func3),
        .decode_rd(rd), 
        .rd_en(rd_en),
        .exdata(exdata),
        .memdata(memdata),
        .stall(stall),
        .op1(op1),
        .op2(op2)
    );

    // 实例化ALU
    alu alu_unit (
        .a(op1),
        .b(op2),
        .alu_op(alu_op),
        .result(alu_result),
        .zero(zero)
    );

    // 产生flush信号
    reg [31:0] correctpcreg;
    reg jumpflag;
    always@(*)
    begin 
        if(op[6:0]==7'b1100011) begin
        case(func3)
            3'b000:jumpflag=zero;
            3'b001:jumpflag=!zero;
            3'b100:jumpflag=!zero;
            3'b110:jumpflag=!zero;
            3'b101:jumpflag=zero;
            3'b111:jumpflag=zero;
        endcase
        correctpcreg=jumpflag?(pc+imm):(pc+4);//冒险bug
        end
        else if (op[6:0]==7'b1101111) begin
            correctpcreg=result;
        end
        else if (op[6:0]==7'b1100111) begin
            correctpcreg=result;
        end
        else begin
            correctpcreg=31'd0;
        end
    end
    assign flush=jump_en?((correctpc!=nextpc)?1'b1:1'b0):1'b0;
    assign correctpc=correctpcreg;

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
reg [14:0] rd;
wire [4:0] newrd;
assign newrd=rd_en?decode_rd:5'd0;
wire [3:0] flag;


assign flag[3]=(rs2[4:0]==rd[14:10])?1:0;
assign flag[2]=(rs1[4:0]==rd[14:10])?1:0;
assign flag[1]=(rs2[4:0]==rd[9:5])?1:0;
assign flag[0]=(rs1[4:0]==rd[9:5])?1:0;
//串行存储3个rd
always@(posedge clk or negedge rst_n)
begin
    if(!rst_n)
    begin
        rd[14:0]=15'd0;
    end
    else begin
        rd[14:0]={rd[9:0],newrd[4:0]};
    end
end
//stall产生
assign stall=load&(flag[1]|flag[0]);
//5选2决定op1，op2
reg [31:0] op1reg;
reg [31:0] op2reg;
always@(*)
begin
    if(opcode==7'b1100011)begin//分支部分branch
        op1reg=data1;
        op2reg=data2;
    end
    else if(opcode==7'b1101111) begin//jal
        op1reg=pc;
        op2reg=imm;
    end
    else if(opcode==7'b1100111) begin//jalr
        op1reg=data1;
        op2reg=imm;
    end
    else begin//其他：有立即数则op2为立即数，其他看看冲突
        if(imm_en) begin
            op2reg=imm;
            case(flag)
            4'd0000:op1reg=data1;
            4'd0001:op1reg=exdata;//只要不产生停顿，就不会有0001+ld的情况；如果ld造成停顿，ld语句自然成为rd的第2个相当于隔离了2个周期，自然变成0100
            4'd0100:op1reg=memdata;
            default:op1reg=32'd0;
            endcase
        end
        else begin
            case(flag)//解读：不可能有11xx，xx11因为rs1不等于rs2，不可能有1x1x，x1x1，因为这样的程序无意义因此最多1个1；
            4'd0000:op1reg=data1;
                    op2reg=data2;
            4'd0001:op1reg=exdata;
                    op2reg=data2;
            4'd0100:op1reg=memdata;
                    op2reg=data2;
            4'd1000:op1reg=data1;
                    op2reg=memdata;
            4'd0010:op1reg=data1;
                    op2reg=exdata;
            default:op1reg=32'd0;
                    op2reg=32'd0;
            endcase
        end
    end
end
assign op1=op1reg;
assign op2=op2reg;

endmodule
module alu (
    input  [31:0] a,          // 操作数1（来自寄存器rs1）
    input  [31:0] b,          // 操作数2（来自寄存器rs2或立即数imm）
    input  [3:0]  alu_op,     // ALU操作码（由控制器生成）
    output reg [31:0] result, // 运算结果
    output zero               // 结果是否为0（用于分支指令判断）
);

    // ================= ALU操作码定义（中文注释） =================
    localparam OP_ADD  = 4'b0000;  // 加法（ADD/ADDI）
    localparam OP_SUB  = 4'b0001;  // 减法（SUB）
    localparam OP_SLL  = 4'b0010;  // 逻辑左移（SLL/SLLI）
    localparam OP_SLT  = 4'b0011;  // 有符号比较小于（SLT/SLTI）
    localparam OP_SLTU = 4'b0100;  // 无符号比较小于（SLTU/SLTIU）
    localparam OP_XOR  = 4'b0101;  // 异或（XOR/XORI）
    localparam OP_SRL  = 4'b0110;  // 逻辑右移（SRL/SRLI）
    localparam OP_SRA  = 4'b0111;  // 算术右移（SRA/SRAI）
    localparam OP_OR   = 4'b1000;  // 或（OR/ORI）
    localparam OP_AND  = 4'b1001;  // 与（AND/ANDI）

    // 移位量（RISC-V规范：仅取b的低5位）
    wire [4:0] shamt = b[4:0];

    // ================= ALU核心运算逻辑 =================
    always @(*) begin
        case (alu_op)
            OP_ADD:  result = a + b;                    // 加法
            OP_SUB:  result = a - b;                    // 减法
            OP_SLL:  result = a << shamt;               // 左移（低位补0）
            OP_SLT:  result = ($signed(a) < $signed(b)) ? 32'd1 : 32'd0; // 有符号比较
            OP_SLTU: result = (a < b) ? 32'd1 : 32'd0;  // 无符号比较
            OP_XOR:  result = a ^ b;                    // 异或（相同为0，不同为1）
            OP_SRL:  result = a >> shamt;               // 逻辑右移（高位补0）
            OP_SRA:  result = $signed(a) >>> shamt;      // 算术右移（高位补符号位）
            OP_OR:   result = a | b;                    // 或（有1则1）
            OP_AND:  result = a & b;                    // 与（全1则1）
            default: result = 32'b0;                    // 默认输出0（无效操作码）
        endcase
    end

    // 判断结果是否为0（用于BEQ/BNE等分支指令）
    assign zero = (result == 32'b0);

endmodule
module exmemreg(
    input clk,
    input rst_n,
    input [31:0] ex_result,
    input [4:0] rd_i,
    output read_en,
    output write_en,
    output wb_en,
    output [31:0] result,
    output [31:0] result_address,
    output [4:0] rd_o
);
endmodule

module data_mem (
    //========== 时钟与复位 ==========//
    input         clk,          // 时钟信号
    input         rst_n,        // 异步低电平复位
    //========== 存储器控制 ==========//
    input         read_en,      // 异步读使能
    input  [2:0]  mem_op,      // 内存操作类型（见下方编码）
    input         write_en,    // 同步写使能（上升沿触发）
    //========== 数据接口 ==========//
    input  [31:0] datain,      // 写入数据
    input  [31:0] address,     // 字节地址
    output [31:0] dataout      // 读取数据（带符号扩展）
);

    // ================= 存储器参数 =================
    parameter MEM_SIZE_KB = 4;                   // 默认4KB数据存储器
    localparam MEM_DEPTH = MEM_SIZE_KB * 1024;    // 总字节容量
    localparam ADDR_WIDTH = $clog2(MEM_DEPTH);    // 地址线宽度

    // ================= 操作类型编码 =================
    // Load操作 [2:0]:
    localparam LB   = 3'b000;  // 加载字节（有符号扩展）
    localparam LH   = 3'b001;  // 加载半字（有符号扩展）
    localparam LW   = 3'b010;  // 加载字
    localparam LBU  = 3'b100;  // 加载字节（无符号扩展）
    localparam LHU  = 3'b101;  // 加载半字（无符号扩展）
    // Store操作 [2:0]:
    localparam SB   = 3'b000;  // 存储字节
    localparam SH   = 3'b001;  // 存储半字
    localparam SW   = 3'b010;  // 存储字

    // ================= 存储器实现 =================
    reg [7:0] mem [0:MEM_DEPTH-1];  // 按字节组织的存储器

    // ================= 写入逻辑（同步） =================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // 复位时不操作
        end 
        else if (write_en && address < MEM_DEPTH) begin
            case (mem_op)
                SB: begin  // 存储字节（datain[7:0]）
                    mem[address] <= datain[7:0];
                end
                SH: begin  // 存储半字（datain[15:0]，地址需2字节对齐）
                    if (address[0] == 0) begin
                        mem[address]   <= datain[7:0];
                        mem[address+1] <= datain[15:8];
                    end
                end
                SW: begin  // 存储字（datain[31:0]，地址需4字节对齐）
                    if (address[1:0] == 0) begin
                        mem[address]   <= datain[7:0];
                        mem[address+1] <= datain[15:8];
                        mem[address+2] <= datain[23:16];
                        mem[address+3] <= datain[31:24];
                    end
                end
                default: ;  // 其他操作不写入
            endcase
        end
    end

    // ================= 读取逻辑（异步） =================
    wire [31:0] raw_data;  // 原始读取数据（未扩展）
    assign raw_data = (!rst_n || !read_en) ? 32'b0 :
                     (address >= MEM_DEPTH-3) ? 32'b0 :
                     {mem[address+3], mem[address+2],
                      mem[address+1], mem[address]};

    // 根据mem_op进行符号扩展或截断
    reg [31:0] read_data;
    always @(*) begin
        case (mem_op)
            LB:  begin  // 有符号字节扩展
                read_data = {{24{raw_data[7]}},  raw_data[7:0]};
            end
            LH:  begin  // 有符号半字扩展
                read_data = {{16{raw_data[15]}}, raw_data[15:0]};
            end
            LW:  begin  // 读取完整字
                read_data = raw_data;
            end
            LBU: begin  // 无符号字节扩展
                read_data = {24'b0, raw_data[7:0]};
            end
            LHU: begin  // 无符号半字扩展
                read_data = {16'b0, raw_data[15:0]};
            end
            default: read_data = raw_data;  // 默认按字读取
        endcase
    end

    assign dataout = read_data;

endmodule

module memwbreg(
    input clk,
    input rst_n,
    input wb_en,
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







