`timescale 1ns / 1ps

module mipi_dphy_data_lane (
    input  wire        rst_n,           
    input  wire        clk_hs,          // 750MHz 
    input  wire        clk_div,         // 187.5MHz 
    
    input  wire        data_p,
    input  wire        data_n,
    
    output reg  [7:0]  rx_byte_data,    // 解串对齐后的 8-bit 数据
    output reg         rx_valid,        // 数据有效标志位
    output wire        lp_is_stop,      // 当前处于 LP-11 状态指示
    output reg         tuning_done      // ★ 新增：眼图扫描完成标志
);

    wire hs_data_unbuf, hs_data_delayed;
    wire lp_data_p_async, lp_data_n_async;
    wire [7:0] iserdes_q;

    //==================================================
    // 1. IBUFDS_DPHY
    //==================================================
    IBUFDS_DPHY #(
        .IOSTANDARD("MIPI_DPHY_DCI")
    ) IBUFDS_DPHY_DATA_inst (
        .I       (data_p),
        .IB      (data_n),
        .O       (hs_data_unbuf), 
        .O_LP_P  (lp_data_p_async),
        .O_LP_N  (lp_data_n_async)
    );

    //==================================================
    // 2. IDELAYE3 (★ 改为 VAR_LOAD 动态模式)
    //==================================================
    reg        delay_load;
    reg  [8:0] delay_tap_in;
    wire [8:0] delay_tap_out;

    IDELAYE3 #(
        .CASCADE("NONE"),
        .DELAY_FORMAT("TIME"),
        .DELAY_TYPE("VAR_LOAD"), // ★ 允许运行时动态更改延迟
        .DELAY_VALUE(0),        
        .REFCLK_FREQUENCY(200.0), 
        .UPDATE_MODE("ASYNC")
    ) IDELAYE3_inst (
        .IDATAIN     (hs_data_unbuf),
        .DATAOUT     (hs_data_delayed),
        .CLK         (clk_div),
        .CE          (1'b0),
        .INC         (1'b0),
        .LOAD        (delay_load),   // ★ 状态机控制加载脉冲
        .CNTVALUEIN  (delay_tap_in), // ★ 状态机给定的 0~511 的 Tap 值
        .CNTVALUEOUT (delay_tap_out),
        .CASC_IN     (1'b0),
        .CASC_RETURN (1'b0),
        .CASC_OUT    (),
        .EN_VTC      (1'b0),         // 动态调参时需关闭 VTC
        .RST         (~rst_n)
    );

    //==================================================
    // 3. ISERDESE3
    //==================================================
    ISERDESE3 #(
        .DATA_WIDTH(8),
        .FIFO_ENABLE("FALSE"),
        .FIFO_SYNC_MODE("FALSE")
    ) ISERDESE3_inst (
        .D           (hs_data_delayed),
        .CLK         (clk_hs),
        .CLK_B       (~clk_hs), 
        .CLKDIV      (clk_div),
        .Q           (iserdes_q),     
        .FIFO_RD_CLK (1'b0),
        .FIFO_RD_EN  (1'b0),
        .FIFO_EMPTY  (),
        .RST         (~rst_n)
    );

    //==================================================
    // 4. LP 信号同步与停止位检测
    //==================================================
    reg [1:0] lp_dp_sync_reg, lp_dn_sync_reg;
    always @(posedge clk_div or negedge rst_n) begin
        if (!rst_n) begin
            lp_dp_sync_reg <= 2'b00;
            lp_dn_sync_reg <= 2'b00;
        end else begin
            lp_dp_sync_reg <= {lp_dp_sync_reg[0], lp_data_p_async};
            lp_dn_sync_reg <= {lp_dn_sync_reg[0], lp_data_n_async};
        end
    end
    assign lp_is_stop = (lp_dp_sync_reg[1] && lp_dn_sync_reg[1]);

    //==================================================
    // 5. Fabric Barrel Shifter (纯逻辑字对齐)
    //==================================================
    reg [7:0] q_prev;
    always @(posedge clk_div) begin
        q_prev <= iserdes_q;
    end
    wire [15:0] raw_stream = {iserdes_q, q_prev};
    
    reg [2:0] slip_cnt; 
    wire [7:0] aligned_data = raw_stream[slip_cnt +: 8];

    //==================================================
    // 6. 极速状态机与 valid 抓取
    //==================================================
    reg data_is_valid_internal;
    reg [1:0] sync_state;

    always @(posedge clk_div or negedge rst_n) begin
        if (!rst_n) begin
            sync_state             <= 2'd0;
            data_is_valid_internal <= 1'b0;
            slip_cnt               <= 3'd0;
        end else begin
            if (lp_is_stop) begin
                sync_state             <= 2'd0;
                data_is_valid_internal <= 1'b0;
            end else begin
                case (sync_state)
                    2'd0: sync_state <= 2'd1;
                    2'd1: begin
                        if      (raw_stream[0 +: 8] == 8'hB8) begin slip_cnt <= 3'd0; sync_state <= 2'd2; end
                        else if (raw_stream[1 +: 8] == 8'hB8) begin slip_cnt <= 3'd1; sync_state <= 2'd2; end
                        else if (raw_stream[2 +: 8] == 8'hB8) begin slip_cnt <= 3'd2; sync_state <= 2'd2; end
                        else if (raw_stream[3 +: 8] == 8'hB8) begin slip_cnt <= 3'd3; sync_state <= 2'd2; end
                        else if (raw_stream[4 +: 8] == 8'hB8) begin slip_cnt <= 3'd4; sync_state <= 2'd2; end
                        else if (raw_stream[5 +: 8] == 8'hB8) begin slip_cnt <= 3'd5; sync_state <= 2'd2; end
                        else if (raw_stream[6 +: 8] == 8'hB8) begin slip_cnt <= 3'd6; sync_state <= 2'd2; end
                        else if (raw_stream[7 +: 8] == 8'hB8) begin slip_cnt <= 3'd7; sync_state <= 2'd2; end
                    end
                    2'd2: begin
                        data_is_valid_internal <= 1'b1;
                    end
                endcase
            end
        end
    end

    //==================================================
    // 7. ★ 神级核心：动态眼图扫描 (Eye-Centering FSM) ★
    //==================================================
    localparam TUNE_IDLE      = 4'd0;
    localparam TUNE_SET_TAP   = 4'd1;
    localparam TUNE_WAIT_PKT  = 4'd2;
    localparam TUNE_CHECK_RES = 4'd3;
    localparam TUNE_EVALUATE  = 4'd4;
    localparam TUNE_CALC_MID  = 4'd5;
    localparam TUNE_DONE_ST   = 4'd6;

    reg [3:0] tune_state;
    reg [8:0] test_tap;
    reg [8:0] left_edge, right_edge;
    reg       in_window;
    reg       got_valid_in_pkt;
    
    // 超时计数器：防止摄像头没发数据导致死等
    reg [15:0] timeout_cnt;

    always @(posedge clk_div or negedge rst_n) begin
        if (!rst_n) begin
            tune_state   <= TUNE_IDLE;
            tuning_done  <= 1'b0;
            delay_load   <= 1'b0;
            delay_tap_in <= 9'd0;
            test_tap     <= 9'd0;
            in_window    <= 1'b0;
            left_edge    <= 9'd0;
            right_edge   <= 9'd0;
            rx_valid     <= 1'b0;
            rx_byte_data <= 8'h00;
        end else begin
            // 只有当调谐完成，才允许把真实的数据和 Valid 传递给外部
            if (tuning_done) begin
                rx_valid     <= data_is_valid_internal;
                rx_byte_data <= aligned_data;
            end else begin
                rx_valid     <= 1'b0;
            end

            // 调谐状态机
            case (tune_state)
                TUNE_IDLE: begin
                    // 启动扫描（也可以用外部信号触发）
                    tune_state  <= TUNE_SET_TAP;
                    test_tap    <= 9'd0;
                    in_window   <= 1'b0;
                    tuning_done <= 1'b0;
                end

                TUNE_SET_TAP: begin
                    // 设置测试延迟值
                    delay_tap_in <= test_tap;
                    delay_load   <= 1'b1; // 给一拍的高电平脉冲
                    tune_state   <= TUNE_WAIT_PKT;
                    timeout_cnt  <= 16'd0;
                end

                TUNE_WAIT_PKT: begin
                    delay_load       <= 1'b0;
                    got_valid_in_pkt <= 1'b0;
                    // 等待进入高速接收模式 (退出 LP-11)
                    if (!lp_is_stop) begin
                        tune_state <= TUNE_CHECK_RES;
                    end else begin
                        timeout_cnt <= timeout_cnt + 1;
                        if (timeout_cnt == 16'hFFFF) begin
                            // 超时，说明摄像头没开，保持当前状态死等
                        end
                    end
                end

                TUNE_CHECK_RES: begin
                    // 监控数据包期间，看有没有成功对齐 (抓到过一次 0xB8 就算成功)
                    if (data_is_valid_internal) begin
                        got_valid_in_pkt <= 1'b1;
                    end
                    
                    // 当一包数据传完（重新回到 LP-11），开始评估成绩
                    if (lp_is_stop) begin
                        tune_state <= TUNE_EVALUATE;
                    end
                end

                TUNE_EVALUATE: begin
                    if (got_valid_in_pkt) begin
                        // 测试成功！
                        if (!in_window) begin
                            left_edge <= test_tap; // 记录左边界
                            in_window <= 1'b1;
                        end
                    end else begin
                        // 测试失败！
                        if (in_window) begin
                            // 刚才还在窗口里，现在失败了，说明找到了右边界！
                            right_edge <= test_tap - 1;
                            tune_state <= TUNE_CALC_MID; // 已经找出一个完整的窗口，提前结束！
                        end
                    end

                    // 如果没找到边界，继续测下一个 Tap
                    if (tune_state == TUNE_EVALUATE) begin
                        if (test_tap == 9'd511) begin
                            // 扫到头了
                            right_edge <= 9'd511;
                            tune_state <= TUNE_CALC_MID;
                        end else begin
                            test_tap   <= test_tap + 1;
                            tune_state <= TUNE_SET_TAP;
                        end
                    end
                end

                TUNE_CALC_MID: begin
                    // 核心算法：中心点 = 左边界 + (右边界 - 左边界) / 2
                    delay_tap_in <= left_edge + ((right_edge - left_edge) >> 1);
                    delay_load   <= 1'b1; // 应用最完美的中心延迟
                    tune_state   <= TUNE_DONE_ST;
                end

                TUNE_DONE_ST: begin
                    delay_load  <= 1'b0;
                    tuning_done <= 1'b1; // 扫描结束！
                    // 此后不再扫描，除非触发复位
                end
            endcase
        end
    end

endmodule