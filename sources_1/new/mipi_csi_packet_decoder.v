`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/05/08 21:57:22
// Design Name: 
// Module Name: top_mipi
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


module mipi_csi_packet_decoder(
    input   wire    clk,
    input   wire    rst_n,

    input   wire    [3:0]   dl_rxsynchs,
    input   wire    [31:0]  dl_rxdatahs,
    input   wire    dl_rxvalidhs,

    output  reg     o_payload_vaild,
    output  reg     [31:0]  o_payload_data,
    output  reg     [5:0]   dt,
    output  reg     [3:0]   vc 
    );


localparam [7:0]SYNC_BYTE = 8'hB8;
localparam [3:0]LANES = 3'h4;
localparam [7:0]MIPI_CSI_PACKET_12bRAW = 8'h2C;

localparam ST_IDLE    = 3'd0;
localparam ST_PAYLOAD = 3'd1;
localparam ST_FOOTER  = 3'd2;

reg [2:0]state;
// reg [1:0]vc;
// reg [5:0]dt;
reg [15:0]word_cnt;
reg [1:0]vcx;
reg [5:0]ecc;
reg [15:0]crc;
always@(posedge clk or negedge rst_n)begin
    if(~rst_n)begin
        state <= ST_IDLE;
        o_payload_vaild <= 1'b0;
        o_payload_data <= 32'd0;
    end
    else begin
        case(state)
            ST_IDLE:begin
                o_payload_vaild<=1'b0;
                if(dl_rxvalidhs && dl_rxdatahs[5:0]==6'h2C)begin
                    state <= ST_PAYLOAD;
                    word_cnt <= dl_rxdatahs[23:8];
                    dt <= dl_rxdatahs[5:0];
                    vc[1:0] <= dl_rxdatahs[7:6];
                    ecc <= dl_rxdatahs[29:24];
                    vc[3:2] <= dl_rxdatahs[31:30]
                end
                else begin
                    state <= state;
                end
            end
            ST_PAYLOAD:begin
                if(dl_rxvalidhs)begin
                    o_payload_vaild<=1'b1;
                    o_payload_data<=dl_rxdatahs;
                    word_cnt<=word_cnt - 3'd4;
                    if(word_cnt == 1'd0)begin
                        state <= ST_FOOTER;
                    end
                    else begin
                        state <= state;
                    end
                end
                else begin
                    o_payload_vaild<=1'b0;
                end
            end
            ST_FOOTER:begin
                o_payload_vaild<=1'b0;
                if(o_payload_vaild)begin
                    crc <= dl_rxdatahs[15:0];
                end
                else begin
                    state <= ST_IDLE;
                end
            end
        endcase
    end
end
    
endmodule
