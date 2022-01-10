`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2021/12/13 14:24:50
// Design Name: 
// Module Name: REG_module
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


module read(
    input REG_valid,
    input [188:0] ID_REG_bus,
    input          IF_over,     //对于分支指令，需要该信号
    input [31:0] rs_value,
    input [31:0] rt_value,
    
    input      [  4:0] EXE_wdest,   // EXE级要写回寄存器堆的目标地址号
    input      [  4:0] MEM_wdest,   // MEM级要写回寄存器堆的目标地址号
    input      [  4:0] WB_wdest,    // WB级要写回寄存器堆的目标地址号
    
    input [31:0] EXE_wvalue,
    input [31:0] MEM_wvalue,
    input [31:0] WB_wvalue,
    
    input EXE_wvalid,
    input MEM_wvalid,
    input WB_wvalid,
    
    output REG_over,
    output [171:0] REG_EXE_bus,
    output [4:0] rs,
    output [4:0] rt,
    output [32:0] br_bus,
    output predict_fail,
    //展示PC
    output     [ 31:0] REG_pc
    );
    
//-----{ID->REG总线}begin
    wire read_rs;
    wire read_rt;
    wire inst_no_rs;
    wire inst_no_rt;
    wire [7:0] br_control;
    wire [31:0] br_target;
    wire multiply;
    wire mthi;
    wire mtlo;
    wire [11:0] alu_control;
    wire [31:0] alu_operand1;
    wire [31:0] alu_operand2;
    wire [3:0] mem_control;
    wire mfhi;
    wire mflo;
    wire mtc0;
    wire mfc0;
    wire [7 :0] cp0r_addr;
    wire syscall;
    wire eret;
    wire rf_wen;
    wire [4:0] rf_wdest;
    wire [31:0]pc;
    assign {read_rs,read_rt,br_control,br_target, 
            rs,rt,inst_no_rs,inst_no_rt,
            multiply,mthi,mtlo,            
            alu_control,alu_operand1,alu_operand2,
            mem_control,    
            mfhi,mflo,                            
            mtc0,mfc0,cp0r_addr,syscall,eret, 
            rf_wen, rf_wdest, 
            pc}=ID_REG_bus;
    
    assign REG_pc=pc;
//-----{ID->REG总线}end

//-----{数据相关}begin
    //store旁路单独处理，可以在exe再读
    wire [4:0] store_rf_addr;
    wire store_read_rf;
    
    assign store_read_rf = ~inst_no_rt & (rt!=5'd0) & mem_control[2]; //store inst
    assign store_rf_addr = rt &{5{store_read_rf}};

    //由于是流水的，存在数据相关
    wire rs_wait;
    wire rt_wait;
    assign rs_wait = ~inst_no_rs & (rs!=5'd0)
                   & ( (rs==EXE_wdest && ~EXE_wvalid) | (rs==MEM_wdest && ~MEM_wvalid) | (rs==WB_wdest && ~WB_wvalid));
    assign rt_wait = ~inst_no_rt & (rt!=5'd0)
                   & ( (rt==EXE_wdest && ~EXE_wvalid) | (rt==MEM_wdest && ~MEM_wvalid) | (rt==WB_wdest && ~MEM_wvalid))
                   & ~store_read_rf;
                   
    wire inst_jbr;
    assign inst_jbr= |br_control;
        //对于分支跳转指令，只有在IF执行完成后，才可以算ID完成；
    //否则，ID级先完成了，而IF还在取指令，则next_pc不能锁存到PC里去，
    //那么等IF完成，next_pc能锁存到PC里去时，jbr_bus上的数据已变成无效，
    //导致分支跳转失败
    //(~inst_jbr | IF_over)即是(~inst_jbr | (inst_jbr & IF_over))
//    assign REG_over = REG_valid & ~rs_wait & ~rt_wait & (~inst_jbr | IF_over);
    assign REG_over = REG_valid & ~rs_wait & ~rt_wait & (~inst_jbr | IF_over);

    wire [31:0] forward_rs_value;
    wire [31:0] forward_rt_value;
    
    assign forward_rs_value = (rs == EXE_wdest) ? EXE_wvalue:
                              (rs==MEM_wdest) ? MEM_wvalue:
                              (rs==WB_wdest) ? WB_wvalue:
                              rs_value;
    assign forward_rt_value = (rt == EXE_wdest) ? EXE_wvalue:
                              (rt ==MEM_wdest) ? MEM_wvalue:
                              (rt ==WB_wdest) ? WB_wvalue:
                              rt_value;
    
    
    wire [31:0] alu_op1;
    wire [31:0] alu_op2;
    assign alu_op1 = read_rs ? forward_rs_value : alu_operand1;
    assign alu_op2 = read_rt ? forward_rt_value : alu_operand2;
    
    
//-----{数据相关}end

//-----{分支}begin
    wire inst_jr;
    wire inst_BEQ;
    wire inst_BNE;
    wire inst_BGEZ;
    wire inst_BGTZ;
    wire inst_BLEZ;
    wire inst_BLTZ;
    assign {inst_jr,
            inst_BEQ,
            inst_BNE,
            inst_BGEZ,
            inst_BGTZ,
            inst_BLEZ,
            inst_BLTZ}=br_control;
            
    wire br_taken; 
    wire rs_equql_rt;
    wire rs_ez;
    wire rs_ltz;
    assign rs_equql_rt = (forward_rs_value == forward_rt_value);  // GPR[rs]==GPR[rt]
    assign rs_ez       = ~(|forward_rs_value);            // rs寄存器值为0
    assign rs_ltz      = forward_rs_value[31];            // rs寄存器值小于0
    assign br_taken = inst_BEQ  & rs_equql_rt       // 相等跳转
                    | inst_BNE  & ~rs_equql_rt      // 不等跳转
                    | inst_BGEZ & ~rs_ltz           // 大于等于0跳转
                    | inst_BGTZ & ~rs_ltz & ~rs_ez  // 大于0跳转
                    | inst_BLEZ & (rs_ltz | rs_ez)  // 小于等于0跳转
                    | inst_BLTZ & rs_ltz            // 小于0跳转
                    | inst_jr;

    wire [31:0] r_br_target;
    assign r_br_target=inst_jr ? forward_rs_value : br_target;
    assign br_bus={br_taken,r_br_target};
    assign predict_fail=br_taken;
//-----{分支}end

//-----{REG->EXE总线}begin
    wire [31:0]store_data;
    assign store_data=forward_rt_value;
    assign REG_EXE_bus = {multiply,mthi,mtlo,                   //EXE需用的信息,新增
                          alu_control,alu_op1,alu_op2,          //EXE需用的信息
                          mem_control,store_data,store_rf_addr, //MEM需用的信号
                          mfhi,mflo,                            //WB需用的信号,新增
                          mtc0,mfc0,cp0r_addr,syscall,eret,     //WB需用的信号,新增
                          rf_wen, rf_wdest,                     //WB需用的信号
                          pc};                                  //PC值

//-----{REG->EXE总线}end

endmodule
