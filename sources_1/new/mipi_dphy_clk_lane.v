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
        .IOSTANDARD("MIPI_DPHY_DCI")
    ) IBUFDS_DPHY_CLK_inst (
        .I       (clk_p),
        .IB      (clk_n),
        .O       (hs_clk_unbuf), 
        .ODIV2   (),             
        .O_LP_P  (lp_clk_p),     
        .O_LP_N  (lp_clk_n)      
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