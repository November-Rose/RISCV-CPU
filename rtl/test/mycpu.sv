module myCPU (
    input  logic         cpu_rst,
    input  logic         cpu_clk,

    // Interface to IROM
    // IROM接口
    output [31:0] pc,
    input  [31:0] instruction,
    // Interface to DRAM
    // 外设接口
    output [31:0] perip_addr,
    output        perip_wen,
    output [1:0]  perip_mask,
    output [31:0] perip_wdata,      //  正确写入
    input  [31:0] perip_rdata,    // 从外设读取的原始数据（未扩展）

    output wire        debug_wb_have_inst,   // WB阶段是否有指令 (对单周期CPU，可在复位后恒为1)
    output wire [31:0] debug_wb_pc,          // WB阶段的PC (若wb_have_inst=0，此项可为任意值)
    output wire        debug_wb_ena,         // WB阶段的寄存器写使能 (若wb_have_inst=0，此项可为任意值)
    output wire [ 4:0] debug_wb_reg,         // WB阶段写入的寄存器号 (若wb_ena或wb_have_inst=0，此项可为任意值)
    output wire [31:0] debug_wb_value        // WB阶段写入寄存器的值 (若wb_ena或wb_have_inst=0，此项可为任意值)
);

    // TODO: 完成你自己的单周期CPU设计
    
  /*  // Debug Interface
    assign debug_wb_have_inst = ;
    assign debug_wb_pc        = ;
    assign debug_wb_ena       = ;
    assign debug_wb_reg       = ;
    assign debug_wb_value     = ;*/

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
    wire [31:0] datamem_dataw;  //原始
    // 实例化cputop
    cputop u_cputop (
        .clk                 (cpu_clk),  //NOTES:疑似bug，w_cpu_clk->cpu_clk,下同
        .rst_n               (~cpu_rst),
        .instrmem_instr_addr (pc),
        .instrmem_instr_data (instruction),
        .datamem_datar       (datamem_datar),  // 使用扩展后的数据
        .datamem_w_en        (perip_wen),
        .datamem_addr        (perip_addr),
        .datamem_op          (datamem_op),
        .datamem_dataw       (datamem_dataw),  
        .debug_wb_have_inst  (debug_wb_have_inst),
        .debug_wb_pc(debug_wb_pc),
        .debug_wb_ena(debug_wb_ena),
        .debug_wb_reg(debug_wb_reg),
        .debug_wb_value(debug_wb_value)
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
    //dataw
    reg [31:0 ] perip_wdata_reg;
    // 存储指令的数据写入逻辑
    always @(*) begin
        case (datamem_op)
            // Store Byte (sb): 写入 1 字节
            SB: begin
                case (perip_addr[1:0])
                    2'b00: perip_wdata_reg = {perip_rdata[31:8], datamem_dataw[7:0]};    // 写入 [7:0]
                    2'b01: perip_wdata_reg = {perip_rdata[31:16], datamem_dataw[7:0], perip_rdata[7:0]}; // 写入 [15:8]
                    2'b10: perip_wdata_reg = {perip_rdata[31:24], datamem_dataw[7:0], perip_rdata[15:0]}; // 写入 [23:16]
                    2'b11: perip_wdata_reg = {datamem_dataw[7:0], perip_rdata[23:0]};    // 写入 [31:24]
                endcase
            end

            // Store Halfword (sh): 写入 2 字节
            SH: begin
                case (perip_addr[1])
                    1'b0: perip_wdata_reg = {perip_rdata[31:16], datamem_dataw[15:0]};   // 写入 [15:0]
                    1'b1: perip_wdata_reg = {datamem_dataw[15:0], perip_rdata[15:0]};    // 写入 [31:16]
                endcase
            end

            // Store Word (sw): 写入 4 字节
            SW: begin
                perip_wdata_reg = datamem_dataw;  // 直接写入全部 32 位
            end

            // 默认情况（非存储指令或未定义操作）
            default: begin
                perip_wdata_reg = perip_rdata;    // 保持原数据不变
            end
        endcase
    end
    assign perip_wdata = perip_wdata_reg;

endmodule
