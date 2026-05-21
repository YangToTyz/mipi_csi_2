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
    output  wire            dl_rxvalidhs 

    );



wire clk_hs_750m;
    
    // 暴露给后级的字节时钟
    assign rxbyteclkhs = clk_div_187p5m;
    wire clk_div_187p5m;

    //==================================================
    // 0. 核心枢纽：IDELAYCTRL (UltraScale必须实例化)
    //==================================================
    wire idelayctrl_rdy;
    IDELAYCTRL #(
        .SIM_DEVICE("ULTRASCALE")
    ) IDELAYCTRL_inst (
        .RDY    (idelayctrl_rdy),
        .REFCLK (ref_clk_200m),
        .RST    (~rst_n)
    );

    //==================================================
    // 1. 实例化 Clock Lane
    //==================================================
    mipi_dphy_clock_lane u_clock_lane (
        .clk_p          (mipi_clk_p),
        .clk_n          (mipi_clk_n),
        .clk_hs_750m    (clk_hs_750m),
        .clk_div_187p5m (clk_div_187p5m),
        .lp_clk_p       (), // 顶层暂不外接
        .lp_clk_n       ()
    );

    //==================================================
    // 2. 实例化 4 个 Data Lane 
    //==================================================
    genvar i;
    generate
        for (i = 0; i < 4; i = i + 1) begin : gen_data_lanes
            mipi_dphy_data_lane u_data_lane (
                .rst_n         (rst_n & idelayctrl_rdy), // IDELAYCTRL 准备好才释放复位
                .clk_hs        (clk_hs_750m),
                .clk_div       (clk_div_187p5m),
                .data_p        (data_rxp[i]),
                .data_n        (data_rxn[i]),
                
                // 数据与 valid 映射到对应的 Byte 槽位
                .rx_byte_data  (phy_rx_data_hs[i*8 +: 8]), 
                .rx_valid      (phy_rx_valid_hs[i]),
                .lp_is_stop    ()
            );
        end
    endgenerate






// // wire [3:0] dl_stopstate;
// // wire [3:0] dl_enable;
// wire [3:0] dl_ulpsactivenot;
// assign dl_stopstate = {dl3_stopstate,dl2_stopstate,dl1_stopstate,dl0_stopstate};
// assign dl_enable = {dl3_enable,dl2_enable,dl1_enable,dl0_enable};
// assign dl_ulpsactivenot = {dl3_ulpsactivenot,dl2_ulpsactivenot,dl1_ulpsactivenot,dl0_ulpsactivenot};
// assign dl_rxsynchs = {dl3_rxsynchs,dl2_rxsynchs,dl1_rxsynchs,dl0_rxsynchs};

// // wire [31:0] dl_rxdatahs;
// // wire [3:0] dl_rxvalidhs;
// // assign dl_rxdatahs = {dl3_rxdatahs,dl2_rxdatahs,dl1_rxdatahs,dl0_rxdatahs};
// assign dl_rxvalidhs = ~enpty;//{dl3_rxvalidhs,dl2_rxvalidhs,dl1_rxvalidhs,dl0_rxvalidhs};

