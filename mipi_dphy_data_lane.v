`timescale 1ns / 1ps

module mipi_dphy_data_lane (
    input  wire        clk, 
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


reg [7:0]data_d;
reg error;
always @(posedge clk_div) begin
    data_d<=rx_byte_data;
    if(data_d == 8'hb8 && rx_valid==0)begin
        error<=1;
    end
    else begin
        error<=0;

    end
end
ila_mipi u_ila_mipi(
    .clk(clk_div),
    .probe0(rx_byte_data),
    .probe1(rx_valid),
    .probe2(iserdes_q),
    .probe3(tune_state),
    .probe4(delay_load ),
    .probe5(delay_tap_in),
    .probe6(delay_tap_out),
    .probe7(tuning_done),
    .probe8(left_edge),
    .probe9(right_edge),
    .probe10(lp_is_stop),
    .probe11(sync_state),
    .probe12(state_num)
);
// 在状态机变量定义处增加一个寄存器
    reg force_rst_iserdes;

    wire hs_data_unbuf, hs_data_delayed;
    wire lp_data_p_async, lp_data_n_async;
    wire [7:0] iserdes_q;

    //==================================================
    // 1. IBUFDS_DPHY
    //==================================================
    IBUFDS_DPHY #(
      .DIFF_TERM("TRUE"),             // Differential termination
      .IOSTANDARD("MIPI_DPHY_DCI"),         // I/O standard
      .SIM_DEVICE("ULTRASCALE_PLUS")  // Set the device version (ULTRASCALE_PLUS, ULTRASCALE_PLUS_ES1,
                                      // ULTRASCALE_PLUS_ES2)
    )
    IBUFDS_DPHY_inst (
        .HSRX_O(hs_data_unbuf),             // 1-bit output: HS RX output
        .LPRX_O_N(lp_data_n_async),         // 1-bit output: LP RX output (Slave)
        .LPRX_O_P(lp_data_p_async),         // 1-bit output: LP RX output (Master)
        .HSRX_DISABLE(1'b0), // 1-bit input: Disable control for HS mode
        .I(data_p),                       // 1-bit input: Data input0 PAD
        .IB(data_n),                     // 1-bit input: Data input1 PAD
        .LPRX_DISABLE(1'b0)  // 1-bit input: Disable control for LP mode
    );

// ila_750 u_ila_750(
//     .clk(clk_hs),
//     .probe0(hs_data_delayed),
//     .probe1(lp_is_stop),
//     .probe2(clk_div),
//     .probe3(0)
// );
    //==================================================
    // 2. IDELAYE3 (★ 改为 VAR_LOAD 动态模式)
    //==================================================
    reg        delay_load;
    reg  [8:0] delay_tap_in;
    wire [8:0] delay_tap_out;

    IDELAYE3 #(
        .CASCADE("NONE"),
        .DELAY_FORMAT("COUNT"),      // ★ 修改1：改为 COUNT 模式
        .DELAY_SRC("IDATAIN"),       // ★ 修改2：必须是 IDATAIN
        .DELAY_TYPE("VAR_LOAD"),     // 允许动态加载
        .DELAY_VALUE(0),
        .IS_CLK_INVERTED(1'b0),
        .IS_RST_INVERTED(1'b0),        
        // .REFCLK_FREQUENCY(250.0), // COUNT 模式下不再需要此参数
        .UPDATE_MODE("ASYNC"),
        .SIM_DEVICE("ULTRASCALE_PLUS")
    ) IDELAYE3_inst (
        .IDATAIN     (hs_data_unbuf), // ★ 修改3：信号连到这里
        .DATAIN      (1'b0),          // ★ 修改4：这里强制接地
        .DATAOUT     (hs_data_delayed),
        .CLK         (clk_div),       // 加载 Tap 值的状态机时钟
        .CE          (1'b0),
        .INC         (1'b0),
        .LOAD        (delay_load),
        .CNTVALUEIN  (delay_tap_in),
        .CNTVALUEOUT (delay_tap_out),
        .CASC_IN     (1'b0),
        .CASC_RETURN (1'b0),
        .CASC_OUT    (),
        .EN_VTC      (1'b0),          // ★ 修改5：COUNT 模式下必须拉低
        .RST         (~rst_n)
    );

// reg w_EN_VTC;
// reg [7:0]  init_wait_cnt;
// always @(posedge clk or negedge rst_n) begin
//     if(~rst_n)begin
//         w_EN_VTC<=0;
//         init_wait_cnt<=8'd0;
//     end
//     else begin
//          if (init_wait_cnt < 8'hFF) begin
//             init_wait_cnt <= init_wait_cnt + 1;
//             w_EN_VTC    <= 1'b1; // 复位结束后保持高电平一段时间，让底层完成初始化
//         end 
//         else begin
//             w_EN_VTC    <= 1'b0; // 初始化完毕，永久拉低，将控制权交给动态扫描状态机
//         end
//     end
// end
//     IDELAYE3 #(
//         .CASCADE("NONE"),
//         .DELAY_FORMAT("TIME"),
//         .DELAY_SRC("IDATAIN"),
//         .DELAY_TYPE("VAR_LOAD"), // ★ 允许运行时动态更改延迟
//         .DELAY_VALUE(0),
//         .IS_CLK_INVERTED(1'b0),
//         .IS_RST_INVERTED(1'b0),        
//         .REFCLK_FREQUENCY(250.0), 
//         .UPDATE_MODE("ASYNC"),
//         .SIM_DEVICE("ULTRASCALE_PLUS")
//     ) IDELAYE3_inst (
//         .IDATAIN     (hs_data_unbuf),
//         .DATAIN      (1'b0),
//         .DATAOUT     (hs_data_delayed),
//         .CLK         (clk_div),
//         .CE          (1'b0),
//         .INC         (1'b0),
//         .LOAD        (delay_load),   // ★ 状态机控制加载脉冲
//         .CNTVALUEIN  (delay_tap_in), // ★ 状态机给定的 0~511 的 Tap 值
//         .CNTVALUEOUT (delay_tap_out),
//         .CASC_IN     (1'b0),
//         .CASC_RETURN (1'b0),
//         .CASC_OUT    (),
//         .EN_VTC      (w_EN_VTC),         // 动态调参时需关闭 VTC
//         .RST         (~rst_n)
//     );

    //==================================================
    // 3. ISERDESE3
    //==================================================
    ISERDESE3 #(
        .DATA_WIDTH(8),
        .FIFO_ENABLE("FALSE"),
        .FIFO_SYNC_MODE("FALSE"),
        .SIM_DEVICE("ULTRASCALE_PLUS")
    ) ISERDESE3_inst (
        .D           (hs_data_delayed),
        .CLK         (clk_hs),
        .CLK_B       (~clk_hs), 
        .CLKDIV      (clk_div),
        .Q           (iserdes_q),     
        .FIFO_RD_CLK (1'b0),
        .FIFO_RD_EN  (1'b0),
        .FIFO_EMPTY  (),
        .RST         (~rst_n | lp_is_stop | force_rst_iserdes)
    );

    //==================================================
    // 4. LP 信号同步与停止位检测 (🌟 终极修复：增加防抖滤波器)
    //==================================================
    reg [1:0] lp_dp_sys, lp_dn_sys;
    reg [3:0] lp_filter_cnt;        // 4位计数器
    reg       lp_is_stop_filtered,lp_is_stop_filtered_d;  // 滤波后的真实 LP-11 状态

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            lp_dp_sys           <= 2'b00;
            lp_dn_sys           <= 2'b00;
            lp_filter_cnt       <= 4'd0;
            lp_is_stop_filtered <= 1'b0;
        end else begin
            // 第一级：跨时钟域同步
            lp_dp_sys <= {lp_dp_sys[0], lp_data_p_async};
            lp_dn_sys <= {lp_dn_sys[0], lp_data_n_async};

            // 第二级：毛刺滤波器
            // 只有当 P 和 N 都是 1，才开始累加
            if (lp_dp_sys[1] && lp_dn_sys[1]) begin
                if (lp_filter_cnt < 4'd2) begin
                    lp_filter_cnt <= lp_filter_cnt + 1;
                end else begin
                    // 连续 8 拍都是高电平，确认为真正的 LP-11 (行间隙)
                    lp_is_stop_filtered <= 1'b1; 
                end
            end else begin
                // 一旦进入高速模式，立刻清零并唤醒状态机！
                lp_filter_cnt       <= 4'd0;
                lp_is_stop_filtered <= 1'b0; 
            end
            lp_is_stop_filtered_d<=lp_is_stop_filtered;
        end
    end
    
    // 生成全局复位信号，供给 ISERDES 和 FSM 使用
    // wire lp_is_stop_sys = lp_is_stop_filtered;
    assign lp_is_stop   = lp_is_stop_filtered;
    wire neg_lp_stop = lp_is_stop_filtered_d && ~lp_is_stop_filtered;


    //==================================================
    // 5. Fabric Barrel Shifter (纯逻辑字对齐)
    //==================================================
    reg [7:0] q_prev;
    always @(posedge clk_div) begin
        q_prev <= iserdes_q;
    end
    wire [15:0] raw_stream = {iserdes_q, q_prev};
    
    reg [2:0] slip_cnt,slip_cnt_d; 
    

    

    //==================================================
    // 6. 极速状态机与 valid 抓取 (🌟 修复：异步复位打断死锁)
    //==================================================
    reg data_is_valid_internal;
    reg [1:0] sync_state;

    // 当进入 LP-11 时，强制拉低复位信号，将 sync_state 拽回 0
    wire fsm_rst_n = rst_n & (~lp_is_stop);

    // 核心控制状态机 (受包间隙异步复位)
    always @(posedge clk_div or negedge fsm_rst_n) begin
        if (!fsm_rst_n) begin
            sync_state             <= 2'd1;
            data_is_valid_internal <= 1'b0;
        end else begin
            case (sync_state)
                2'd0: sync_state <= 2'd1;
                2'd1: begin
                    if      (raw_stream[0 +: 8] == 8'hB8) sync_state <= 2'd2;
                    else if (raw_stream[1 +: 8] == 8'hB8) sync_state <= 2'd2;
                    else if (raw_stream[2 +: 8] == 8'hB8) sync_state <= 2'd2;
                    else if (raw_stream[3 +: 8] == 8'hB8) sync_state <= 2'd2;
                    else if (raw_stream[4 +: 8] == 8'hB8) sync_state <= 2'd2;
                    else if (raw_stream[5 +: 8] == 8'hB8) sync_state <= 2'd2;
                    else if (raw_stream[6 +: 8] == 8'hB8) sync_state <= 2'd2;
                    else if (raw_stream[7 +: 8] == 8'hB8) sync_state <= 2'd2;
                end
                2'd2: begin
                    data_is_valid_internal <= 1'b1;
                end
            endcase
        end
    end

    // 独立维护对齐偏移量 (只受全局复位，包间隙不清除，以供评估算法读取！)
    always @(posedge clk_div or negedge rst_n) begin
        if (!rst_n) begin
            slip_cnt <= 3'd0;
        end else if (sync_state == 2'd1) begin
            if      (raw_stream[0 +: 8] == 8'hB8) slip_cnt <= 3'd0;
            else if (raw_stream[1 +: 8] == 8'hB8) slip_cnt <= 3'd1;
            else if (raw_stream[2 +: 8] == 8'hB8) slip_cnt <= 3'd2;
            else if (raw_stream[3 +: 8] == 8'hB8) slip_cnt <= 3'd3;
            else if (raw_stream[4 +: 8] == 8'hB8) slip_cnt <= 3'd4;
            else if (raw_stream[5 +: 8] == 8'hB8) slip_cnt <= 3'd5;
            else if (raw_stream[6 +: 8] == 8'hB8) slip_cnt <= 3'd6;
            else if (raw_stream[7 +: 8] == 8'hB8) slip_cnt <= 3'd7;
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
    localparam SYNC_CNT   = 4'd3;

    reg [3:0] tune_state;
    reg [8:0] test_tap;
    reg [8:0] left_edge, right_edge;
    reg       in_window;
    reg       got_valid_in_pkt;
    reg [3:0] cnt_1;
    
    
    // 超时计数器：防止摄像头没发数据导致死等
    reg [15:0] timeout_cnt;
    reg [7:0] aligned_data;

    reg [3:0] state_num;
    
    always @(posedge clk_div or negedge rst_n) begin
        if (!rst_n) begin
            state_num<=4'd0;
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
            slip_cnt_d <= 3'd0;
            cnt_1<=4'd0;
        end
        // else if(!state_rst)begin
        //     tune_state   <= TUNE_IDLE;
        //     tuning_done  <= 1'b0;
        //     delay_load   <= 1'b0;
        //     delay_tap_in <= 9'd0;
        //     test_tap     <= 9'd0;
        //     in_window    <= 1'b0;
        //     left_edge    <= 9'd0;
        //     right_edge   <= 9'd0;
        //     rx_valid     <= 1'b0;
        //     rx_byte_data <= 8'h00;
        //     slip_cnt_d <= 3'd0;
        // end
        else begin
            // 只有当调谐完成，才允许把真实的数据和 Valid 传递给外部
            aligned_data <= raw_stream[slip_cnt +: 8];
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
                    if(rst_n)begin
                        tune_state  <= TUNE_SET_TAP;
                        test_tap    <= 9'd0;
                        in_window   <= 1'b0;
                        tuning_done <= 1'b0;
                    end
                    
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
                    // 使用同步后的信号判断：退出 LP-11，开始接收高速数据
                    if (!lp_is_stop) begin
                        tune_state <= TUNE_CHECK_RES;
                    end else begin
                        timeout_cnt <= timeout_cnt + 1;
                        if (timeout_cnt == 16'hFFFF) begin
                            tune_state <= TUNE_IDLE; // 死锁超时复位
                        end
                    end
                end

                TUNE_CHECK_RES: begin
                    // 记录本包是否成功抓到了 0xB8
                    if (data_is_valid_internal) begin
                        got_valid_in_pkt <= 1'b1;
                        tune_state <= TUNE_EVALUATE;
                    end
                    else if(lp_is_stop)begin
                        tune_state <= TUNE_IDLE;
                    end
                    
                end

                TUNE_EVALUATE: begin
                    if(got_valid_in_pkt && !in_window)begin
                        state_num<=4'd1;
                        if(cnt_1 == SYNC_CNT)begin
                            left_edge  <= test_tap;   // 记录左边界
                            test_tap   <= test_tap + 1;
                            in_window  <= 1'b1;
                            slip_cnt_d <= slip_cnt;
                            tune_state <= TUNE_SET_TAP;
                            cnt_1<=4'd0;
                        end
                        else begin
                            cnt_1<=cnt_1+1;
                            tune_state <= TUNE_SET_TAP;
                            test_tap   <= test_tap + 1;
                        end
                    end
                    else if(got_valid_in_pkt && in_window && slip_cnt_d!=slip_cnt )begin
                        state_num<=4'd2;
                        right_edge <= test_tap - 1;
                        test_tap   <= test_tap + 1;
                        tune_state <= TUNE_CALC_MID;
                    end
                    else if(!got_valid_in_pkt && in_window && neg_lp_stop)begin//&& neg_lp_stop
                        state_num<=4'd3;
                        right_edge <= test_tap - 1;
                        test_tap   <= test_tap + 1;
                        tune_state <= TUNE_CALC_MID;
                    end
                    else if(got_valid_in_pkt && in_window && neg_lp_stop)begin
                        state_num<=4'd4;
                        right_edge <= test_tap - 1;
                        test_tap   <= test_tap + 1;
                        tune_state <= TUNE_SET_TAP;
                    end
                    else if (test_tap == 9'd511) begin
                        state_num<=4'd5;
                        // right_edge <= 9'd511;     // 扫到 511 都全是成功的，被迫结束
                        tune_state <= TUNE_CALC_MID;
                    end 
                    else begin
                        test_tap   <= test_tap;
                        tune_state <= tune_state;
                    end

                end

                

                // 修改这两个状态
                TUNE_CALC_MID: begin
                    delay_tap_in      <= left_edge + ((right_edge - left_edge) >> 1);
                    delay_load        <= 1'b1; 
                    force_rst_iserdes <= 1'b1; // 🌟 瞬间改变巨大Tap值时，强制拉高复位
                    tune_state        <= TUNE_DONE_ST;
                end

                TUNE_DONE_ST: begin
                    delay_load        <= 1'b0;
                    force_rst_iserdes <= 1'b0; // 🌟 释放复位，焕然一新迎接新数据
                    tuning_done       <= 1'b1; 
                end
            endcase
        end
    end

endmodule