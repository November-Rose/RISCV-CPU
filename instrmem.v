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
integer i = 0;
// ===== 存储器初始化（纯组合逻辑）=====
always @(*) begin
    // 默认填充NOP指令（确保未初始化地址返回安全值）
    if(!rst_n)
    begin
    for (i = 0; i < MEM_DEPTH; i = i + 1) begin
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
wire [ADDR_WIDTH-1:0] word_addr = instr_addr[ADDR_WIDTH+1:2]; // 字节地址转字地址(左移除以4)
assign instr_data = (~rst_n) ? 32'h00000013 :    // 复位时输出NOP
                   (word_addr >= MEM_DEPTH) ? 32'h00000013 : // 越界保护
                   mem[word_addr];                // 正常输出

endmodule
