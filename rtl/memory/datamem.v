module datamem (
    //========== 时钟与复位 ==========//
    input         clk,          // 时钟信号
    input         rst_n,        // 异步低电平复位
    
    //========== 写端口 ==========//
    input         write_en,     // 写使能（同步）
    input  [2:0]  write_op,     // 写操作类型（SB/SH/SW）
    input  [31:0] write_data,   // 写入数据
    input  [31:0] write_addr,   // 写地址（独立于读地址）
    
    //========== 读端口 ==========//
    input         read_en,      // 读使能（异步）
    input  [2:0]  read_op,      // 读操作类型（LB/LH/LW/LBU/LHU）
    input  [31:0] read_addr,    // 读地址（独立于写地址）
    output [31:0] read_data     // 读取数据
);

    // ================= 存储器参数 =================
    parameter MEM_SIZE_KB = 4;                   // 默认4KB数据存储器
    localparam MEM_DEPTH = MEM_SIZE_KB * 1024;   // 总字节容量
    localparam ADDR_WIDTH = $clog2(MEM_DEPTH);   // 地址线宽度
    
    // ================= 操作类型编码（与原始设计完全一致） =================
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

    // ================= 存储器实现（保持字节寻址方式） =================
    reg [7:0] mem [0:MEM_DEPTH-1];  // 按字节组织的存储器

    // ================= 写端口逻辑（同步，与原始设计逻辑一致） =================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // 复位时不操作（保持原始设计行为）
        end
        else if (write_en && write_addr < MEM_DEPTH) begin
            case (write_op)
                SB: begin  // 存储字节（write_data[7:0]）
                    mem[write_addr] <= write_data[7:0];
                end
                SH: begin  // 存储半字（write_data[15:0]，地址需2字节对齐）
                    if (write_addr[0] == 0) begin
                        mem[write_addr]   <= write_data[7:0];
                        mem[write_addr+1] <= write_data[15:8];
                    end
                end
                SW: begin  // 存储字（write_data[31:0]，地址需4字节对齐）
                    if (write_addr[1:0] == 0) begin
                        mem[write_addr]   <= write_data[7:0];
                        mem[write_addr+1] <= write_data[15:8];
                        mem[write_addr+2] <= write_data[23:16];
                        mem[write_addr+3] <= write_data[31:24];
                    end
                end
                default: ;  // 其他操作不写入（保持原始设计行为）
            endcase
        end
    end

    // ================= 读端口逻辑（异步，处理方式与原始设计一致） =================
    wire [31:0] raw_read_data = (read_en && read_addr < MEM_DEPTH) ? 
                               {mem[read_addr+3], mem[read_addr+2],
                                mem[read_addr+1], mem[read_addr]} : 32'b0;

    // 符号扩展处理（完全保持原始设计逻辑）
    reg [31:0] read_data_reg;
    always @(*) begin
        if (!rst_n) begin
            read_data_reg = 32'b0;
        end else begin
            case (read_op)
                LB:  begin  // 有符号字节扩展
                    read_data_reg = {{24{raw_read_data[7]}}, raw_read_data[7:0]};
                end
                LH:  begin  // 有符号半字扩展
                    read_data_reg = {{16{raw_read_data[15]}}, raw_read_data[15:0]};
                end
                LW:  begin  // 读取完整字
                    read_data_reg = raw_read_data;
                end
                LBU: begin  // 无符号字节扩展
                    read_data_reg = {24'b0, raw_read_data[7:0]};
                end
                LHU: begin  // 无符号半字扩展
                    read_data_reg = {16'b0, raw_read_data[15:0]};
                end
                default: read_data_reg = raw_read_data;  // 默认按字读取
            endcase
        end
    end

    assign read_data = read_data_reg;

endmodule