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