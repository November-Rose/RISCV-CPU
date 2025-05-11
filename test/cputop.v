

//解决了两个不兼容问题，1符号位扩展问题，2op从3位变成2位

module cputop(
    input         clk,
    input         rst_n,

    output [31:0] instrmem_instr_addr,
    input  [31:0] instrmem_instr_data,

    input  [31:0] datamem_datar, 
    output        datamem_w_en,//读使能自动默认
    output [31:0] datamem_addr,
    output [2:0]  datamem_op,
    output [31:0] datamem_dataw,

    output wire        debug_wb_have_inst,   // WB阶段是否有指令 (对单周期CPU，可在复位后恒为1)
    output wire [31:0] debug_wb_pc,          // WB阶段的PC (若wb_have_inst=0，此项可为任意值)
    output wire        debug_wb_ena,         // WB阶段的寄存器写使能 (若wb_have_inst=0，此项可为任意值)
    output wire [ 4:0] debug_wb_reg,         // WB阶段写入的寄存器号 (若wb_ena或wb_have_inst=0，此项可为任意值)
    output wire [31:0] debug_wb_value        // WB阶段写入寄存器的值 (若wb_ena或wb_have_inst=0，此项可为任意值)
);
    
     // ====================== 信号声明 =====================寄存器输入端信号来源于前面的输出，输出端命名为寄存器信号
    // PC模块信号
    wire        stall;     // 阻塞信号
    wire        brunch_taken;   // NOTES:需要添加，分支实际跳转结果（来自交付单元）
    wire        update_en;      // NOTES:需要添加,分支指令执行完毕后给出
    wire        flush;               // 冲刷信号（分支预测错误）
    wire        update_en_o;
    wire        brunch_taken_o;      //update_en_o和brunch_taken_o应该从寄存器中获得
    // IF/ID寄存器信号
    wire [31:0] ifid_instr;
    wire [31:0] ifid_instr_addr;
    wire ifid_s_flag;

    // 译码器信号
    wire [31:0] decoder_imm;
    wire        decoder_imm_en;
    wire [6:0]  decoder_op;
    wire [7:0]  decoder_funct7;
    wire [2:0]  decoder_funct3;
    wire [4:0]  decoder_rd;
    wire        decoder_rd_en;
    wire [4:0]  decoder_mem_op;
    wire        decoder_jump_en;
    wire [4:0]  decoder_rs1;
    wire        decoder_rs1_en;
    wire [4:0]  decoder_rs2;
    wire        decoder_rs2_en;

    // 寄存器堆信号
    wire [31:0] regbag_data1;
    wire [31:0] regbag_data2;

    // ID/EX寄存器信号
    wire [6:0]  idex_op;
    wire [7:0]  idex_funct7;
    wire [2:0]  idex_funct3;
    wire [4:0]  idex_rd;
    wire        idex_rd_en;
    wire [31:0] idex_imm;
    wire        idex_imm_en;
    wire [31:0] idex_data1;
    wire [31:0] idex_data2;
    wire [4:0]  idex_mem_op;
    wire        idex_jump_en;
    wire [31:0] idex_pc;
    wire [31:0] idex_instr_addr;
    wire        idex_rs1_en;
    wire        idex_rs2_en;
    wire [4:0]  idex_rs1;
    wire [4:0]  idex_rs2;
    wire idex_s_flag;


    // EX模块信号
    wire [31:0] ex_result;
    wire [31:0] ex_result_addr;
    wire [31:0] ex_correctpc;
    

    assign datamem_op=idex_mem_op[2:0];
    assign datamem_w_en=idex_mem_op[3];
    assign datamem_addr=ex_result_addr;
    assign datamem_dataw=idex_data2;

     // EX/MEM寄存器信号
    wire        exmem_wb_en;
    wire [31:0] exmem_result;
    wire        exmem_read_en;
    wire [4:0]  exmem_rd;
    wire        exmem_s_flag;
    
    // MEM/WB寄存器信号
    wire        memwb_wb_en;
    wire [31:0] memwb_result;
    wire [4:0]  memwb_rd;
    wire        memwb_flag;
    
    
    // Debug Interface 
    reg [31:0] wb_pc_reg;
    reg [31:0] mem_pc_reg;
    //reg debug_wb_have_inst_reg;
    assign debug_wb_have_inst = ~memwb_flag;
    assign debug_wb_pc        = wb_pc_reg;
    assign debug_wb_ena       = memwb_wb_en;
    assign debug_wb_reg       = memwb_rd;
    assign debug_wb_value     = memwb_result;
    always@(posedge clk or negedge rst_n) begin
        if(~rst_n) begin
            wb_pc_reg<=32'b0;
            mem_pc_reg<=32'b0;
            //debug_wb_have_inst_reg<=1'b0;
        end
        else begin
            mem_pc_reg<=idex_pc;
            wb_pc_reg<=mem_pc_reg;
        end
    end

    // ====================== 模块实例化 ======================

    // ---------------------- IF ----------------------
    IF_top IF_top_inst(
        .clk(clk),
        .rst_n(rst_n),
        .instr_data(instrmem_instr_data),
        .stall(stall),
        .brunch_taken(brunch_taken_o),
        .update_en(update_en_o),
        .flush(flush),
        .checkpre_flush_addr(ex_correctpc), // 预测错误时，使用的PC地址
        .pc(instrmem_instr_addr)
    );
    

    // ---------------------- IF/ID寄存器 ----------------------
    ifidreg ifidreg_inst (
        .clk(clk),
        .rst_n(rst_n),
        .checkpre_flush(flush),
        .feedforward_stall(stall),

        .instrmem_instr_data(instrmem_instr_data),
        .instr_addr_i(instrmem_instr_addr),
        .decoder_instr(ifid_instr),
        .instr_addr_o(ifid_instr_addr),
        .s_flag(ifid_s_flag)
    );

    // ---------------------- 译码器 ----------------------
    decoder decoder_inst (
        .instr(ifid_instr),
        .imm(decoder_imm),
        .imm_en(decoder_imm_en),
        .op(decoder_op),
        .funct7(decoder_funct7),
        .funct3(decoder_funct3),
        .rd_addr(decoder_rd),
        .rd_en(decoder_rd_en),        
        .mem_op(decoder_mem_op),
        .jump_en(decoder_jump_en),
        .rs1_addr(decoder_rs1),
        .rs1_en(decoder_rs1_en),
        .rs2_addr(decoder_rs2),
        .rs2_en(decoder_rs2_en)
    );

    // ---------------------- 寄存器堆 ----------------------
    regbag regbag_inst (
        .clk(clk),
        .rst_n(rst_n),
        .decoder_r_en1(decoder_rs1_en),
        .decoder_r_addr1(decoder_rs1),
        .idexreg_r_data1(regbag_data1),
        .decoder_r_en2(decoder_rs2_en),
        .decoder_r_addr2(decoder_rs2),
        .idexreg_r_data2(regbag_data2),
        .wb_w_en(memwb_wb_en),
        .wb_w_addr(memwb_rd),
        .wb_w_data(memwb_result)
    );

    // ---------------------- ID/EX寄存器 ----------------------
    idexreg idexreg_inst (
        .clk(clk),
        .rst_n(rst_n),
        .checkpre_flush(flush),
        .feedforward_stall(stall),
        .s_flag_i(ifid_s_flag),

        .regbag_data1(regbag_data1),
        .regbag_data2(regbag_data2),
        .en1_i(decoder_rs1_en),
        .en2_i(decoder_rs2_en),
        .decoder_en1_i(decoder_rs1_en),
        .decoder_en2_i(decoder_rs2_en),
        .imm_i(decoder_imm),
        .imm_en_i(decoder_imm_en),
        .rd_i(decoder_rd),
        .rd_en_i(decoder_rd_en),
        .op_i(decoder_op),
        .funct7_i(decoder_funct7),
        .funct3_i(decoder_funct3),
        .mem_op_i(decoder_mem_op),
        .jump_en_i(decoder_jump_en),
        .pc_i(ifid_instr_addr),
        .rs1_i(decoder_rs1),
        .rs2_i(decoder_rs2),

        .op_o(idex_op),
        .funct7_o(idex_funct7),
        .funct3_o(idex_funct3),
        .rd_o(idex_rd),
        .rd_en_o(idex_rd_en),
        .imm_o(idex_imm),
        .imm_en_o(idex_imm_en),
        .data1_o(idex_data1),
        .en1_o(idex_rs1_en),
        .data2_o(idex_data2),
        .en2_o(idex_rs2_en),
        .mem_op_o(idex_mem_op),
        .jump_en_o(idex_jump_en),
        .pc_o(idex_pc),
        .rs1_o(idex_rs1),
        .rs2_o(idex_rs2),
        .s_flag_o(idex_s_flag)
    );

    // ---------------------- EX模块 ----------------------
    ex ex_inst (
        .clk(clk),
        .rst_n(rst_n),

        .en1(idex_rs1_en),
        .en2(idex_rs2_en),
        .imm_en(idex_imm_en),
        .rd_en(idex_rd_en),
        .rd(idex_rd),
        .rs1(idex_rs1),         // 原始rs1地址
        .rs2(idex_rs2),         // 原始rs2地址,用于判断数据依赖
        .imm(idex_imm),
        .data1(idex_data1),
        .data2(idex_data2),
        .mem_op(idex_mem_op),
        .jump_en(idex_jump_en),
        .op(idex_op),
        .funct7(idex_funct7),
        .funct3(idex_funct3),
        .exdata(exmem_result),        // 前递数据（来自EX阶段）
        .memdata(memwb_result),     // 前递数据（来自MEM阶段）
        .pc(idex_pc),
        .nextpc(ifid_instr_addr),   //NOTES:需要连接if阶段的new addr
        .s_flag(idex_s_flag),

        .exresult(ex_result),
        .result_address(ex_result_addr),
        .stall(stall),
        .flush(flush),
        .correctpc(ex_correctpc),
        .update_en(update_en), // 更新信号
        .brunch_taken(brunch_taken)
    );

    // ---------------------- EX/MEM寄存器 ----------------------
    exmemreg exmemreg_inst (
        .clk(clk),
        .rst_n(rst_n),

        .result_i(ex_result),
        .rd_i(idex_rd),
        .wb_en_i(idex_rd_en),
        .read_en_i(idex_mem_op[4]), // Load指令标志
        .update_en_i(update_en),
        .brunch_taken_i(brunch_taken),
        .s_flag_i(idex_s_flag),

        .wb_en_o(exmem_wb_en),
        .result_o(exmem_result),
        .read_en_o(exmem_read_en),//a
        .rd_o(exmem_rd),
        .update_en_o(update_en_o),
        .brunch_taken_o(brunch_taken_o),
        .s_flag_o(exmem_s_flag)
    );
    

    // ---------------------- MEM/WB寄存器 ----------------------
    memwbreg memwbreg_inst (
        .clk(clk),
        .rst_n(rst_n),

        .wb_en(exmem_wb_en),
        .rd(exmem_rd),
        .result(exmem_read_en ? datamem_datar : exmem_result), // 选择ALU或存储器数据
        .s_flag_i(exmem_s_flag),

        .regbag_w_data(memwb_result),
        .regbag_w_addr(memwb_rd),
        .regbag_w_en(memwb_wb_en),
        .s_flag_o(memwb_flag)

    );

