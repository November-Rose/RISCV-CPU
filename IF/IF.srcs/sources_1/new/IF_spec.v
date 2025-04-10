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
module IF(

    //========== 时钟与复位 ==========//
    input         clk,        // 全局时钟（上升沿触发）
    input         rst_n,      // 异步低电平复位（0复位，1正常工作）
    //========== 指令存储器接口 ==========//
    output [31:0] instr_addr, // 指令存储器地址（4字节对齐，addr[1:0]=00）
    input  [31:0] instr_data, // 指令存储器数据（32位）
    //========== 分支预测器接口 ==========//
    input         f_en,       // 分支预测使能（1表示预测跳转）
    input  [31:0] f_addr,     // 预测跳转地址（来自分支预测器）
    //========== 流水线控制 ==========//
    input         flush,      // 冲刷信号（分支预测错误时置1）
    input         blocking,   // 阻塞信号（数据冲突时置1）
    //========== 输出 ==========//  
    output reg [31:0] addr    // 当前PC值（按4字节对齐，addr[1:0]=00）
    
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
    output reg [31:0] instrmem_addr    // 当前PC值（按4字节对齐，addr[1:0]=00）
);
    always @(posedge clk) begin
        if(!rst_n) begin
            instrmem_addr <= 32'h0000_0000; //复位时PC值为0
        end else if (new_addr_en) begin
            instrmem_addr <= new_PC_addr; //新地址有效时更新PC值
        end 
    end
endmodule

module PC_MUX(
    input         instrmem_addr,  //原先的PC值
    input         pred_f_en,       // 分支预测使能（1表示预测跳转）
    input  [31:0] pred_f_addr,     // 预测跳转地址（来自分支预测器）
    input         checkpre_flush,      // 冲刷信号（分支预测错误时置1）
    input  [31:0] checkpre_flush_addr,   // CHANGE：新增冲刷地址（分支预测错误时的PC值）
    output reg [31:0] new_PC_addr
);
    always @(*) begin
        if (checkpre_flush) begin
           new_PC_addr = checkpre_flush_addr; //冲刷信号有效时使用冲刷地址
        end else if (pred_f_en) begin
            new_PC_addr = pred_f_addr; //分支预测使能时使用预测地址
        end else begin
            new_PC_addr = new_PC_addr + 4; //默认情况下PC值加4
        end
    end
endmodule

//CHANGE:该模块用于产生PC_reg模块的new_addr_en信号,其中的input需要由数据相关性检测器和控制冒险检测器提供。为此需要特别注意可能产生冒险的地方。
//NOTES:此处有两个需要由下级流水给出的信号
module PC_enable(
    input        predecode_stall,//predecode阶段的阻塞信号
    input        data_hazard_stall,//数据冒险的阻塞信号
    input        control_hazard_stall,//控制冒险的阻塞信号
    output       new_addr_en //新地址使能信号
);
assign new_addr_en = !predecode_stall && !data_hazard_stall && !control_hazard_stall; //当三个信号都为0时，new_addr_en为1
endmodule

module predecode(

);
endmodule

//CHANGE:原先的分支预测模块pred容易与predecode混淆，因此将其名称改为BPU（Branch Prediction Unit）
//拟采用Bi-Mode分支预测
module BPU (
    input wire clk,
    input wire rst_n,
    input wire [31:0] instrmem_addr,  // 指令地址
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
    assign prediction_index = instrmem_addr[7:0];
    assign selector_index = instrmem_addr[15:8];

    // 预测逻辑
    always @(*) begin
        if (selector_table[selector_index] >= 2'b10) begin
            // 选择T表
            pred_f_en = (T_table[prediction_index] >= 2'b10) ? 1'b1 : 1'b0;
        end else begin
            // 选择NT表
            pred_f_en = (NT_table[prediction_index] >= 2'b10) ? 1'b1 : 1'b0;
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
                if ((T_table[prediction_index] >= 2'b10 && brunch_taken) || (T_table[prediction_index] < 2'b10 && !brunch_taken)) begin
                    if (selector_table[selector_index] < 2'b11) begin
                        selector_table[selector_index] <= selector_table[selector_index] + 1;
                    end
                end else begin
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
                if ((NT_table[prediction_index] >= 2'b10 && brunch_taken) || (NT_table[prediction_index] < 2'b10 && !brunch_taken)) begin
                    if (selector_table[selector_index] < 2'b11) begin
                        selector_table[selector_index] <= selector_table[selector_index] + 1;
                    end
                end else begin
                    if (selector_table[selector_index] > 2'b00) begin
                        selector_table[selector_index] <= selector_table[selector_index] - 1;
                    end
                end
            end
        end
    end

endmodule    