`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/04/08 18:18:22
// Design Name: 
// Module Name: IF_spec
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

//README:为了代码的可读性与可维护性，我会尽可能地将大模块划分为几个小模块。同时为了不与spec文档产生过多冲突，我会尽量沿用spec文档中的变量名，并对新增的模块和变量予以注释说明
module IF_top(
    //========== 时钟与复位 ==========//
    input         clk,                // 全局时钟（上升沿触发）
    input         rst_n,              // 异步低电平复位（0复位，1正常工作）
    input  [31:0] instr_data,         // 指令存储器数据（32位）
    
    //========== 冒险控制 ==========//
    input         data_hazard_stall,   // 数据冒险阻塞信号
    input         control_hazard_stall,// 控制冒险阻塞信号
    
    //========== 分支预测接口 ==========//
    input  wire        brunch_taken,   // 分支实际跳转结果（来自交付单元）
    input  wire        update_en,      // 分支预测表更新使能
    input  wire [31:0] target_addr,    // 分支实际目标地址（来自执行阶段）
    
    //========== 流水线控制 ==========//
    input         flush,               // 冲刷信号（分支预测错误）
    input  [31:0] checkpre_flush_addr, // 冲刷恢复地址
    input         blocking,            // 全局阻塞信号
    
    //========== 输出 ==========//
    output [31:0] pc                   // 当前PC值（4字节对齐）
);

    //========== 内部信号声明 ==========//
    wire [31:0] new_PC_addr;          // 新PC地址
    wire        new_addr_en;          // PC更新使能
    wire        pred_f_en;            // 分支预测使能
    wire        btb_hit;              // BTB命中信号
    wire [31:0] predicted_target_addr;// BTB预测地址
    wire        jxx, bxx;             // 预解码控制信号

    //========== 模块实例化 ==========//
    // PC寄存器模块
    PC_reg pc_reg_inst (
        .clk          (clk),
        .rst_n        (rst_n),
        .new_addr_en  (new_addr_en),
        .new_PC_addr  (new_PC_addr),
        .pc           (pc)
    );

    // PC多路选择器
    PC_MUX pc_mux_inst (
        .pc                   (pc),
        .pred_f_en            (pred_f_en),
        .pred_f_addr          (predicted_target_addr),  // 使用BTB预测地址
        .btb_hit              (btb_hit),
        .checkpre_flush        (flush),
        .checkpre_flush_addr  (checkpre_flush_addr),
        .new_PC_addr          (new_PC_addr)
    );

    // PC更新使能生成
    PC_enable pc_enable_inst (
        .data_hazard_stall    (data_hazard_stall),
        .control_hazard_stall (control_hazard_stall),
        .new_addr_en          (new_addr_en)
    );

    // 指令预解码器
    predecode predecoder_inst (
        .instr_data           (instr_data),
        .jxx                  (jxx),
        .bxx                  (bxx)
    );

    // 分支预测单元（BPU）
    BPU bpu_inst (
        .clk           (clk),
        .rst_n         (rst_n),
        .jxx           (jxx),
        .bxx           (bxx),
        .pc            (pc),
        .brunch_taken  (brunch_taken),
        .update_en     (update_en),
        .pred_f_en     (pred_f_en)
    );

    // 分支目标缓冲（BTB）
    BTB #(
        .BTB_SIZE      (16),
        .ADDR_WIDTH    (32)
    ) btb_inst (
        .clk                  (clk),
        .rst_n                (rst_n),
        .jxx                  (jxx),
        .bxx                  (bxx),
        .pc                   (pc),
        .target_addr          (target_addr),
        .update_en            (update_en),
        .predicted_target_addr(predicted_target_addr),
        .btb_hit              (btb_hit)
    );
endmodule

module PC_reg (                         //原PC模块//
    //========== 时钟与复位 ==========//
    input         clk,        // 全局时钟（上升沿触发）
    input         rst_n,      // 异步低电平复位（0复位，1正常工作）
    /*CHANGE：为了PC_reg模块的简洁，将获得正确地址的逻辑独立出来，只将new_PC_addr传入
    //========== 分支预测接口 ==========//
    input         pred_f_en,       // 分支预测使能（1表示预测跳转）
    input  [31:0] pred_f_addr,     // 预测跳转地址（来自分支预测器）
    
    //========== 流水线控制 ==========//
    input         checkpre_flush,      // 冲刷信号（分支预测错误时置1）
    */
    /*CHANGE：阻塞信号由PC_enable模块接受，PC_enable输出new_addr_en信号
    input         feedforward_stall,   // 阻塞信号（数据冲突时置1）
    */
    input         new_addr_en,       // 新地址使能（1表示新地址有效）
    input  [31:0] new_PC_addr,          // 新地址
    //========== 输出 ==========//
    output reg [31:0] pc    // 当前PC值（按4字节对齐，addr[1:0]=00）
);
    always @(posedge clk) begin
        if(!rst_n) begin
            pc <= 32'h0000_0000; //复位时PC值为0
        end else if (new_addr_en) begin
            pc <= new_PC_addr; //新地址有效时更新PC值
        end 
    end
endmodule

module PC_MUX(
    input  [31:0] pc,  //原先的PC值
    input         pred_f_en,       // 分支预测使能（1表示预测跳转）
    input  [31:0] pred_f_addr,     // 预测跳转地址（来自分支预测器）
    input         btb_hit,      // BTB命中信号（1表示命中）
    input         checkpre_flush,      // 冲刷信号（分支预测错误时置1）
    input  [31:0] checkpre_flush_addr,   // CHANGE：新增冲刷地址（分支预测错误时的PC值）
    output reg [31:0] new_PC_addr
);
    always @(*) begin
        if (checkpre_flush) begin
           new_PC_addr = checkpre_flush_addr; //冲刷信号有效时使用冲刷地址
        end else if (pred_f_en && btb_hit) begin
            new_PC_addr = pred_f_addr; //分支预测使能时使用预测地址
        end else begin
            new_PC_addr = pc + 4; //默认情况下PC值加4
        end
    end
endmodule

//CHANGE:该模块用于产生PC_reg模块的new_addr_en信号,其中的input需要由数据相关性检测器和控制冒险检测器提供。为此需要特别注意可能产生冒险的地方。
//NOTES:此处有两个需要由下级流水给出的信号
module PC_enable(
    input        data_hazard_stall,//数据冒险的阻塞信号
    input        control_hazard_stall,//控制冒险的阻塞信号
    output       new_addr_en //新地址使能信号
);

assign new_addr_en = !data_hazard_stall && !control_hazard_stall; //当两个信号都为0时，new_addr_en为1
endmodule

module predecode(
    input [31:0] instr_data,
    output       jxx,
    output       bxx
);
localparam OPCODE_JAL    = 7'b1101111;  // JAL指令
localparam OPCODE_JALR   = 7'b1100111;  // JALR指令
localparam OPCODE_BRANCH = 7'b1100011;   // 分支指令

// ========================= 预解码逻辑 =========================
wire is_jal    = (instr_data[6:0] == OPCODE_JAL);    // JAL指令
wire is_jalr   = (instr_data[6:0] == OPCODE_JALR);   // JALR指令
wire is_branch = (instr_data[6:0] == OPCODE_BRANCH); // 分支指令

// 组合逻辑输出（立即识别指令类型）
assign jxx = is_jal | is_jalr;   // 合并J型指令信号
assign bxx = is_branch;          // 分支指令信号
endmodule

//CHANGE:原先的分支预测模块pred容易与predecode混淆，因此将其名称改为BPU（Branch Prediction Unit）
//拟采用Bi-Mode分支预测
//这是AI写的，可能还有逻辑需要改正
module BPU (
    input wire clk,
    input wire rst_n,
    input wire jxx,
    input wire bxx,
    input wire [31:0] pc,  // 指令地址
    input wire brunch_taken,  // NOTES:此信号需要由交付单元给出。分支指令实际是否跳转，1表示跳转，0表示不跳转。
    input wire update_en,  // NOTES:此信号需要由交付单元给出。当分支指令完成时，update_en为1，表示需要更新预测表
    output reg pred_f_en  // 预测结果，1表示跳转，0表示不跳转
);

    // 参数定义
    parameter TABLE_SIZE = 256;  // 预测表大小
    parameter SELECTOR_SIZE = 256;  // 选择器表大小
    parameter COUNTER_BITS = 2;  // 计数器位数

    // 定义T表、NT表和选择器表
    reg [COUNTER_BITS-1:0] T_table [TABLE_SIZE-1:0];
    reg [COUNTER_BITS-1:0] NT_table [TABLE_SIZE-1:0];
    reg [COUNTER_BITS-1:0] selector_table [SELECTOR_SIZE-1:0];

    // 计算索引
    wire [7:0] prediction_index;
    wire [7:0] selector_index;
    assign prediction_index = pc[7:0];
    assign selector_index = pc[15:8];

    // 预测逻辑
    always @(*) begin
        if (jxx && !bxx) begin
             pred_f_en = 1'b1;
        end else if(bxx && !jxx) begin
             if (selector_table[selector_index] >= 2'b10) begin
            // 选择T表
                pred_f_en = (T_table[prediction_index] >= 2'b10) ? 1'b1 : 1'b0;
            end else begin
            // 选择NT表
                pred_f_en = (NT_table[prediction_index] >= 2'b10) ? 1'b1 : 1'b0;
            end
        end else begin
            pred_f_en = 1'b0; // 非分支指令
        end
    end

    // 更新逻辑
    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // 复位，包含原来initial块的初始化逻辑
            for (i = 0; i < TABLE_SIZE; i = i + 1) begin
                T_table[i] <= 2'b11;  // 初始化为强可跳转状态
                NT_table[i] <= 2'b00; // 初始化为强不跳转状态
            end
            for (i = 0; i < SELECTOR_SIZE; i = i + 1) begin
                selector_table[i] <= 2'b10; // 初始化为弱选择T表状态
            end
        end else if (update_en) begin
            if (selector_table[selector_index] >= 2'b10) begin
                // 选择T表
                if (brunch_taken) begin
                    if (T_table[prediction_index] < 2'b11) begin
                        T_table[prediction_index] <= T_table[prediction_index] + 1;
                    end
                end else begin
                    if (T_table[prediction_index] > 2'b00) begin
                        T_table[prediction_index] <= T_table[prediction_index] - 1;
                    end
                end

                // 更新选择器
                //需要考虑特例情况
                if ((T_table[prediction_index] >= 2'b10 && brunch_taken) || (T_table[prediction_index] < 2'b10 && brunch_taken)) begin
                    if (selector_table[selector_index] < 2'b11) begin
                        selector_table[selector_index] <= selector_table[selector_index] + 1;
                    end
                end else if(T_table[prediction_index] >= 2'b10 && !brunch_taken) begin
                    if (selector_table[selector_index] > 2'b00) begin
                        selector_table[selector_index] <= selector_table[selector_index] - 1;
                    end
                end
            end else begin
                // 选择NT表
                if (brunch_taken) begin
                    if (NT_table[prediction_index] < 2'b11) begin
                        NT_table[prediction_index] <= NT_table[prediction_index] + 1;
                    end
                end else begin
                    if (NT_table[prediction_index] > 2'b00) begin
                        NT_table[prediction_index] <= NT_table[prediction_index] - 1;
                    end
                end

                // 更新选择器
                if ((NT_table[prediction_index] >= 2'b10 && !brunch_taken) || (NT_table[prediction_index] < 2'b10 && !brunch_taken)) begin
                    if (selector_table[selector_index] > 2'b00) begin
                        selector_table[selector_index] <= selector_table[selector_index] - 1;
                    end
                end else if(T_table[prediction_index] < 2'b10 && brunch_taken) begin
                    if (selector_table[selector_index] < 2'b11) begin
                        selector_table[selector_index] <= selector_table[selector_index] + 1;
                    end
                end
            end
        end
    end

endmodule 

//CHANGE:新增BTB模块用于预测分支指令跳转的地址
// BTB模块定义，使用参数化设计，方便调整BTB大小和地址位宽
module BTB #(
    parameter BTB_SIZE = 16,  // BTB的条目数量，可根据需要调整
    parameter ADDR_WIDTH = 32 // 地址位宽，可根据需要调整
) (
    input wire clk,           // 时钟信号，用于同步模块的操作
    input wire rst_n,         // 异步复位信号，低电平有效，用于将BTB模块复位到初始状态
    input wire jxx,
    input wire bxx,
    input wire [ADDR_WIDTH-1:0] pc, // 分支指令的地址，用于查找和存储操作
    //NOTES:target_addr在执行阶段产生，为预测地址与实际地址不一致时，分支指令的实际跳转地址
    input wire [ADDR_WIDTH-1:0] target_addr, // 分支指令的目标地址，用于存储操作
    //NOTES:update_en 信号的产生:执行阶段。比较实际的分支目标地址和 BTB 预测的目标地址。若两者不一致，表明预测错误，需要更新 BTB 中的信息；若一致，则说明预测正确。
    input wire update_en,     // 更新使能信号，用于控制是否更新BTB中的信息
    output reg [ADDR_WIDTH-1:0] predicted_target_addr, // 预测的分支目标地址，如果未命中则输出无效值
    output reg btb_hit            // 命中信号，表示是否在BTB中找到匹配的分支指令地址
);

    // BTB条目结构体
    // 存储分支指令的地址
    reg [ADDR_WIDTH-1:0] btb_branch_addr [BTB_SIZE-1:0];
    // 存储分支指令对应的目标地址
    reg [ADDR_WIDTH-1:0] btb_target_addr [BTB_SIZE-1:0];
    // 有效位，用于标记每个条目是否有效
    reg valid [BTB_SIZE-1:0];
    // 标志是否为分支指令
    wire is_branch;
    assign is_branch = jxx || bxx;

    // LRU计数器，用于实现最近最少使用（LRU）替换策略
    // lru_counter[i][j] 表示第i个条目相对于第j个条目的使用频率关系
    reg [BTB_SIZE-1:0] lru_counter [BTB_SIZE-1:0];

    integer i, j;
    integer empty_index;
    integer lru_index;
    integer max_lru;
    integer lru_sum;
    // 异步复位和正常操作逻辑
    always @(posedge clk or negedge rst_n) begin
        // 异步复位操作
        if (!rst_n) begin
            // 遍历BTB的所有条目
            for (i = 0; i < BTB_SIZE; i = i + 1) begin
                // 将所有条目的有效位置为0，表示无效
                valid[i] <= 1'b0;
                // 初始化LRU计数器
                for (j = 0; j < BTB_SIZE; j = j + 1) begin
                    lru_counter[i][j] <= 1'b0;
                end
            end
        end else begin
            if (is_branch) begin
                // 正常操作
                // 查找操作
                // 初始化命中信号为0，表示未命中
                btb_hit <= 1'b0;
                // 初始化预测的目标地址为全零，表示无效值
                predicted_target_addr <= {ADDR_WIDTH{1'b0}};
                // 遍历BTB的所有条目
                for (i = 0; i < BTB_SIZE; i = i + 1) begin
                    // 检查当前条目是否有效且分支指令地址匹配
                    if (valid[i] && btb_branch_addr[i] == pc) begin
                        // 命中，将命中信号置为1
                        btb_hit <= 1'b1;
                        // 输出预测的目标地址
                        predicted_target_addr <= btb_target_addr[i];
                        // 更新LRU计数器
                        for (j = 0; j < BTB_SIZE; j = j + 1) begin
                            if (j != i) begin
                                // 其他条目相对于当前条目更旧
                                lru_counter[j][i] <= 1'b1;
                            end else begin
                                // 当前条目相对于自身最新
                                lru_counter[j][i] <= 1'b0;
                            end
                        end
                    end
                end
            end

            // 存储操作
            if (is_branch && !btb_hit) begin
                empty_index = -1;
                lru_index = 0;
                max_lru = 0;
                // 查找空闲条目
                for (i = 0; i < BTB_SIZE; i = i + 1) begin
                    if (!valid[i]) begin
                        empty_index = i;
                        break;
                    end
                end
                // 如果没有空闲条目，使用LRU策略选择要替换的条目
                if (empty_index == -1) begin
                    for (i = 0; i < BTB_SIZE; i = i + 1) begin
                        lru_sum = 0;
                        // 计算每个条目的LRU计数器之和
                        for (j = 0; j < BTB_SIZE; j = j + 1) begin
                            lru_sum = lru_sum + lru_counter[i][j];
                        end
                        if (lru_sum > max_lru) begin
                            max_lru = lru_sum;
                            lru_index = i;
                        end
                    end
                    // 替换LRU条目
                    btb_branch_addr[lru_index] <= pc;
                    btb_target_addr[lru_index] <= target_addr;
                    valid[lru_index] <= 1'b1;
                    // 更新LRU计数器
                    for (j = 0; j < BTB_SIZE; j = j + 1) begin
                        if (j != lru_index) begin
                            lru_counter[j][lru_index] <= 1'b1;
                        end else begin
                            lru_counter[j][lru_index] <= 1'b0;
                        end
                    end
                end else begin
                    // 使用空闲条目存储新的分支信息
                    btb_branch_addr[empty_index] <= pc;
                    btb_target_addr[empty_index] <= target_addr;
                    valid[empty_index] <= 1'b1;
                    // 更新LRU计数器
                    for (j = 0; j < BTB_SIZE; j = j + 1) begin
                        if (j != empty_index) begin
                            lru_counter[j][empty_index] <= 1'b1;
                        end else begin
                            lru_counter[j][empty_index] <= 1'b0;
                        end
                    end
                end
            end

            // 更新操作
            if (update_en) begin
                // 如果预测错误，更新目标地址
                if (btb_hit && btb_target_addr[i] != target_addr) begin
                    for (i = 0; i < BTB_SIZE; i = i + 1) begin
                        if (valid[i] && btb_branch_addr[i] == pc) begin
                            btb_target_addr[i] <= target_addr;
                        end
                    end
                end
            end
        end
    end
endmodule    

