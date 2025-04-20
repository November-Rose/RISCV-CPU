
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
    assign mem_op[3]=load;//r_en
    assign mem_op[4]=store;//w_en
endmodule