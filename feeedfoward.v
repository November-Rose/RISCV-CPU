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