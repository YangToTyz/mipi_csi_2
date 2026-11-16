`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: mipi_csi_packet_decoder
// Description: MIPI RAW12 Decoder with Clock Domain Crossing (rxbyteclkhs -> clk)
//////////////////////////////////////////////////////////////////////////////////

module mipi_csi_packet_decoder(
    input   wire            clk,            // 系统读取时钟
    input   wire            rst_n,          // 异步复位

    input   wire            rxbyteclkhs,    // MIPI 字节时钟 (写入时钟)

    input   wire    [3:0]   dl_rxsynchs,
    input   wire    [31:0]  dl_rxdatahs,
    input   wire            dl_rxvalidhs,

    output  reg             o_payload_vaild,
    output  reg     [47:0]  o_payload_data, // ★ 纯数据：4个 RAW12 像素
    output  reg             o_payload_last, // ★ 新增端口：TLAST 行结束标志 (一包数据的最后一拍)
    output  reg             o_payload_strat,
    output  reg     [5:0]   dt,
    output  reg     [3:0]   vc 
);


wire [23:0] hdr = dl_rxdatahs[23:0];
wire [7:0]  ecc_exp;

// 直接调用标准公式
assign ecc_exp[0] = hdr[0]^hdr[1]^hdr[2]^hdr[4]^hdr[5]^hdr[7]^hdr[10]^hdr[11]^hdr[13]^hdr[16]^hdr[20]^hdr[21]^hdr[22]^hdr[23];
assign ecc_exp[1] = hdr[0]^hdr[1]^hdr[3]^hdr[4]^hdr[6]^hdr[8]^hdr[10]^hdr[12]^hdr[14]^hdr[17]^hdr[20]^hdr[21]^hdr[22]^hdr[23];
assign ecc_exp[2] = hdr[0]^hdr[2]^hdr[3]^hdr[5]^hdr[6]^hdr[9]^hdr[11]^hdr[12]^hdr[15]^hdr[18]^hdr[20]^hdr[21]^hdr[22];
assign ecc_exp[3] = hdr[1]^hdr[2]^hdr[3]^hdr[7]^hdr[8]^hdr[9]^hdr[13]^hdr[14]^hdr[15]^hdr[19]^hdr[20]^hdr[21]^hdr[23];
assign ecc_exp[4] = hdr[4]^hdr[5]^hdr[6]^hdr[7]^hdr[8]^hdr[9]^hdr[16]^hdr[17]^hdr[18]^hdr[19]^hdr[20]^hdr[22]^hdr[23];
assign ecc_exp[5] = hdr[10]^hdr[11]^hdr[12]^hdr[13]^hdr[14]^hdr[15]^hdr[16]^hdr[17]^hdr[18]^hdr[19]^hdr[21]^hdr[22]^hdr[23];
assign ecc_exp[6] = 1'b0;
assign ecc_exp[7] = 1'b0;

// 比对计算出的 ECC 与线上传来的 dl_rxdatahs[31:24]
wire hdr_ecc_ok = ((dl_rxdatahs[5:0] == 6'h2c) && (dl_rxdatahs[31:24] == ecc_exp) && dl_rxvalidhs && (ecc_exp!=8'd0));

always @(posedge rxbyteclkhs) begin
    dl_rxdatahs_d<=dl_rxdatahs;
    dl_rxvalidhs_d<=dl_rxvalidhs;
end

//=========================================================
// 1. rxbyteclkhs 时钟域：解析包头并将载荷写入异步 FIFO
//=========================================================
localparam ST_IDLE    = 3'd0;
localparam ST_PAYLOAD = 3'd1;
localparam ST_FOOTER  = 3'd2;

reg [2:0]  wr_state;
reg [15:0] word_cnt;

// 寄存器缓存，用于跨时钟域传递
reg [5:0]  dt_reg;
reg [3:0]  vc_reg;

// FIFO 写端信号
reg        fifo_wren;
reg [32:0] fifo_din; // [32] = is_last_word, [31:0] = data
reg frame_first;

reg    [31:0]  dl_rxdatahs_d;
reg            dl_rxvalidhs_d;
always @(posedge rxbyteclkhs or negedge rst_n) begin
    
    if (~rst_n) begin
        wr_state <= ST_IDLE;
        fifo_wren <= 1'b0;
        fifo_din <= 33'd0;
        word_cnt <= 16'd0;
        dt_reg <= 6'd0;
        vc_reg <= 4'd0;
        frame_first<=1'b0;
    end
    else if(hdr_ecc_ok)begin
        wr_state <= ST_IDLE;
        fifo_wren <= 1'b0;
        fifo_din <= 33'd0;
        word_cnt <= 16'd0;
        dt_reg <= 6'd0;
        vc_reg <= 4'd0;
        frame_first<=1'b0;
    end
    else begin
        fifo_wren <= 1'b0; // 默认不写 FIFO

        case (wr_state)
            ST_IDLE: begin
                // 收到包头 (PH)，且 Data Type = 0x2C (RAW12)
                if(dl_rxvalidhs_d && dl_rxdatahs_d[5:0] == 6'h00)begin
                    frame_first<=1'b1;
                end
                else if (dl_rxvalidhs_d && dl_rxdatahs_d[5:0] == 6'h2C ) begin
                    wr_state <= ST_PAYLOAD;
                    word_cnt <= dl_rxdatahs_d[23:8];
                    dt_reg   <= dl_rxdatahs_d[5:0];
                    vc_reg   <= {dl_rxdatahs_d[31:30], dl_rxdatahs_d[7:6]};
                end
            end

            ST_PAYLOAD: begin
                if (dl_rxvalidhs_d) begin
                    fifo_wren <= 1'b1;
                    frame_first<=1'b0;
                    
                    if (word_cnt <= 16'd4) begin
                        // 最后一拍载荷数据，拉高 is_last_word 标志 (第32位)
                        fifo_din <= {1'b1, dl_rxdatahs_d};
                        wr_state <= ST_FOOTER;
                    end else begin
                        fifo_din <= {1'b0, dl_rxdatahs_d};
                        word_cnt <= word_cnt - 16'd4;
                    end
                end
            end

            ST_FOOTER: begin
                // 等待 rxvalidhs 拉低，或者直接回到 IDLE 准备下一包
                if (!dl_rxvalidhs_d) begin
                    wr_state <= ST_IDLE;
                end
            end
        endcase
    end
end

reg  frame_first_r1, frame_first_r2;
always @(posedge rxbyteclkhs) begin
    frame_first_r1 <= frame_first;
    if(frame_first && ~frame_first_r1)begin
        frame_first_r2<=~frame_first_r2;
    end
end

//=========================================================
// 2. XPM 异步 FIFO (解决跨时钟域问题)
//=========================================================
wire        fifo_empty,fifo_full;
wire [32:0] fifo_rdata;
wire        fifo_rden;

xpm_fifo_async #(
    .FIFO_MEMORY_TYPE("auto"),
    .FIFO_WRITE_DEPTH(512),      // 深度可以根据需要调整
    .READ_DATA_WIDTH(33),
    .WRITE_DATA_WIDTH(33),
    .FIFO_READ_LATENCY(1),       // 标准读取延迟
    .READ_MODE("fwft"),
    .USE_ADV_FEATURES("0000")
) u_xpm_fifo_async (
    .rst        (~rst_n),
    .wr_clk     (rxbyteclkhs),
    .wr_en      (fifo_wren),
    .din        (fifo_din),
    .rd_clk     (rxbyteclkhs),
    .rd_en      (fifo_rden),
    .dout       (fifo_rdata),
    .empty      (fifo_empty),
    .full       (fifo_full),
    .sleep      (1'b0),
    .injectdbiterr(1'b0),
    .injectsbiterr(1'b0)
);

//=========================================================
// 3. 静态配置信号跨时钟域 (dt, vc)
//=========================================================
reg [5:0] dt_sys_r1, dt_sys_r2;
reg [3:0] vc_sys_r1, vc_sys_r2;

reg  frame_first_d1, frame_first_d2;
always @(posedge rxbyteclkhs) begin
    dt_sys_r1 <= dt_reg; 
    dt_sys_r2 <= dt_sys_r1;
    vc_sys_r1 <= vc_reg; 
    vc_sys_r2 <= vc_sys_r1;
    dt <= dt_sys_r2;
    vc <= vc_sys_r2;
    frame_first_d1<=frame_first_r2;
    frame_first_d2<=frame_first_d1;
end

//=========================================================
// 4. clk 时钟域：Gearbox 齿轮箱 (32-bit 转 48-bit)
//=========================================================
reg [1:0]  gb_state;
reg [31:0] gb_buf;

wire        fifo_valid   = ~fifo_empty;
wire        is_last_word = fifo_rdata[32];
wire [31:0] current_data = fifo_rdata[31:0];

assign fifo_rden = ~fifo_empty; // 只要有数据就一直读

reg frame_start;
reg o_payload_strat;
always @(posedge rxbyteclkhs) begin
    if(frame_first_d2 != frame_first_d1)begin
        o_payload_strat<=1'b1;
    end
    else begin
        o_payload_strat<=1'b0;
    end
    // if(frame_start && o_payload_vaild)begin
    //     frame_start<=1'b0;
    //     o_payload_strat<=1'b1;
    // end
    // else if(!frame_first_r2 && frame_first_r1)begin
    //     frame_start<=1'b1;
    //     o_payload_strat<=1'b0;
    // end
    // else begin
    //     frame_start <=frame_start;
    //     o_payload_strat<=1'b0;
    // end
    
end

always @(posedge rxbyteclkhs or negedge rst_n) begin
    if (~rst_n) begin
        gb_state        <= 2'd0;
        o_payload_vaild <= 1'b0;
        o_payload_data  <= 48'd0;
        o_payload_last  <= 1'b0; // ★ 初始化 Last 信号
    end else begin
        

        if (fifo_valid) begin
            case (gb_state)
                2'd0: begin
                    gb_buf <= current_data; // 缓存前 4 个字节
                    if (is_last_word) begin
                        gb_state <= 2'd0;   // 异常长度处理，重新同步
                    end else begin
                        gb_state <= 2'd1;
                    end
                end

                2'd1: begin
                    o_payload_vaild <= 1'b1;
                    // ★ 取当前拍的低 2 字节，拼接缓存的 4 字节，形成完整的 6 字节 (48-bit)
                    o_payload_data  <= {current_data[15:0], gb_buf[31:0]};
                    
                    if (is_last_word) begin
                        o_payload_last <= 1'b1; // ★ 触发独立的包尾 Last 信号
                        gb_state <= 2'd0;
                    end else begin
                        gb_buf[15:0] <= current_data[31:16]; // 缓存剩下的高 2 字节
                        gb_state <= 2'd2;
                    end
                end

                2'd2: begin
                    o_payload_vaild <= 1'b1;
                    // ★ 取当前拍的完整 4 字节，拼接缓存的 2 字节，形成 6 字节 (48-bit)
                    o_payload_data  <= {current_data[31:0], gb_buf[15:0]};
                    
                    if (is_last_word) begin
                        o_payload_last <= 1'b1; // ★ 触发独立的包尾 Last 信号
                    end 
                    // 每读满 3 拍（12字节 = 输出2次 48bit），状态回到 0 闭环
                    gb_state <= 2'd0; 
                end
            endcase
        end
        else begin
            o_payload_vaild <= 1'b0; // 默认单拍拉低
            o_payload_last  <= 1'b0; // ★ 默认单拍拉低
        end
    end
end

//=========================================================
// 5. ILA 测试模块
//=========================================================
// ila_mipi_top u_ila_packet(
//     .clk    (rxbyteclkhs),
//     .probe0 (o_payload_vaild), // clk 域
//     .probe1 (o_payload_data),  // clk 域 (48 bit)
//     .probe2 (dt),              // clk 域
//     .probe3 (vc),              // clk 域
//     .probe4 (o_payload_last),  // ★ 新增：clk 域下的 last 信号
//     .probe5 (dl_rxdatahs),     // 警告：rx时钟域信号 (跨域仅供ILA参考)
//     .probe6 (dl_rxvalidhs),     // 警告：rx时钟域信号 (跨域仅供ILA参考)
//     .probe7 (fifo_din[32]),
//     .probe8(hdr_ecc_ok),
//     .probe9(wr_state),
//     .probe10(word_cnt),
//     .probe11(ecc_exp)
// );

endmodule