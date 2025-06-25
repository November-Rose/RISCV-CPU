`timescale 1ns / 1ps

module myCPU(
    input         w_clk_rst,     // 高电平复位
    input         w_cpu_clk,    
    // IROM接口
    output [31:0] pc,
    input  [31:0] instruction,
    // 外设接口
    output [31:0] perip_addr,
    output        perip_wen,
    output [1:0]  perip_mask,
    output [31:0] perip_wdata,
    input  [31:0] perip_rdata    // 从外设读取的原始数据（未扩展）
);

    // 操作码定义
    localparam LB   = 3'b000;
    localparam LH   = 3'b001;
    localparam LW   = 3'b010;
    localparam LBU  = 3'b100;
    localparam LHU  = 3'b101;
    localparam SB   = 3'b000;
    localparam SH   = 3'b001;
    localparam SW   = 3'b010;

    wire [2:0] datamem_op;
    reg [1:0] perip_mask_reg;
    wire [31:0] datamem_datar;  // 符号扩展后的数据

    // 实例化cputop
    cputop u_cputop (
        .clk                 (w_cpu_clk),
        .rst_n               (~w_clk_rst),
        .instrmem_instr_addr (pc),
        .instrmem_instr_data (instruction),
        .datamem_datar       (datamem_datar),  // 使用扩展后的数据
        .datamem_w_en        (perip_wen),
        .datamem_addr        (perip_addr),
        .datamem_op          (datamem_op),
        .datamem_dataw       (perip_wdata)
    );

    // 操作码到字节掩码转换
    always @(*) begin
        case (datamem_op)
            SB:   perip_mask_reg = 2'b00;
            SH:   perip_mask_reg = 2'b01;
            SW:   perip_mask_reg = 2'b11;
            LB:   perip_mask_reg = 2'b00;
            LH:   perip_mask_reg = 2'b01;
            LW:   perip_mask_reg = 2'b11;
            LBU:  perip_mask_reg = 2'b00;
            LHU:  perip_mask_reg = 2'b01;
            default: perip_mask_reg = 2'b11;
        endcase
    end
    assign perip_mask = perip_mask_reg;

    // -------------------------------
    // 新增：符号/零扩展处理逻辑
    // -------------------------------
    reg [31:0] datamem_datar_reg;
    always @(*) begin
        case (datamem_op)
            // 有符号扩展
            LB: begin
                case (perip_addr[1:0])
                    2'b00: datamem_datar_reg = {{24{perip_rdata[7]}},  perip_rdata[7:0]};
                    2'b01: datamem_datar_reg = {{24{perip_rdata[15]}}, perip_rdata[15:8]};
                    2'b10: datamem_datar_reg = {{24{perip_rdata[23]}}, perip_rdata[23:16]};
                    2'b11: datamem_datar_reg = {{24{perip_rdata[31]}}, perip_rdata[31:24]};
                endcase
            end
            LH: begin
                case (perip_addr[1])
                    1'b0: datamem_datar_reg = {{16{perip_rdata[15]}}, perip_rdata[15:0]};
                    1'b1: datamem_datar_reg = {{16{perip_rdata[31]}}, perip_rdata[31:16]};
                endcase
            end
            // 无符号扩展
            LBU: begin
                case (perip_addr[1:0])
                    2'b00: datamem_datar_reg = {24'b0, perip_rdata[7:0]};
                    2'b01: datamem_datar_reg = {24'b0, perip_rdata[15:8]};
                    2'b10: datamem_datar_reg = {24'b0, perip_rdata[23:16]};
                    2'b11: datamem_datar_reg = {24'b0, perip_rdata[31:24]};
                endcase
            end
            LHU: begin
                case (perip_addr[1])
                    1'b0: datamem_datar_reg = {16'b0, perip_rdata[15:0]};
                    1'b1: datamem_datar_reg = {16'b0, perip_rdata[31:16]};
                endcase
            end
            // 默认情况（LW和其他指令）
            default: datamem_datar_reg = perip_rdata;
        endcase
    end
    assign datamem_datar = datamem_datar_reg;

endmodule

//解决了两个不兼容问题，1符号位扩展问题，2op从3位变成2位

module cputop(
    input         clk,
    input         rst_n,

    output [31:0] instrmem_instr_addr,
    input  [31:0] instrmem_instr_data,

    input  [31:0] datamem_datar,
    //output        datamem_r_en,  
    output        datamem_w_en,//读使能自动默认
    //output [31:0] datamem_addr_r,
    //output [31:0] datamem_addr_w,
    output [31:0] datamem_addr,
    //output [2:0]  datamem_op_r,
    //output [2:0]  datamem_op_w,
    output [2:0]  datamem_op,
    output [31:0] datamem_dataw
);

    // ====================== 信号声明 =====================
    // PC模块信号
    wire         stall;   // 阻塞信号
    wire        brunch_taken;   // NOTES:需要添加，分支实际跳转结果（来自交付单元）
    wire        update_en;      // NOTES:需要添加,分支指令执行完毕后给出
    wire        flush;               // 冲刷信号（分支预测错误）
    // IF/ID寄存器信号
    wire [31:0] ifid_instr;
    wire [31:0] ifid_instr_addr;

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
    //wire [31:0] exmem_result_addr;
    wire [4:0]  exmem_rd;
    //wire [2:0]  exmem_op;
    

    // MEM/WB寄存器信号
    wire        memwb_wb_en;
    wire [31:0] memwb_result;
    wire [4:0]  memwb_rd;

    // ====================== 模块实例化 ======================

    // ---------------------- IF ----------------------
    IF_top IF_top_inst(
        .clk(clk),
        .rst_n(rst_n),
        .instr_data(instrmem_instr_data),
        .stall(stall),
        .brunch_taken(brunch_taken),
        .update_en(update_en),
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
        .instr_addr_o(ifid_instr_addr)
    );

    // ---------------------- 译码器 ----------------------
    decoder decoder_inst (
        .instr(ifid_instr),
        .instr_addr_i(ifid_instr_addr),
        .imm(decoder_imm),
        .imm_en(decoder_imm_en),
        .op(decoder_op),
        .funct7(decoder_funct7),
        .funct3(decoder_funct3),
        .rd_addr(decoder_rd),
        .rd_en(decoder_rd_en),
        .instr_addr_o(idex_instr_addr),          
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
        .pc_i(idex_instr_addr),
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
        .rs2_o(idex_rs2)
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
        .nextpc(instrmem_instr_addr),

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
        //.result_address_i(ex_result_addr),
        .rd_i(idex_rd),
        .wb_en_i(idex_rd_en),
        .read_en_i(idex_mem_op[4]), // Load指令标志
        //.mem_op_i(idex_mem_op[2:0]),

        .wb_en_o(exmem_wb_en),
        .result_o(exmem_result),
        .read_en_o(exmem_read_en),//a
        //.result_address_o(exmem_result_addr),//a
        //.mem_op_o(exmem_op),//a,a信号为了得到datamem_datar
        .rd_o(exmem_rd)
    );
    // assign datamem_op_r=exmem_op;
    // assign datamem_r_en=exmem_read_en;
    // assign datamem_addr_r=exmem_result_addr;

    // assign datamem_op_w=idex_mem_op[2:0];
    // assign datamem_w_en=idex_mem_op[3];//作为同步写入，为了保持时序一致性，需要从idex里面取这个
    // assign datamem_addr_w=ex_result_addr;
    // assign datamem_dataw = idex_data2;  // 写入数据来自寄存器堆读取的数据2

    

    // ---------------------- MEM/WB寄存器 ----------------------
    memwbreg memwbreg_inst (
        .clk(clk),
        .rst_n(rst_n),

        .wb_en(exmem_wb_en),
        .rd(exmem_rd),
        .result(exmem_read_en ? datamem_datar : exmem_result), // 选择ALU或存储器数据

        .regbag_w_data(memwb_result),
        .regbag_w_addr(memwb_rd),
        .regbag_w_en(memwb_wb_en)
    );

endmodule
/*
module top(
    input clk,
    input rst_n
);
    // 声明连线
    wire [31:0] instrmem_instr_addr;
    wire [31:0] instrmem_instr_data;
    
    wire        datamem_r_en;
    wire [31:0] datamem_datar;
    wire [2:0]  datamem_op_r;
    wire [31:0] datamem_addr_r;
    
    wire        datamem_w_en;
    wire [31:0] datamem_dataw;
    wire [2:0]  datamem_op_w;
    wire [31:0] datamem_addr_w;

    cputop cpu(
        .clk(clk),
        .rst_n(rst_n),

        .instrmem_instr_addr(instrmem_instr_addr),
        .instrmem_instr_data(instrmem_instr_data),
        
        .datamem_r_en(datamem_r_en),
        .datamem_datar(datamem_datar),
        .datamem_op_r(datamem_op_r),
        .datamem_addr_r(datamem_addr_r),

        .datamem_w_en(datamem_w_en),
        .datamem_dataw(datamem_dataw),
        .datamem_op_w(datamem_op_w),
        .datamem_addr_w(datamem_addr_w)
    );

    datamem datamem_inst (
        .clk(clk),
        .rst_n(rst_n),
        .write_en(datamem_w_en),     // 写使能（同步）
        .write_op(datamem_op_w),     // 写操作类型（SB/SH/SW）
        .write_data(datamem_dataw),  // 写入数据
        .write_addr(datamem_addr_w), // 写地址
    
        // 读端口
        .read_en(datamem_r_en),      // 读使能（异步）
        .read_op(datamem_op_r),      // 读操作类型（LB/LH/LW/LBU/LHU）
        .read_addr(datamem_addr_r),  // 读地址
        .read_data(datamem_datar)
    );

    // 指令存储器
    instrmem instrmem_inst (
        .rst_n(rst_n),
        .instr_addr(instrmem_instr_addr),
        .instr_data(instrmem_instr_data)
    );
endmodule*/