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


module top_mipi(
    input   wire    sys_clk,

    input   wire    clk_rxp,
    input   wire    clk_rxn,
    input   wire    [3:0]   data_rxp,
    input   wire    [3:0]   data_rxn,
    );

wire clk_250m;
wire reset;
wire locked;
wire rst_n;
assign rst_n = locked;
clk_wiz_0 u_clk_wiz_0
   (
    // Clock out ports
    .clk_out1(sys_clk),     // output clk_out1
    // Status and control signals
    .reset(reset), // input reset
    .locked(locked),       // output locked
   // Clock in ports
    .clk_in1(clk_250m)      // input clk_in1
);

wire            cl_stopstate,
wire            cl_enable,
wire    [3:0]   dl_stopstate,
wire    [3:0]   dl_enable,
wire            rxbyteclkhs,
wire    [3:0]   dl_rxsynchs,
wire    [31:0]  dl_rxdatahs,
wire            dl_rxvalidhs 
mipi_csi_module u_mipi_csi_module(
    .core_clk(clk_250m),
    .core_rst(rst_n),
    .clk_rxp(clk_rxp),
    .clk_rxn(clk_rxn),
    .data_rxp(data_rxp),
    .data_rxn(data_rxn),
    .cl_stopstate(cl_stopstate),
    .cl_enable(1'b1),
    .dl_stopstate(dl_stopstate),
    .dl_enable(4'b1),
    

    .dl_rxsynchs(dl_rxsynchs)
    .dl_rxdatahs(dl_rxdatahs),
    .dl_rxvalidhs(dl_rxvalidhs) 
);

wire            payload_vaild,
wire    [31:0]  payload_data,
wire    [5:0]   dt,
wire    [3:0]   vc,
mipi_csi_packet_decoder mipi_csi_packet_decoder(
    .clk(clk_250m),
    .rst_n(rst_n),

    .dl_rxsynchs(dl_rxsynchs),
    .dl_rxdatahs(dl_rxdatahs),
    .dl_rxvalidhs(dl_rxvalidhs),

    .o_payload_vaild(payload_vaild),
    .o_payload_data(payload_data),
    .dt(dt),
    .vc(vc) 
);


    
endmodule
