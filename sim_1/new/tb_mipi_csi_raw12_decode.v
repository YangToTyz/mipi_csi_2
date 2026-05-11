`timescale 1ns / 1ps

module tb_mipi_csi_raw12_decode();

    reg         clk;
    reg         rst_n;
    reg         payload_vaild;
    reg  [31:0] payload_data;
    reg  [5:0]  dt;
    reg  [3:0]  vc;

    wire [47:0] mipi_data;
    wire [9:0]  mipi_user;
    wire        mipi_vaild;
    wire        mipi_last;

    // 例化
    mipi_csi_raw12_decode uut (
        .clk(clk),
        .rst_n(rst_n),
        .payload_vaild(payload_vaild),
        .payload_data(payload_data),
        .dt(dt),
        .vc(vc),
        .mipi_data(mipi_data),
        .mipi_user(mipi_user),
        .mipi_vaild(mipi_vaild),
        .mipi_last(mipi_last)
    );

    // 时钟生成 187.5MHz
    initial begin
        clk = 0;
        forever #2.666 clk = ~clk;
    end

    // 激励发送任务
    task send_4bytes;
        input [7:0] b3, b2, b1, b0;
        begin
            payload_vaild <= 1'b1;
            payload_data  <= {b3, b2, b1, b0};
            @(posedge clk);
        end
    endtask

    initial begin
        // 1. 初始化
        rst_n         = 0;
        payload_vaild = 0;
        payload_data  = 0;
        dt            = 6'h00; 
        vc            = 4'd0;

        #50;
        rst_n = 1;
        #20;
        @(posedge clk);

        // ===================================================
        // Test Case 1: 发送 dt = 0x2C (RAW12) 
        // ===================================================
        $display("\n=== STARTING PACKET 1 (RAW12, DT=0x2C) ===");
        dt = 6'h2C; // RAW12
        vc = 4'd1;  // VC 设为1，用于观察 mipi_user

        send_4bytes(8'h04, 8'h03, 8'h02, 8'h01); // Cycle 1
        send_4bytes(8'h08, 8'h07, 8'h06, 8'h05); // Cycle 2
        send_4bytes(8'h0C, 8'h0B, 8'h0A, 8'h09); // Cycle 3

        payload_vaild <= 1'b0;
        payload_data  <= 32'd0;
        
        // 等待包间空闲
        #50; 

        // ===================================================
        // Test Case 2: 发送 dt = 0x3C (非 RAW12 直通测试)
        // ===================================================
        $display("\n=== STARTING PACKET 2 (OTHER, DT=0x3C) ===");
        dt = 6'h3C; // 其他格式
        vc = 4'd2;  // VC 设为2

        // 输入 0x11, 0x22, 0x33, 0x44 -> 期望输出 0x110, 0x220, 0x330, 0x440
        send_4bytes(8'h44, 8'h33, 8'h22, 8'h11); 
        // 输入 0x55, 0x66, 0x77, 0x88 -> 期望输出 0x550, 0x660, 0x770, 0x880
        send_4bytes(8'h88, 8'h77, 8'h66, 8'h55); 

        payload_vaild <= 1'b0;
        payload_data  <= 32'd0;

        #50;
        $display("\n=== SIMULATION FINISHED ===");
        $finish;
    end

    // 监控结果自动打印（加入了 DT 输出）
    always @(posedge clk) begin
        if (mipi_vaild) begin
            $display("Time: %0t | DT: %h | VC: %h | Last: %b | P4:0x%03X, P3:0x%03X, P2:0x%03X, P1:0x%03X",
                     $time, mipi_user[9:4], mipi_user[3:0], mipi_last,
                     mipi_data[47:36], mipi_data[35:24], mipi_data[23:12], mipi_data[11:0]);
        end
    end

endmodule