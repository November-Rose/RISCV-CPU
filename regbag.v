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

//==============================
// 写操作（同步时序逻辑）
//==============================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        // 异步复位（所有寄存器清零）
        for (integer i = 1; i < 32; i = i + 1) begin
            register[i] <= 32'b0;
        end
    end
    else if (wb_w_en && (wb_w_addr != 5'b0)) begin
        // 同步写入（x0地址不写入）
        register[wb_w_addr] <= wb_w_data;
    end
end

//==============================
// 读端口1（组合逻辑）
//==============================
assign idexreg_r_data1 = (!decoder_r_en1) ? 32'b0 :          // 读使能关闭时输出0
                         (decoder_r_addr1 == 5'b0) ? 32'b0 :  // x0始终返回0
                         register[decoder_r_addr1];            // 正常读取

//==============================
// 读端口2（组合逻辑）
//==============================
assign idexreg_r_data2 = (!decoder_r_en2) ? 32'b0 :          // 读使能关闭时输出0
                         (decoder_r_addr2 == 5'b0) ? 32'b0 :  // x0始终返回0
                         register[decoder_r_addr2];            // 正常读取


endmodule