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