endmodule


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
    output [4:0]  mem_op,        // 内存操作类型（LB/LH/LW/LBU/LHU/SB/SH/SW）,低3位位datamem里面的op，高2位位r_en和w_en
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
    //assign instr_addr_o = instr_addr_i;  // 直传指令地址

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
    assign rd_en   = !is_stype && !is_btype; // STORE和BRANCH不写rd
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
    assign mem_op[3]=load;//r_en
    assign mem_op[4]=store;//w_en
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
integer i;
//==============================
// 写操作（同步时序逻辑）
//==============================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        // 异步复位（所有寄存器清零）
        for (i = 1; i < 32; i = i + 1) begin
            register[i] <= 32'b0;
        end
    end
    else if (wb_w_en && (wb_w_addr != 5'b0)) begin
        // 同步写入（x0地址不写入）
        register[wb_w_addr] <= wb_w_data;
    end
end

//==============================
// 读端口1（带旁路逻辑）
//==============================
assign idexreg_r_data1 = (!decoder_r_en1) ? 32'b0 :          // 读使能关闭
                        (decoder_r_addr1 == 5'b0) ? 32'b0 :  // x0处理
                        // 写旁路：如果正在写入相同地址，直接返回待写入值
                        (wb_w_en && (wb_w_addr == decoder_r_addr1)) ? wb_w_data :
                        register[decoder_r_addr1];            // 正常读取

//==============================
// 读端口2（带旁路逻辑）
//==============================
assign idexreg_r_data2 = (!decoder_r_en2) ? 32'b0 :          // 读使能关闭
                        (decoder_r_addr2 == 5'b0) ? 32'b0 :  // x0处理
                        // 写旁路
                        (wb_w_en && (wb_w_addr == decoder_r_addr2)) ? wb_w_data :
                        register[decoder_r_addr2];            // 正常读取


endmodule


//README:为了代码的可读性与可维护性，我会尽可能地将大模块划分为几个小模块。同时为了不与spec文档产生过多冲突，我会尽量沿用spec文档中的变量名，并对新增的模块和变量予以注释说明
module IF_top(
    //========== 时钟与复位 ==========//
    input         clk,                // 全局时钟（上升沿触发）
    input         rst_n,              // 异步低电平复位（0复位，1正常工作）
    input  [31:0] instr_data,         // 指令存储器数据（32位）
    
    //========== 冒险控制 ==========//
    input         stall,
    
    //========== 分支预测接口 ==========//
    input  wire        brunch_taken,   // 分支实际跳转结果（来自交付单元）
    input  wire        update_en,      // 分支预测表更新使能
    
    //========== 流水线控制 ==========//
    input         flush,               // 冲刷信号（分支预测错误）
    input  [31:0] checkpre_flush_addr, // 冲刷恢复地址
    
    //========== 输出 ==========//
    output [31:0] pc                   // 当前PC值（4字节对齐）
);

    //========== 内部信号声明 ==========//
    wire [31:0] new_PC_addr;          // 新PC地址
    wire        new_addr_en;          // PC更新使能
    wire        pred_f_en;            // 分支预测使能
    wire        btb_hit;              // BTB命中信号
    wire [31:0] predicted_target_addr;// BTB预测地址
    wire        jxx, bxx;             // 预解码控制信号

    //========== 模块实例化 ==========//
    // PC寄存器模块
    PC_reg pc_reg_inst (
        .clk          (clk),
        .rst_n        (rst_n),
        .new_addr_en  (new_addr_en),
        .new_PC_addr  (new_PC_addr),
        .pc           (pc)
    );

    // PC多路选择器
    PC_MUX pc_mux_inst (
        .pc                   (pc),
        .pred_f_en            (pred_f_en),
        .pred_f_addr          (predicted_target_addr),  // 使用BTB预测地址
        .btb_hit              (btb_hit),
        .checkpre_flush        (flush),
        .checkpre_flush_addr  (checkpre_flush_addr),
        .new_PC_addr          (new_PC_addr)
    );

    // PC更新使能生成
    PC_enable pc_enable_inst (
        .data_hazard_stall    (stall),
        .control_hazard_stall (stall),
        .new_addr_en          (new_addr_en)
    );

    // 指令预解码器
    predecode predecoder_inst (
        .instr_data           (instr_data),
        .jxx                  (jxx),
        .bxx                  (bxx)
    );

    // 分支预测单元（BPU）
    BPU bpu_inst (
        .clk           (clk),
        .rst_n         (rst_n),
        .jxx           (jxx),
        .bxx           (bxx),
        .pc            (pc),
        .brunch_taken  (brunch_taken),
        .update_en     (update_en),
        .pred_f_en     (pred_f_en)
    );

    // 分支目标缓冲（BTB）
    BTB #(
        .BTB_SIZE      (16),
        .ADDR_WIDTH    (32)
    ) btb_inst (
        .clk                  (clk),
        .rst_n                (rst_n),
        .jxx                  (jxx),
        .bxx                  (bxx),
        .pc                   (pc),
        .target_addr          (checkpre_flush_addr),
        .update_en            (update_en),
        .predicted_target_addr(predicted_target_addr),
        .btb_hit              (btb_hit)
    );
endmodule

module PC_reg (                         //原PC模块//
    //========== 时钟与复位 ==========//
    input         clk,        // 全局时钟（上升沿触发）
    input         rst_n,      // 异步低电平复位（0复位，1正常工作）
    /*CHANGE：为了PC_reg模块的简洁，将获得正确地址的逻辑独立出来，只将new_PC_addr传入
    //========== 分支预测接口 ==========//
    input         pred_f_en,       // 分支预测使能（1表示预测跳转）
    input  [31:0] pred_f_addr,     // 预测跳转地址（来自分支预测器）
    
    //========== 流水线控制 ==========//
    input         checkpre_flush,      // 冲刷信号（分支预测错误时置1）
    */
    /*CHANGE：阻塞信号由PC_enable模块接受，PC_enable输出new_addr_en信号
    input         feedforward_stall,   // 阻塞信号（数据冲突时置1）
    */
    input         new_addr_en,       // 新地址使能（1表示新地址有效）
    input  [31:0] new_PC_addr,          // 新地址
    //========== 输出 ==========//
    output reg [31:0] pc    // 当前PC值（按4字节对齐，addr[1:0]=00）
);
    always @(posedge clk) begin
        if(!rst_n) begin
            pc <= 32'h0000_0000; //复位时PC值为0
        end else if (new_addr_en) begin
            pc <= new_PC_addr; //新地址有效时更新PC值
        end 
    end
endmodule

module PC_MUX(
    input  [31:0] pc,  //原先的PC值
    input         pred_f_en,       // 分支预测使能（1表示预测跳转）
    input  [31:0] pred_f_addr,     // 预测跳转地址（来自分支预测器）
    input         btb_hit,      // BTB命中信号（1表示命中）
    input         checkpre_flush,      // 冲刷信号（分支预测错误时置1）
    input  [31:0] checkpre_flush_addr,   // CHANGE：新增冲刷地址（分支预测错误时的PC值）
    output reg [31:0] new_PC_addr
);
    always @(*) begin
        if (checkpre_flush) begin
           new_PC_addr = checkpre_flush_addr; //冲刷信号有效时使用冲刷地址
        end else if (pred_f_en && btb_hit) begin
            new_PC_addr = pred_f_addr; //分支预测使能时使用预测地址
        end else begin
            new_PC_addr = pc + 4; //默认情况下PC值加4
        end
    end
endmodule

//CHANGE:该模块用于产生PC_reg模块的new_addr_en信号,其中的input需要由数据相关性检测器和控制冒险检测器提供。为此需要特别注意可能产生冒险的地方。
//NOTES:此处有两个需要由下级流水给出的信号
module PC_enable(
    input        data_hazard_stall,//数据冒险的阻塞信号
    input        control_hazard_stall,//控制冒险的阻塞信号
    output       new_addr_en //新地址使能信号
);

assign new_addr_en = !data_hazard_stall && !control_hazard_stall; //当两个信号都为0时，new_addr_en为1
endmodule

module predecode(
    input [31:0] instr_data,
    output       jxx,
    output       bxx
);
localparam OPCODE_JAL    = 7'b1101111;  // JAL指令
localparam OPCODE_JALR   = 7'b1100111;  // JALR指令
localparam OPCODE_BRANCH = 7'b1100011;   // 分支指令

// ========================= 预解码逻辑 =========================
wire is_jal    = (instr_data[6:0] == OPCODE_JAL);    // JAL指令
wire is_jalr   = (instr_data[6:0] == OPCODE_JALR);   // JALR指令
wire is_branch = (instr_data[6:0] == OPCODE_BRANCH); // 分支指令

// 组合逻辑输出（立即识别指令类型）
assign jxx = is_jal | is_jalr;   // 合并J型指令信号
assign bxx = is_branch;          // 分支指令信号
endmodule

//CHANGE:原先的分支预测模块pred容易与predecode混淆，因此将其名称改为BPU（Branch Prediction Unit）
//拟采用Bi-Mode分支预测
//这是AI写的，可能还有逻辑需要改正
module BPU (
    input wire clk,
    input wire rst_n,
    input wire jxx,
    input wire bxx,
    input wire [31:0] pc,  // 指令地址
    input wire brunch_taken,  // NOTES:此信号需要由交付单元给出。分支指令实际是否跳转，1表示跳转，0表示不跳转。
    input wire update_en,  // NOTES:此信号需要由交付单元给出。当分支指令完成时，update_en为1，表示需要更新预测表
    output reg pred_f_en  // 预测结果，1表示跳转，0表示不跳转
);

    // 参数定义
    parameter TABLE_SIZE = 256;  // 预测表大小
    parameter SELECTOR_SIZE = 256;  // 选择器表大小
    parameter COUNTER_BITS = 2;  // 计数器位数

    // 定义T表、NT表和选择器表
    reg [COUNTER_BITS-1:0] T_table [TABLE_SIZE-1:0];
    reg [COUNTER_BITS-1:0] NT_table [TABLE_SIZE-1:0];
    reg [COUNTER_BITS-1:0] selector_table [SELECTOR_SIZE-1:0];

    // 计算索引
    wire [7:0] prediction_index;
    wire [7:0] selector_index;
    assign prediction_index = pc[7:0];
    assign selector_index = pc[15:8];

    // 预测逻辑
    always @(*) begin
        if (jxx && !bxx) begin
             pred_f_en = 1'b1;
        end else if(bxx && !jxx) begin
             if (selector_table[selector_index] >= 2'b10) begin
            // 选择T表
                pred_f_en = (T_table[prediction_index] >= 2'b10) ? 1'b1 : 1'b0;
            end else begin
            // 选择NT表
                pred_f_en = (NT_table[prediction_index] >= 2'b10) ? 1'b1 : 1'b0;
            end
        end else begin
            pred_f_en = 1'b0; // 非分支指令
        end
    end

    // 更新逻辑
    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // 复位，包含原来initial块的初始化逻辑
            for (i = 0; i < TABLE_SIZE; i = i + 1) begin
                T_table[i] <= 2'b11;  // 初始化为强可跳转状态
                NT_table[i] <= 2'b00; // 初始化为强不跳转状态
            end
            for (i = 0; i < SELECTOR_SIZE; i = i + 1) begin
                selector_table[i] <= 2'b10; // 初始化为弱选择T表状态
            end
        end else if (update_en) begin
            if (selector_table[selector_index] >= 2'b10) begin
                // 选择T表
                if (brunch_taken) begin
                    if (T_table[prediction_index] < 2'b11) begin
                        T_table[prediction_index] <= T_table[prediction_index] + 1;
                    end
                end else begin
                    if (T_table[prediction_index] > 2'b00) begin
                        T_table[prediction_index] <= T_table[prediction_index] - 1;
                    end
                end

                // 更新选择器
                //需要考虑特例情况
                if ((T_table[prediction_index] >= 2'b10 && brunch_taken) || (T_table[prediction_index] < 2'b10 && brunch_taken)) begin
                    if (selector_table[selector_index] < 2'b11) begin
                        selector_table[selector_index] <= selector_table[selector_index] + 1;
                    end
                end else if(T_table[prediction_index] >= 2'b10 && !brunch_taken) begin
                    if (selector_table[selector_index] > 2'b00) begin
                        selector_table[selector_index] <= selector_table[selector_index] - 1;
                    end
                end
            end else begin
                // 选择NT表
                if (brunch_taken) begin
                    if (NT_table[prediction_index] < 2'b11) begin
                        NT_table[prediction_index] <= NT_table[prediction_index] + 1;
                    end
                end else begin
                    if (NT_table[prediction_index] > 2'b00) begin
                        NT_table[prediction_index] <= NT_table[prediction_index] - 1;
                    end
                end

                // 更新选择器
                if ((NT_table[prediction_index] >= 2'b10 && !brunch_taken) || (NT_table[prediction_index] < 2'b10 && !brunch_taken)) begin
                    if (selector_table[selector_index] > 2'b00) begin
                        selector_table[selector_index] <= selector_table[selector_index] - 1;
                    end
                end else if(T_table[prediction_index] < 2'b10 && brunch_taken) begin
                    if (selector_table[selector_index] < 2'b11) begin
                        selector_table[selector_index] <= selector_table[selector_index] + 1;
                    end
                end
            end
        end
    end

endmodule 

//CHANGE:新增BTB模块用于预测分支指令跳转的地址
// BTB模块定义，使用参数化设计，方便调整BTB大小和地址位宽
module BTB #(
    parameter BTB_SIZE = 16,  // BTB的条目数量，可根据需要调整
    parameter ADDR_WIDTH = 32 // 地址位宽，可根据需要调整
) (
    input wire clk,           // 时钟信号，用于同步模块的操作
    input wire rst_n,         // 异步复位信号，低电平有效，用于将BTB模块复位到初始状态
    input wire jxx,
    input wire bxx,
    input wire [ADDR_WIDTH-1:0] pc, // 分支指令的地址，用于查找和存储操作
    //NOTES:target_addr在执行阶段产生，为预测地址与实际地址不一致时，分支指令的实际跳转地址
    input wire [ADDR_WIDTH-1:0] target_addr, // 分支指令的目标地址，用于存储操作
    //NOTES:update_en 信号的产生:执行阶段。比较实际的分支目标地址和 BTB 预测的目标地址。若两者不一致，表明预测错误，需要更新 BTB 中的信息；若一致，则说明预测正确。
    input wire update_en,     // 更新使能信号，用于控制是否更新BTB中的信息
    output reg [ADDR_WIDTH-1:0] predicted_target_addr, // 预测的分支目标地址，如果未命中则输出无效值
    output reg btb_hit            // 命中信号，表示是否在BTB中找到匹配的分支指令地址
);

    // BTB条目结构体
    // 存储分支指令的地址
    reg [ADDR_WIDTH-1:0] btb_branch_addr [BTB_SIZE-1:0];
    // 存储分支指令对应的目标地址
    reg [ADDR_WIDTH-1:0] btb_target_addr [BTB_SIZE-1:0];
    // 有效位，用于标记每个条目是否有效
    reg valid [BTB_SIZE-1:0];
    // 标志是否为分支指令
    wire is_branch;
    assign is_branch = jxx || bxx;

    // LRU计数器，用于实现最近最少使用（LRU）替换策略
    // lru_counter[i][j] 表示第i个条目相对于第j个条目的使用频率关系
    reg [BTB_SIZE-1:0] lru_counter [BTB_SIZE-1:0];

    integer i, j;
    integer empty_index;
    integer lru_index;
    integer max_lru;
    integer lru_sum;
    // 异步复位和正常操作逻辑
    always @(posedge clk or negedge rst_n) begin
        // 异步复位操作
        if (!rst_n) begin
            // 遍历BTB的所有条目
            for (i = 0; i < BTB_SIZE; i = i + 1) begin
                // 将所有条目的有效位置为0，表示无效
                valid[i] <= 1'b0;
                // 初始化LRU计数器
                for (j = 0; j < BTB_SIZE; j = j + 1) begin
                    lru_counter[i][j] <= 1'b0;
                end
            end
        end else begin
            if (is_branch) begin
                // 正常操作
                // 查找操作
                // 初始化命中信号为0，表示未命中
                btb_hit <= 1'b0;
                // 初始化预测的目标地址为全零，表示无效值
                predicted_target_addr <= {ADDR_WIDTH{1'b0}};
                // 遍历BTB的所有条目
                for (i = 0; i < BTB_SIZE; i = i + 1) begin
                    // 检查当前条目是否有效且分支指令地址匹配
                    if (valid[i] && btb_branch_addr[i] == pc) begin
                        // 命中，将命中信号置为1
                        btb_hit <= 1'b1;
                        // 输出预测的目标地址
                        predicted_target_addr <= btb_target_addr[i];
                        // 更新LRU计数器
                        for (j = 0; j < BTB_SIZE; j = j + 1) begin
                            if (j != i) begin
                                // 其他条目相对于当前条目更旧
                                lru_counter[j][i] <= 1'b1;
                            end else begin
                                // 当前条目相对于自身最新
                                lru_counter[j][i] <= 1'b0;
                            end
                        end
                    end
                end
            end

            // 存储操作
            if (is_branch && !btb_hit) begin
                empty_index = -1;
                lru_index = 0;
                max_lru = 0;
                // 查找空闲条目
                for (i = 0; i < BTB_SIZE; i = i + 1) begin
                    if (!valid[i]) begin
                        empty_index = i;
                        break;
                    end
                end
                // 如果没有空闲条目，使用LRU策略选择要替换的条目
                if (empty_index == -1) begin
                    for (i = 0; i < BTB_SIZE; i = i + 1) begin
                        lru_sum = 0;
                        // 计算每个条目的LRU计数器之和
                        for (j = 0; j < BTB_SIZE; j = j + 1) begin
                            lru_sum = lru_sum + lru_counter[i][j];
                        end
                        if (lru_sum > max_lru) begin
                            max_lru = lru_sum;
                            lru_index = i;
                        end
                    end
                    // 替换LRU条目
                    btb_branch_addr[lru_index] <= pc;
                    btb_target_addr[lru_index] <= target_addr;
                    valid[lru_index] <= 1'b1;
                    // 更新LRU计数器
                    for (j = 0; j < BTB_SIZE; j = j + 1) begin
                        if (j != lru_index) begin
                            lru_counter[j][lru_index] <= 1'b1;
                        end else begin
                            lru_counter[j][lru_index] <= 1'b0;
                        end
                    end
                end else begin
                    // 使用空闲条目存储新的分支信息
                    btb_branch_addr[empty_index] <= pc;
                    btb_target_addr[empty_index] <= target_addr;
                    valid[empty_index] <= 1'b1;
                    // 更新LRU计数器
                    for (j = 0; j < BTB_SIZE; j = j + 1) begin
                        if (j != empty_index) begin
                            lru_counter[j][empty_index] <= 1'b1;
                        end else begin
                            lru_counter[j][empty_index] <= 1'b0;
                        end
                    end
                end
            end

            // 更新操作
            if (update_en) begin
                // 如果预测错误，更新目标地址
                if (btb_hit && btb_target_addr[i] != target_addr) begin
                    for (i = 0; i < BTB_SIZE; i = i + 1) begin
                        if (valid[i] && btb_branch_addr[i] == pc) begin
                            btb_target_addr[i] <= target_addr;
                        end
                    end
                end
            end
        end
    end
endmodule    

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
    input s_flag,

    output [31:0] exresult,
    output [31:0] result_address,//仅仅用于访存load与store语句
    output stall,
    output flush,
    output [31:0] correctpc,
    output brunch_taken,
    output update_en
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
    reg [3:0] alu_op;
    wire [31:0] alu_result;
    wire [31:0] op1, op2;
    wire zero;
    wire stall1;
    
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
        .stall(stall1),
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
        case(funct3)
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
            correctpcreg=alu_result;
        end
        else if (op[6:0]==7'b1100111) begin
            correctpcreg=alu_result;
        end
        else begin
            correctpcreg=pc+4;
        end
    end
    assign stall=s_flag?1'b0:stall1;
    assign flush=s_flag?1'b0:(jump_en?((correctpc!=nextpc)?1'b1:1'b0):1'b0);
    assign correctpc=correctpcreg;
    assign result_address=(op == 7'b0100011||op == 7'b0000011)?alu_result:32'd0;//store:resultaddress是算出来的，result是rs2；load:address是算出来的，result未定
    assign exresult=(op == 7'b0100011)?data2:alu_result;
    assign update_en=jump_en;
    assign brunch_taken=jumpflag;
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
always @(*) begin
    if (opcode == 7'b1100011) begin // branch
        op1reg = data1;
        op2reg = data2;
    end
    else if (opcode == 7'b1101111) begin // jal
        op1reg = pc;
        op2reg = imm;
    end
    else if (opcode == 7'b1100111) begin // jalr
        op1reg = data1;
        op2reg = imm;
    end
    else begin // 其他情况
        if (imm_en) begin
            op2reg = imm; // op2 固定为立即数
            case (flag)
                4'b0000: op1reg = data1;
                4'b0001: op1reg = exdata;
                4'b0100: op1reg = memdata;
                default: op1reg = 32'd0;
            endcase
        end
        else begin
            case (flag) // 无立即数时，op1 和 op2 需同时处理
                4'b0000: begin
                    op1reg = data1;
                    op2reg = data2;
                end
                4'b0001: begin
                    op1reg = exdata;
                    op2reg = data2;
                end
                4'b0100: begin
                    op1reg = memdata;
                    op2reg = data2;
                end
                4'b1000: begin
                    op1reg = data1;
                    op2reg = memdata;
                end
                4'b0010: begin
                    op1reg = data1;
                    op2reg = exdata;
                end
                default: begin
                    op1reg = 32'd0;
                    op2reg = 32'd0;
                end
            endcase
        end
    end
end
assign op1=op1reg;
assign op2=op2reg;

endmodule

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
        s_flag_reg<=1'b1;
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

module ifidreg(
    input clk,
    input rst_n,
    input [31:0] instrmem_instr_data,
    input checkpre_flush,
    input feedforward_stall,
    input [31:0] instr_addr_i,

    output [31:0] decoder_instr,
    output [31:0] instr_addr_o,
    output s_flag
);
    // 流水线寄存器（包含指令和地址）
    reg [31:0] pipeline_reg;
    reg [31:0] addr_reg;  // 新增地址寄存器
    reg s_flag_reg;
    //==============================
    // 流水线控制逻辑（优先级：冲刷 > 阻塞 > 正常传输）
    //==============================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // 异步复位：清空流水线（输出NOP指令和0地址）
            pipeline_reg <= 32'h00000013;  // ADDI x0, x0, 0 (NOP)
            addr_reg <= 32'd0;
            s_flag_reg <=1'b1;
        end
        else begin
            s_flag_reg<=checkpre_flush;
            casez ({checkpre_flush, feedforward_stall})
                2'b1?: begin
                    // 冲刷优先（插入气泡）
                    pipeline_reg <= 32'h00000013;
                    addr_reg <= 32'd0;
                    //s_flag<=1'b1;
                end
                2'b01: begin
                    // 保持当前状态（阻塞）
                    // 两个寄存器都保持原值
                    //s_flag<=1'b1;
                end
                default: begin
                    // 正常传输
                    pipeline_reg <= instrmem_instr_data;
                    addr_reg <= instr_addr_i;
                    //s_flag<=1'b0;
                end
            endcase
        end
    end

    // 输出连接
    assign decoder_instr = pipeline_reg;
    assign instr_addr_o = addr_reg;  // 直接使用寄存器输出
    assign s_flag=s_flag_reg;
endmodule

module idexreg(
    input clk,
    input rst_n,
    input checkpre_flush,
    input feedforward_stall,
    input s_flag_i,

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
    input [4:0] rs1_i,
    input [4:0] rs2_i,
    //input [31:0] exdata_i,
    //input [31:0] memdata_i,

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
    output [31:0] pc_o,
    output [4:0] rs1_o,
    output [4:0] rs2_o,
    output s_flag_o
    //output [31:0] exdata_o,
    //output [31:0] memdata_o
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
reg s_flag_reg;
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
        s_flag_reg<=1'b1;
    end
    else begin
        s_flag_reg<=s_flag_i||checkpre_flush;
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
assign s_flag_o=s_flag_reg;

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