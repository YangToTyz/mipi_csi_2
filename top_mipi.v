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
    input   wire    rst_n,

    input   wire    clk_rxp,
    input   wire    clk_rxn,
    input   wire    [3:0]   data_rxp,
    input   wire    [3:0]   data_rxn,

    output  wire rxbyteclkhs,

    input wire f_sync,

    output  wire            o_payload_vaild,
    output  wire            o_payload_last,
    output  wire            o_payload_strat,
    output  wire    [47:0]  o_payload_data,
    output  wire    [9:0]   o_payload_dest
    );

wire    [47:0]  w_payload_data;
wire            w_payload_vaild;
wire            w_payload_last;
wire            w_payload_strat;
wire    [9:0]   w_payload_dest;

assign o_payload_data  = w_payload_data;
assign o_payload_vaild = w_payload_vaild;
assign o_payload_last = w_payload_last;
assign o_payload_strat = w_payload_strat;
// ila_mipi_top u_ila_mipi_top(
//     .clk(rxbyteclkhs),
//     .probe0(o_payload_vaild),
//     .probe1(o_payload_data),
//     .probe2(o_payload_dest),
//     .probe3(o_payload_last)
// );

assign o_payload_dest = {dt,vc};
assign w_payload_dest = {dt,vc};


wire            cl_stopstate;
wire            cl_enable;
wire    [3:0]   dl_stopstate;
wire    [3:0]   dl_enable;
wire    [3:0]   dl_rxsynchs;
wire    [31:0]  dl_rxdatahs;
wire            dl_rxvalidhs;
mipi_csi_module u_mipi_csi_module(
    .core_clk(sys_clk),
    .core_rst_n(rst_n),
    .clk_rxp(clk_rxp),
    .clk_rxn(clk_rxn),
    .data_rxp(data_rxp),
    .data_rxn(data_rxn),

    .rxbyteclkhs(rxbyteclkhs),
    
    .cl_stopstate(cl_stopstate),
    .cl_enable(1'b1),
    .dl_stopstate(dl_stopstate),
    .dl_enable(4'b1),
    

    .dl_rxsynchs(dl_rxsynchs),
    .dl_rxdatahs(dl_rxdatahs),
    .dl_rxvalidhs(dl_rxvalidhs) ,

    .f_sync(f_sync),
    .o_payload_vaild(w_payload_vaild),
    .o_payload_data (w_payload_data),
    .o_payload_last(w_payload_last),
    .o_payload_strat(w_payload_strat),
    .o_payload_dest(w_payload_dest)
);

wire            payload_vaild;
wire    [31:0]  payload_data;
wire    [5:0]   dt;
wire    [3:0]   vc;
mipi_csi_packet_decoder u_mipi_csi_packet_decoder(
    .clk(sys_clk),
    .rst_n(rst_n),

    .rxbyteclkhs(rxbyteclkhs),

    .dl_rxsynchs(dl_rxsynchs),
    .dl_rxdatahs(dl_rxdatahs),
    .dl_rxvalidhs(dl_rxvalidhs),

    .o_payload_vaild(w_payload_vaild),
    .o_payload_data (w_payload_data),
    .o_payload_last(w_payload_last),
    .o_payload_strat(w_payload_strat),
    .dt(dt),
    .vc(vc) 
);


    
endmodule
