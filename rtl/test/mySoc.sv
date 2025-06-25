module miniRV_SoC (
    input  logic         fpga_rst,   // 高电平有效
    input  logic         fpga_clk,

    output logic         debug_wb_have_inst, // 当前时钟周期是否有指令写回
    output logic [31:0]  debug_wb_pc,        // 当前写回的指令的PC
    output logic         debug_wb_ena,       // 寄存器堆的写使能
    output logic [4:0]   debug_wb_reg,       // 写入的寄存器号
    output logic [31:0]  debug_wb_value      // 写入寄存器的值
);

    logic        cpu_clk = fpga_clk;
    
    // CPU与内存接口信号
    logic [31:0] pc;
    logic [31:0] instruction;
    logic [31:0] perip_addr;
    logic        perip_wen;
    logic [1:0]  perip_mask;
    logic [31:0] perip_wdata;
    logic [31:0] perip_rdata;
    
    // CPU核心实例化
    myCPU Core_cpu (
        .cpu_rst            (fpga_rst),
        .cpu_clk            (cpu_clk),
        
        // IROM接口
        .pc                 (pc),
        .instruction        (instruction),
        
        // DRAM接口
        .perip_addr         (perip_addr),
        .perip_wen          (perip_wen),
        .perip_mask         (perip_mask),
        .perip_wdata        (perip_wdata),
        .perip_rdata        (perip_rdata),
        
        // 调试接口
        .debug_wb_have_inst (debug_wb_have_inst),
        .debug_wb_pc        (debug_wb_pc),
        .debug_wb_ena       (debug_wb_ena),
        .debug_wb_reg       (debug_wb_reg),
        .debug_wb_value     (debug_wb_value)
    );
    
    // 指令存储器IROM实例化
    IROM Mem_IROM (
        .a          (pc[15:2]),     // 按字寻址，忽略低2位
        .spo        (instruction)   // 输出指令
    );

    // 数据存储器DRAM实例化
    DRAM Mem_DRAM (
        .clk        (cpu_clk),      // 时钟信号
        .a          (perip_addr[15:2]), // 按字寻址，忽略低2位
        .spo        (perip_rdata),  // 读取数据
        .we         (perip_wen),    // 写使能
        .d          (perip_wdata)   // 写入数据
    );
    
endmodule