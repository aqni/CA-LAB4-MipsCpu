`timescale 1ns / 1ps

////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer:
//
// Create Date:   11:57:16 04/23/2016
// Design Name:   pipeline_cpu
// Module Name:   F:/new_lab/8_pipeline_cpu/tb.v
// Project Name:  pipeline_cpu
// Target Device:  
// Tool versions:  
// Description: 
//
// Verilog Test Fixture created by ISE for module: pipeline_cpu
//
// Dependencies:
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
////////////////////////////////////////////////////////////////////////////////

module tb;

    // Inputs
    reg clk;
    reg resetn;
    reg [4:0] rf_addr;
    reg [31:0] mem_addr;

    // Outputs
    wire [31:0] rf_data;
    wire [31:0] mem_data;
    wire [31:0] IF_pc;
    wire [31:0] IF_inst;
    wire [31:0] ID_pc;
    wire [31:0] ID_inst;
    wire [31:0] REG_pc;
    wire [31:0] EXE_pc;
    wire [31:0] MEM_pc;
    wire [31:0] WB_pc;
    wire [31:0] cpu_5_valid;
    wire [31:0] cpu_5_over;
    wire [31:0] cpu_allow_in;
    
    //µ÷ÊÔÏß
    wire [31:0] inst;
    wire [31:0] next_pc;
    wire [31:0] inst_addr;
    wire [32:0] br_bus;
    wire [32:0] j_bus;
    wire [4:0] rs;
    wire [4:0] rt;
    wire [31:0] rs_value;
    wire [31:0] rt_value;
    wire [4:0] EXE_wdest;
    wire [4:0] MEM_wdest;
    wire [4:0] WB_wdest;
    wire  EXE_wvalid;
    wire  MEM_wvalid;
    wire  WB_wvalid;
    wire [31:0] EXE_wvalue;
    wire [31:0] MEM_wvalue;
    wire [31:0] WB_wvalue;
   

    // Instantiate the Unit Under Test (UUT)
    pipeline_cpu uut (
        .clk(clk), 
        .resetn(resetn), 
        .rf_addr(rf_addr), 
        .mem_addr(mem_addr), 
        .rf_data(rf_data), 
        .mem_data(mem_data), 
        .IF_pc(IF_pc), 
        .IF_inst(IF_inst), 
        .ID_pc(ID_pc), 
        .REG_pc(REG_pc),
        .EXE_pc(EXE_pc), 
        .MEM_pc(MEM_pc), 
        .WB_pc(WB_pc), 
        .cpu_5_valid(cpu_5_valid),
        .dbg_inst(inst),
        .cpu_5_over(cpu_5_over),
        .cpu_allow_in(cpu_allow_in),
        .dbg_inst_addr(inst_addr),
        .dbg_next_pc(next_pc),
        .dbg_ID_inst(ID_inst),
        .dbg_j_bus(j_bus),
        .dbg_br_bus(br_bus),
        .dbg_rs(rs),
        .dbg_rt(rt),
        .dbg_rs_value(rs_value),
        .dbg_rt_value(rt_value),
        .dbg_EXE_wdest(EXE_wdest),
        .dbg_MEM_wdest(MEM_wdest),
        .dbg_WB_wdest(WB_wdest),
        .dbg_EXE_wvalid(EXE_wvalid),
        .dbg_MEM_wvalid(MEM_wvalid),
        .dbg_WB_wvalid(WB_wvalid),
        .dbg_EXE_wvalue(EXE_wvalue),
        .dbg_MEM_wvalue(MEM_wvalue),
        .dbg_WB_wvalue(WB_wvalue)
    );

    initial begin
        // Initialize Inputs
        clk = 0;
        resetn = 0;
        rf_addr = 2;
        mem_addr = 32'h14;

        // Wait 100 ns for global reset to finish
        #100;
      resetn = 1;
        // Add stimulus here
    end
   always #5 clk=~clk;
endmodule

