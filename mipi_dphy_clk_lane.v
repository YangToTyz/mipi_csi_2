`timescale 1ns / 1ps

module mipi_dphy_clock_lane (
    input  wire clk_p,
    input  wire clk_n,
    output wire clk_hs_750m,
    output wire clk_div_187p5m,
    output wire lp_clk_p,
    output wire lp_clk_n
);

    wire hs_clk_unbuf;

    
    IBUFDS_DPHY #(
      .DIFF_TERM("TRUE"),             // Differential termination
      .IOSTANDARD("MIPI_DPHY_DCI"),         // I/O standard
      .SIM_DEVICE("ULTRASCALE_PLUS")  // Set the device version (ULTRASCALE_PLUS, ULTRASCALE_PLUS_ES1,
                                      // ULTRASCALE_PLUS_ES2)
   )
   IBUFDS_DPHY_inst (
      .HSRX_O(hs_clk_unbuf),             // 1-bit output: HS RX output
      .LPRX_O_N(lp_clk_n),         // 1-bit output: LP RX output (Slave)
      .LPRX_O_P(lp_clk_p),         // 1-bit output: LP RX output (Master)
      .HSRX_DISABLE(1'b0), // 1-bit input: Disable control for HS mode
      .I(clk_p),                       // 1-bit input: Data input0 PAD
      .IB(clk_n),                     // 1-bit input: Data input1 PAD
      .LPRX_DISABLE(1'b0)  // 1-bit input: Disable control for LP mode
   );

    BUFGCE BUFGCE_HS_inst (
        .I  (hs_clk_unbuf),
        .CE (1'b1),
        .O  (clk_hs_750m)
    );

    BUFGCE_DIV #(
        .BUFGCE_DIVIDE(4) 
    ) BUFGCE_DIV_inst (
        .I   (hs_clk_unbuf),
        .CE  (1'b1),
        .CLR (1'b0),
        .O   (clk_div_187p5m)
    );

endmodule