// mipi_dphy_0 u_mipi_dphy_0 (
//   .core_clk(core_clk),                    // input wire core_clk
//   .core_rst(core_rst),                    // input wire core_rst
//   .rxbyteclkhs(rxbyteclkhs),              // output wire rxbyteclkhs
//   .clkoutphy_out(clkoutphy_out),          // output wire clkoutphy_out
//   .pll_lock_out(pll_lock_out),            // output wire pll_lock_out
//   .system_rst_out(system_rst_out),        // output wire system_rst_out
//   .init_done(init_done),                  // output wire init_done
//   .cl_stopstate(cl_stopstate),            // output wire cl_stopstate
//   .cl_enable(cl_enable),                  // input wire cl_enable
//   .cl_ulpsactivenot(cl_ulpsactivenot),    // output wire cl_ulpsactivenot
//   .dl0_stopstate(dl0_stopstate),          // output wire dl0_stopstate
//   .dl0_enable(dl0_enable),                // input wire dl0_enable
//   .dl0_ulpsactivenot(dl0_ulpsactivenot),  // output wire dl0_ulpsactivenot
//   .dl1_stopstate(dl1_stopstate),          // output wire dl1_stopstate
//   .dl1_enable(dl1_enable),                // input wire dl1_enable
//   .dl1_ulpsactivenot(dl1_ulpsactivenot),  // output wire dl1_ulpsactivenot
//   .dl2_stopstate(dl2_stopstate),          // output wire dl2_stopstate
//   .dl2_enable(dl2_enable),                // input wire dl2_enable
//   .dl2_ulpsactivenot(dl2_ulpsactivenot),  // output wire dl2_ulpsactivenot
//   .dl3_stopstate(dl3_stopstate),          // output wire dl3_stopstate
//   .dl3_enable(dl3_enable),                // input wire dl3_enable
//   .dl3_ulpsactivenot(dl3_ulpsactivenot),  // output wire dl3_ulpsactivenot
//   .dl0_rxdatahs(dl0_rxdatahs),            // output wire [7 : 0] dl0_rxdatahs
//   .dl0_rxvalidhs(dl0_rxvalidhs),          // output wire dl0_rxvalidhs
//   .dl0_rxactivehs(dl0_rxactivehs),        // output wire dl0_rxactivehs
//   .dl0_rxsynchs(dl0_rxsynchs),            // output wire dl0_rxsynchs
//   .dl0_forcerxmode(dl0_forcerxmode),      // input wire dl0_forcerxmode
//   .dl0_rxclkesc(dl0_rxclkesc),            // output wire dl0_rxclkesc
//   .dl0_rxlpdtesc(dl0_rxlpdtesc),          // output wire dl0_rxlpdtesc
//   .dl0_rxulpsesc(dl0_rxulpsesc),          // output wire dl0_rxulpsesc
//   .dl0_rxtriggeresc(dl0_rxtriggeresc),    // output wire [3 : 0] dl0_rxtriggeresc
//   .dl0_rxdataesc(dl0_rxdataesc),          // output wire [7 : 0] dl0_rxdataesc
//   .dl0_rxvalidesc(dl0_rxvalidesc),        // output wire dl0_rxvalidesc
//   .dl0_errsoths(dl0_errsoths),            // output wire dl0_errsoths
//   .dl0_errsotsynchs(dl0_errsotsynchs),    // output wire dl0_errsotsynchs
//   .dl0_erresc(dl0_erresc),                // output wire dl0_erresc
//   .dl0_errsyncesc(dl0_errsyncesc),        // output wire dl0_errsyncesc
//   .dl0_errcontrol(dl0_errcontrol),        // output wire dl0_errcontrol
//   .dl1_rxdatahs(dl1_rxdatahs),            // output wire [7 : 0] dl1_rxdatahs
//   .dl1_rxvalidhs(dl1_rxvalidhs),          // output wire dl1_rxvalidhs
//   .dl1_rxactivehs(dl1_rxactivehs),        // output wire dl1_rxactivehs
//   .dl1_rxsynchs(dl1_rxsynchs),            // output wire dl1_rxsynchs
//   .dl1_forcerxmode(dl1_forcerxmode),      // input wire dl1_forcerxmode
//   .dl1_rxclkesc(dl1_rxclkesc),            // output wire dl1_rxclkesc
//   .dl1_rxlpdtesc(dl1_rxlpdtesc),          // output wire dl1_rxlpdtesc
//   .dl1_rxulpsesc(dl1_rxulpsesc),          // output wire dl1_rxulpsesc
//   .dl1_rxtriggeresc(dl1_rxtriggeresc),    // output wire [3 : 0] dl1_rxtriggeresc
//   .dl1_rxdataesc(dl1_rxdataesc),          // output wire [7 : 0] dl1_rxdataesc
//   .dl1_rxvalidesc(dl1_rxvalidesc),        // output wire dl1_rxvalidesc
//   .dl1_errsoths(dl1_errsoths),            // output wire dl1_errsoths
//   .dl1_errsotsynchs(dl1_errsotsynchs),    // output wire dl1_errsotsynchs
//   .dl1_erresc(dl1_erresc),                // output wire dl1_erresc
//   .dl1_errsyncesc(dl1_errsyncesc),        // output wire dl1_errsyncesc
//   .dl1_errcontrol(dl1_errcontrol),        // output wire dl1_errcontrol
//   .dl2_rxdatahs(dl2_rxdatahs),            // output wire [7 : 0] dl2_rxdatahs
//   .dl2_rxvalidhs(dl2_rxvalidhs),          // output wire dl2_rxvalidhs
//   .dl2_rxactivehs(dl2_rxactivehs),        // output wire dl2_rxactivehs
//   .dl2_rxsynchs(dl2_rxsynchs),            // output wire dl2_rxsynchs
//   .dl2_forcerxmode(dl2_forcerxmode),      // input wire dl2_forcerxmode
//   .dl2_rxclkesc(dl2_rxclkesc),            // output wire dl2_rxclkesc
//   .dl2_rxlpdtesc(dl2_rxlpdtesc),          // output wire dl2_rxlpdtesc
//   .dl2_rxulpsesc(dl2_rxulpsesc),          // output wire dl2_rxulpsesc
//   .dl2_rxtriggeresc(dl2_rxtriggeresc),    // output wire [3 : 0] dl2_rxtriggeresc
//   .dl2_rxdataesc(dl2_rxdataesc),          // output wire [7 : 0] dl2_rxdataesc
//   .dl2_rxvalidesc(dl2_rxvalidesc),        // output wire dl2_rxvalidesc
//   .dl2_errsoths(dl2_errsoths),            // output wire dl2_errsoths
//   .dl2_errsotsynchs(dl2_errsotsynchs),    // output wire dl2_errsotsynchs
//   .dl2_erresc(dl2_erresc),                // output wire dl2_erresc
//   .dl2_errsyncesc(dl2_errsyncesc),        // output wire dl2_errsyncesc
//   .dl2_errcontrol(dl2_errcontrol),        // output wire dl2_errcontrol
//   .dl3_rxdatahs(dl3_rxdatahs),            // output wire [7 : 0] dl3_rxdatahs
//   .dl3_rxvalidhs(dl3_rxvalidhs),          // output wire dl3_rxvalidhs
//   .dl3_rxactivehs(dl3_rxactivehs),        // output wire dl3_rxactivehs
//   .dl3_rxsynchs(dl3_rxsynchs),            // output wire dl3_rxsynchs
//   .dl3_forcerxmode(dl3_forcerxmode),      // input wire dl3_forcerxmode
//   .dl3_rxclkesc(dl3_rxclkesc),            // output wire dl3_rxclkesc
//   .dl3_rxlpdtesc(dl3_rxlpdtesc),          // output wire dl3_rxlpdtesc
//   .dl3_rxulpsesc(dl3_rxulpsesc),          // output wire dl3_rxulpsesc
//   .dl3_rxtriggeresc(dl3_rxtriggeresc),    // output wire [3 : 0] dl3_rxtriggeresc
//   .dl3_rxdataesc(dl3_rxdataesc),          // output wire [7 : 0] dl3_rxdataesc
//   .dl3_rxvalidesc(dl3_rxvalidesc),        // output wire dl3_rxvalidesc
//   .dl3_errsoths(dl3_errsoths),            // output wire dl3_errsoths
//   .dl3_errsotsynchs(dl3_errsotsynchs),    // output wire dl3_errsotsynchs
//   .dl3_erresc(dl3_erresc),                // output wire dl3_erresc
//   .dl3_errsyncesc(dl3_errsyncesc),        // output wire dl3_errsyncesc
//   .dl3_errcontrol(dl3_errcontrol),        // output wire dl3_errcontrol
//   .cl_rxclkactivehs(cl_rxclkactivehs),    // output wire cl_rxclkactivehs
//   .cl_rxulpsclknot(cl_rxulpsclknot),      // output wire cl_rxulpsclknot
//   .clk_rxp(clk_rxp),                      // input wire clk_rxp
//   .clk_rxn(clk_rxn),                      // input wire clk_rxn
//   .data_rxp(data_rxp),                    // input wire [3 : 0] data_rxp
//   .data_rxn(data_rxn)                    // input wire [3 : 0] data_rxn
// );

// wire full,enpty;

// mipiclk2sysclk u_mipiclk2sysclk (
//   .rst(core_rst),        // input wire rst
//   .wr_clk(rxbyteclkhs),  // input wire wr_clk
//   .rd_clk(core_clk),  // input wire rd_clk
//   .din({dl3_rxdatahs,dl2_rxdatahs,dl1_rxdatahs,dl0_rxdatahs}),        // input wire [31 : 0] din
//   .wr_en(dl0_rxvalidhs),    // input wire wr_en
//   .rd_en(~enpty),    // input wire rd_en
//   .dout(dl_rxdatahs),      // output wire [31 : 0] dout
//   .full(full),      // output wire full
//   .empty(empty)    // output wire empty
// );


    
endmodule
