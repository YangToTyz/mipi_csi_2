`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/05/08 21:57:22
// Design Name: 
// Module Name: mipi_csi_module
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


module mipi_csi_module(
    input   wire            core_clk,
    input   wire            core_rst_n,

    input   wire            clk_rxp,
    input   wire            clk_rxn,
    input   wire    [3:0]   data_rxp,
    input   wire    [3:0]   data_rxn,

    output  wire            cl_stopstate,
    input   wire            cl_enable,
    output  wire    [3:0]   dl_stopstate,
    input   wire    [3:0]   dl_enable,
    output  wire    [3:0]   dl_rxsynchs,

    output  wire            rxbyteclkhs,
    output  wire    [31:0]  dl_rxdatahs,
    output  wire            dl_rxvalidhs,


    input wire f_sync,
    input  wire             o_payload_vaild,
    input  wire     [47:0]  o_payload_data, // ★ 纯数据：4个 RAW12 像素
    input  wire             o_payload_last, // ★ 新增端口：TLAST 行结束标志 (一包数据的最后一拍)
    input  wire             o_payload_strat,
    input  wire     [9:0]  o_payload_dest

    // output wire [47:0] phy_rx_data_hs,
    // output wire [3:0] phy_rx_valid_hs

    );



    wire clk_hs_750m;
    
    // 暴露给后级的字节时钟
    wire clk_div_187p5m;
    assign rxbyteclkhs = clk_div_187p5m;
    
    wire [3:0]lane_raw_valid;
    wire [31:0]lane_raw_data;

    //==================================================
    // 0. 核心枢纽：IDELAYCTRL (UltraScale必须实例化)
    //==================================================
    // wire idelayctrl_rdy;
    // IDELAYCTRL #(
    //     .SIM_DEVICE("ULTRASCALE")
    // ) IDELAYCTRL_inst (
    //     .RDY    (idelayctrl_rdy),
    //     .REFCLK (core_clk),
    //     .RST    (~rst_n)
    // );

    //==================================================
    // 1. 实例化 Clock Lane
    //==================================================
    mipi_dphy_clock_lane u_clock_lane (
        .clk_p          (clk_rxp),
        .clk_n          (clk_rxn),
        .clk_hs_750m    (clk_hs_750m),
        .clk_div_187p5m (clk_div_187p5m),
        .lp_clk_p       (), // 顶层暂不外接
        .lp_clk_n       ()
    );
    wire state_rst;
    vio_state u_vio_state(
        .clk(core_clk),
        .probe_out0(state_rst)
    );
    //==================================================
    // 2. 实例化 4 个 Data Lane 
    //==================================================
    wire [3:0]lp_is_stop;
    genvar i;
    generate
        for (i = 0; i < 4; i = i + 1) begin : gen_data_lanes
            mipi_dphy_data_lane u_data_lane (
                .clk(core_clk),
                .rst_n         (core_rst_n & state_rst), // IDELAYCTRL 准备好才释放复位
                .clk_hs        (clk_hs_750m),
                .clk_div       (clk_div_187p5m),
                .data_p        (data_rxp[i]),
                .data_n        (data_rxn[i]),
                
                // 数据与 valid 映射到对应的 Byte 槽位
                .rx_byte_data  (lane_raw_data[i*8 +: 8]), 
                .rx_valid      (lane_raw_valid[i]),
                .lp_is_stop    (lp_is_stop[i]),
                .tuning_done   ()
            );
        end
    endgenerate

reg [15:0]last_cnt;
reg fsync_d;
always @(posedge clk_div_187p5m) begin
    fsync_d <= f_sync;
    if(!fsync_d)begin
        last_cnt<=16'd0;
    end
    else if(o_payload_last)begin
        last_cnt<=last_cnt+1'b1;
    end
end

ila_data4 u_ila_data4(
    .clk(clk_div_187p5m),
    .probe0(lane_raw_data[7:0]),
    .probe1(lane_raw_valid[0] ),
    .probe2(lane_raw_data[15:8]),
    .probe3(lane_raw_valid[1] ),
    .probe4(lane_raw_data[23:16]),
    .probe5(lane_raw_valid[2] ),
    .probe6(lane_raw_data[31:24]),
    .probe7(lane_raw_valid[3] ),
    .probe8(lp_is_stop),
    .probe9 (o_payload_vaild),
    .probe10(o_payload_data),
    .probe11(dl_rxdatahs_reg),
    .probe12(dl_rxvalidhs_reg),
    .probe13(o_payload_last),
    .probe14(o_payload_strat),
    .probe15(f_sync),
    .probe16(last_cnt)
);

//==================================================
    // ★ 3. MIPI 4-Lane Deskew (通道对齐缓冲逻辑) ★
    //==================================================
    // 采用寄存器数组搭建 4 个深度为 16 的小型 FIFO
    reg [7:0] deskew_fifo_0 [0:15];
    reg [7:0] deskew_fifo_1 [0:15];
    reg [7:0] deskew_fifo_2 [0:15];
    reg [7:0] deskew_fifo_3 [0:15];

    reg [3:0] wr_ptr_0, wr_ptr_1, wr_ptr_2, wr_ptr_3;
    reg [3:0] rd_ptr_0, rd_ptr_1, rd_ptr_2, rd_ptr_3;

    // FIFO 判空条件
    wire empty_0 = (wr_ptr_0 == rd_ptr_0);
    wire empty_1 = (wr_ptr_1 == rd_ptr_1);
    wire empty_2 = (wr_ptr_2 == rd_ptr_2);
    wire empty_3 = (wr_ptr_3 == rd_ptr_3);

    // 当 4 个通道全都接收到数据时，标志置 1
    wire all_not_empty = (~empty_0) & (~empty_1) & (~empty_2) & (~empty_3);

    // ----------------------------------------------------
    // ★ 核心修复：更严格的 FIFO 清空逻辑 ★
    // ----------------------------------------------------
    // 新增：只要 4 个通道的 valid 全都为 0，说明一定处于包的间隙，强制清零
    wire all_invalid = ~(lane_raw_valid[0] | lane_raw_valid[1] | lane_raw_valid[2] | lane_raw_valid[3]);
    
    // 只要有任何一个通道进入 Stop 状态，或者所有通道均无效，代表包结束，清空指针
    wire deskew_rst = (|lp_is_stop) | all_invalid; 

    // 对齐后的输出寄存器
    reg [31:0] dl_rxdatahs_reg;
    reg        dl_rxvalidhs_reg;

    always @(posedge clk_div_187p5m or negedge core_rst_n) begin
        if (!core_rst_n) begin
            wr_ptr_0 <= 4'd0; rd_ptr_0 <= 4'd0;
            wr_ptr_1 <= 4'd0; rd_ptr_1 <= 4'd0;
            wr_ptr_2 <= 4'd0; rd_ptr_2 <= 4'd0;
            wr_ptr_3 <= 4'd0; rd_ptr_3 <= 4'd0;
            dl_rxvalidhs_reg <= 1'b0;
            dl_rxdatahs_reg  <= 32'd0;
        end 
        else if (deskew_rst) begin // <--- 使用新的强制复位条件
            // 包结束（包间隙），清零指针以丢弃上个包尾部的残留噪声碎片
            wr_ptr_0 <= 4'd0; rd_ptr_0 <= 4'd0;
            wr_ptr_1 <= 4'd0; rd_ptr_1 <= 4'd0;
            wr_ptr_2 <= 4'd0; rd_ptr_2 <= 4'd0;
            wr_ptr_3 <= 4'd0; rd_ptr_3 <= 4'd0;
            dl_rxvalidhs_reg <= 1'b0;
        end 
        else begin
            // ----------------------------------------------------
            // 步骤 A: 独立写。哪一个通道的数据有效，就写哪一个的 FIFO
            // ----------------------------------------------------
            if (lane_raw_valid[0]) begin
                deskew_fifo_0[wr_ptr_0] <= lane_raw_data[7:0];
                wr_ptr_0 <= wr_ptr_0 + 1'b1;
            end
            if (lane_raw_valid[1]) begin
                deskew_fifo_1[wr_ptr_1] <= lane_raw_data[15:8];
                wr_ptr_1 <= wr_ptr_1 + 1'b1;
            end
            if (lane_raw_valid[2]) begin
                deskew_fifo_2[wr_ptr_2] <= lane_raw_data[23:16];
                wr_ptr_2 <= wr_ptr_2 + 1'b1;
            end
            if (lane_raw_valid[3]) begin
                deskew_fifo_3[wr_ptr_3] <= lane_raw_data[31:24];
                wr_ptr_3 <= wr_ptr_3 + 1'b1;
            end

            // ----------------------------------------------------
            // 步骤 B: 同步读。只有当 4 个通道都就绪了，才进行拼接
            // ----------------------------------------------------
            if (all_not_empty) begin
                dl_rxdatahs_reg[7:0]   <= deskew_fifo_0[rd_ptr_0];
                dl_rxdatahs_reg[15:8]  <= deskew_fifo_1[rd_ptr_1];
                dl_rxdatahs_reg[23:16] <= deskew_fifo_2[rd_ptr_2];
                dl_rxdatahs_reg[31:24] <= deskew_fifo_3[rd_ptr_3];
                
                rd_ptr_0 <= rd_ptr_0 + 1'b1;
                rd_ptr_1 <= rd_ptr_1 + 1'b1;
                rd_ptr_2 <= rd_ptr_2 + 1'b1;
                rd_ptr_3 <= rd_ptr_3 + 1'b1;

                dl_rxvalidhs_reg <= 1'b1;
            end else begin
                dl_rxvalidhs_reg <= 1'b0;
            end
        end
    end

    assign dl_rxdatahs  = dl_rxdatahs_reg;
    assign dl_rxvalidhs = dl_rxvalidhs_reg;
    // //==================================================
    // // ★ 3. MIPI 4-Lane Deskew (通道对齐缓冲逻辑) ★
    // //==================================================
    // // 采用寄存器数组搭建 4 个深度为 16 的小型 FIFO
    // reg [7:0] deskew_fifo_0 [0:15];
    // reg [7:0] deskew_fifo_1 [0:15];
    // reg [7:0] deskew_fifo_2 [0:15];
    // reg [7:0] deskew_fifo_3 [0:15];

    // reg [3:0] wr_ptr_0, wr_ptr_1, wr_ptr_2, wr_ptr_3;
    // reg [3:0] rd_ptr_0, rd_ptr_1, rd_ptr_2, rd_ptr_3;

    // // FIFO 判空条件
    // wire empty_0 = (wr_ptr_0 == rd_ptr_0);
    // wire empty_1 = (wr_ptr_1 == rd_ptr_1);
    // wire empty_2 = (wr_ptr_2 == rd_ptr_2);
    // wire empty_3 = (wr_ptr_3 == rd_ptr_3);

    // // 当 4 个通道全都接收到数据时，标志置 1
    // wire all_not_empty = (~empty_0) & (~empty_1) & (~empty_2) & (~empty_3);

    // // 只要有任何一个通道进入了 Stop 状态(LP-11)，代表一包数据彻底结束，清空指针
    // wire pkt_ended = |lp_is_stop; 

    // // 对齐后的输出寄存器
    // reg [31:0] dl_rxdatahs_reg;
    // reg        dl_rxvalidhs_reg;

    // always @(posedge clk_div_187p5m or negedge core_rst_n) begin
    //     if (!core_rst_n) begin
    //         wr_ptr_0 <= 4'd0; rd_ptr_0 <= 4'd0;
    //         wr_ptr_1 <= 4'd0; rd_ptr_1 <= 4'd0;
    //         wr_ptr_2 <= 4'd0; rd_ptr_2 <= 4'd0;
    //         wr_ptr_3 <= 4'd0; rd_ptr_3 <= 4'd0;
    //         dl_rxvalidhs_reg <= 1'b0;
    //         dl_rxdatahs_reg  <= 32'd0;
    //     end 
    //     else if (pkt_ended) begin
    //         // 包结束（包间隙），清零指针以丢弃残留碎片并重置状态
    //         wr_ptr_0 <= 4'd0; rd_ptr_0 <= 4'd0;
    //         wr_ptr_1 <= 4'd0; rd_ptr_1 <= 4'd0;
    //         wr_ptr_2 <= 4'd0; rd_ptr_2 <= 4'd0;
    //         wr_ptr_3 <= 4'd0; rd_ptr_3 <= 4'd0;
    //         dl_rxvalidhs_reg <= 1'b0;
    //     end 
    //     else begin
    //         // ----------------------------------------------------
    //         // 步骤 A: 独立写。哪一个通道的数据有效，就写哪一个的 FIFO
    //         // ----------------------------------------------------
    //         if (lane_raw_valid[0]) begin
    //             deskew_fifo_0[wr_ptr_0] <= lane_raw_data[7:0];
    //             wr_ptr_0 <= wr_ptr_0 + 1'b1;
    //         end
    //         if (lane_raw_valid[1]) begin
    //             deskew_fifo_1[wr_ptr_1] <= lane_raw_data[15:8];
    //             wr_ptr_1 <= wr_ptr_1 + 1'b1;
    //         end
    //         if (lane_raw_valid[2]) begin
    //             deskew_fifo_2[wr_ptr_2] <= lane_raw_data[23:16];
    //             wr_ptr_2 <= wr_ptr_2 + 1'b1;
    //         end
    //         if (lane_raw_valid[3]) begin
    //             deskew_fifo_3[wr_ptr_3] <= lane_raw_data[31:24];
    //             wr_ptr_3 <= wr_ptr_3 + 1'b1;
    //         end

    //         // ----------------------------------------------------
    //         // 步骤 B: 同步读。只有当 4 个通道都就绪了，才进行拼接
    //         // ----------------------------------------------------
    //         if (all_not_empty) begin
    //             dl_rxdatahs_reg[7:0]   <= deskew_fifo_0[rd_ptr_0];
    //             dl_rxdatahs_reg[15:8]  <= deskew_fifo_1[rd_ptr_1];
    //             dl_rxdatahs_reg[23:16] <= deskew_fifo_2[rd_ptr_2];
    //             dl_rxdatahs_reg[31:24] <= deskew_fifo_3[rd_ptr_3];
                
    //             rd_ptr_0 <= rd_ptr_0 + 1'b1;
    //             rd_ptr_1 <= rd_ptr_1 + 1'b1;
    //             rd_ptr_2 <= rd_ptr_2 + 1'b1;
    //             rd_ptr_3 <= rd_ptr_3 + 1'b1;

    //             dl_rxvalidhs_reg <= 1'b1;
    //         end else begin
    //             // 如果任意一个通道没有数据，不输出有效标志位
    //             dl_rxvalidhs_reg <= 1'b0;
    //         end
    //     end
    // end

    // // 将对齐后的内部寄存器连接到给解码器模块的端口上
    // // 注意：顶层中 dl_rxvalidhs 必须是单一的 1-bit 信号 (不要写成 wire [3:0])
    // assign dl_rxdatahs  = dl_rxdatahs_reg;
    // assign dl_rxvalidhs = dl_rxvalidhs_reg;




    
endmodule
