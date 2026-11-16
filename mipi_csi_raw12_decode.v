`timescale 1ns / 1ps

module mipi_csi_raw12_decode(
    input  wire         clk,
    input  wire         rst_n,

    input  wire         payload_vaild,  // packet data有效信号
    input  wire [31:0]  payload_data,   // 去掉ph和pf后的packet data
    input  wire [5:0]   dt,             // packet data对应的data id
    input  wire [3:0]   vc,             // packet data对应的virtual channel

    output wire [47:0]  mipi_data,      // 按raw12协议解码或8bit补0后4pixel数据
    output wire [9:0]   mipi_user,      // 对应的{dt, vc}拼接数据
    output wire         mipi_vaild,     // 有效信号
    output wire         mipi_last       // 每一包packet data解码后最后一个byte数据拉高
);

    //=========================================================
    // 1. 状态机参数与内部寄存器定义
    //=========================================================
    localparam GB_0_IN_4 = 2'd0; 
    localparam GB_4_IN_4 = 2'd1; 
    localparam GB_2_IN_4 = 2'd2; 

    reg [1:0]  gb_state;
    reg [31:0] byte_buf;         

    // 第一级流水线：组合逻辑结果 -> 寄存器
    reg        gb_vaild_comb;
    reg [47:0] gb_data_comb;
    reg        gb_val_reg;
    reg [47:0] gb_data_reg;
    reg [9:0]  gb_user_reg;

    // 第二级流水线：输出寄存器
    reg        mipi_vaild_out;
    reg [47:0] mipi_data_out;
    reg [9:0]  mipi_user_out;
    reg        mipi_last_out;

    //=========================================================
    // 2. 齿轮箱状态机运转控制 (仅针对 RAW12 0x2C)
    //=========================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            gb_state <= GB_0_IN_4;
            byte_buf <= 32'd0;
        end else begin
            if (payload_vaild && (dt == 6'h2C)) begin
                case (gb_state)
                    GB_0_IN_4: begin
                        byte_buf <= payload_data;
                        gb_state <= GB_4_IN_4;
                    end
                    GB_4_IN_4: begin
                        byte_buf[15:0] <= payload_data[31:16];
                        gb_state       <= GB_2_IN_4;
                    end
                    GB_2_IN_4: begin
                        gb_state <= GB_0_IN_4;
                    end
                    default: gb_state <= GB_0_IN_4;
                endcase
            end else if (!payload_vaild) begin
                gb_state <= GB_0_IN_4; // 包间复位
            end
        end
    end

    //=========================================================
    // 3. 组合逻辑：RAW12 解包 & 兼容其它格式 (低位补0)
    //=========================================================
    always @(*) begin
        gb_vaild_comb = 1'b0;
        gb_data_comb  = 48'd0;

        if (payload_vaild) begin
            if (dt == 6'h2C) begin
                // --- RAW12 处理分支 ---
                if (gb_state == GB_4_IN_4) begin
                    gb_vaild_comb = 1'b1;
                    gb_data_comb[11:0]  = {byte_buf[7:0],     byte_buf[19:16]};
                    gb_data_comb[23:12] = {byte_buf[15:8],    byte_buf[23:20]};
                    gb_data_comb[35:24] = {byte_buf[31:24],   payload_data[11:8]};
                    gb_data_comb[47:36] = {payload_data[7:0], payload_data[15:12]};
                end
                else if (gb_state == GB_2_IN_4) begin
                    gb_vaild_comb = 1'b1;
                    gb_data_comb[11:0]  = {byte_buf[7:0],       payload_data[3:0]};
                    gb_data_comb[23:12] = {byte_buf[15:8],      payload_data[7:4]};
                    gb_data_comb[35:24] = {payload_data[15:8],  payload_data[27:24]};
                    gb_data_comb[47:36] = {payload_data[23:16], payload_data[31:28]};
                end
            end 
            else begin
                // --- 非 RAW12 (例如 DT=0x3C) 处理分支 ---
                // 每周期直接输出，不经过齿轮箱缓冲，将每个Byte在低位补 4'b0000
                gb_vaild_comb = 1'b1;
                gb_data_comb[11:0]  = {payload_data[7:0],   4'b0000};
                gb_data_comb[23:12] = {payload_data[15:8],  4'b0000};
                gb_data_comb[35:24] = {payload_data[23:16], 4'b0000};
                gb_data_comb[47:36] = {payload_data[31:24], 4'b0000};
            end
        end
    end

    //=========================================================
    // 4. 两级流水线与 last / user 信号对齐输出
    //=========================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            gb_val_reg     <= 1'b0;
            gb_data_reg    <= 48'd0;
            gb_user_reg    <= 10'd0;
            
            mipi_vaild_out <= 1'b0;
            mipi_data_out  <= 48'd0;
            mipi_user_out  <= 10'd0;
            mipi_last_out  <= 1'b0;
        end else begin
            // Stage 1
            gb_val_reg  <= gb_vaild_comb;
            gb_data_reg <= gb_data_comb;
            gb_user_reg <= {dt, vc}; 

            // Stage 2
            mipi_vaild_out <= gb_val_reg;
            mipi_data_out  <= gb_data_reg;
            mipi_user_out  <= gb_user_reg;
            
            // last_out 生成逻辑对所有数据类型均生效
            mipi_last_out  <= gb_val_reg & (~gb_vaild_comb);
        end
    end

    // 输出赋值
    assign mipi_data  = mipi_data_out;
    assign mipi_user  = mipi_user_out;
    assign mipi_vaild = mipi_vaild_out;
    assign mipi_last  = mipi_last_out;

endmodule