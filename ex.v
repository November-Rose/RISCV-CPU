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
    reg [3:0] alu_op;
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
    // assign correctpc=correctpcreg;

endmodule