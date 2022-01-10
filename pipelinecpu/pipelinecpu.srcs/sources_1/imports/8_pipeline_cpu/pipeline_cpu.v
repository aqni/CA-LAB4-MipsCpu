`timescale 1ns / 1ps
//*************************************************************************
//   > 文件名: pipeline_cpu.v
//   > 描述  :五级流水CPU模块，共实现XX条指令
//   >        指令rom和数据ram均实例化xilinx IP得到，为同步读写
//   > 作者  : LOONGSON
//   > 日期  : 2016-04-14
//*************************************************************************
module pipeline_cpu(  // 多周期cpu
    input clk,        // 时钟
    input resetn,     // 复位信号，低电平有效
    
    //display data
    input  [ 4:0] rf_addr,
    input  [31:0] mem_addr,
    output [31:0] rf_data,
    output [31:0] mem_data,
    output [31:0] IF_pc,
    output [31:0] IF_inst,
    output [31:0] ID_pc,
    output [31:0] REG_pc,
    output [31:0] EXE_pc,
    output [31:0] MEM_pc,
    output [31:0] WB_pc,
    
    //5级流水新增
    output [31:0] cpu_5_valid,
    output [31:0] HI_data,
    output [31:0] LO_data,
    
    //调试线
    output [31:0] dbg_inst,
    output [31:0] dbg_ID_inst,
    output [31:0] cpu_5_over,
    output [31:0] cpu_allow_in,
    output [31:0] dbg_inst_addr,
    output [31:0] dbg_next_pc,
    output [32:0] dbg_j_bus,
    output [32:0] dbg_br_bus,
    output [4:0] dbg_rs,
    output [4:0] dbg_rt,
    output [31:0] dbg_rs_value,
    output [31:0] dbg_rt_value,
    output [4:0] dbg_EXE_wdest,
    output [4:0] dbg_MEM_wdest,
    output [4:0] dbg_WB_wdest,
    output dbg_EXE_wvalid,
    output dbg_MEM_wvalid,
    output dbg_WB_wvalid,
    output [31:0] dbg_EXE_wvalue,
    output [31:0] dbg_MEM_wvalue,
    output [31:0] dbg_WB_wvalue
    );
//------------------------{5级流水控制信号}begin-------------------------//
    //5模块的valid信号
    reg IF_valid;
    reg ID_valid;
    reg REG_valid;
    reg EXE_valid;
    reg MEM_valid;
    reg WB_valid;
    //5模块执行完成信号,来自各模块的输出
    wire IF_over;
    wire ID_over;
    wire REG_over;
    wire EXE_over;
    wire MEM_over;
    wire WB_over;
    //5模块允许下一级指令进入
    wire IF_allow_in;
    wire ID_allow_in;
    wire REG_allow_in;
    wire EXE_allow_in;
    wire MEM_allow_in;
    wire WB_allow_in;
    //6级流水分支预测
    wire predict_fail;
    
    // syscall和eret到达写回级时会发出cancel信号，
    wire cancel;    // 取消已经取出的正在其他流水级执行的指令
    
    //各级允许进入信号:本级无效，或本级执行完成且下级允许进入
    assign IF_allow_in  = (IF_over & ID_allow_in) | cancel;
    assign ID_allow_in  = ~ID_valid  | (ID_over  & REG_allow_in);
    assign REG_allow_in  = ~REG_valid  | (REG_over  & EXE_allow_in);
    assign EXE_allow_in = ~EXE_valid | (EXE_over & MEM_allow_in);
    assign MEM_allow_in = ~MEM_valid | (MEM_over & WB_allow_in );
    assign WB_allow_in  = ~WB_valid  | WB_over;
   
    //IF_valid，在复位后，一直有效
   always @(posedge clk)
    begin
        if (!resetn)
        begin
            IF_valid <= 1'b0;
        end
        else
        begin
            IF_valid <= 1'b1;
        end
    end
    
    //ID_valid
    always @(posedge clk)
    begin
        if (!resetn || cancel)
        begin
            ID_valid <= 1'b0;
        end
        else if (ID_allow_in)
        begin
            ID_valid <= IF_over;
        end
    end
    
    //REG_valid
    always @(posedge clk)
    begin
        if (!resetn || cancel)
        begin
            REG_valid <= 1'b0;
        end
        else if (REG_allow_in)
        begin
            REG_valid <= ID_over;
        end
    end
    
    //EXE_valid
    always @(posedge clk)
    begin
        if (!resetn || cancel)
        begin
            EXE_valid <= 1'b0;
        end
        else if (EXE_allow_in)
        begin
            EXE_valid <= REG_over;
        end
    end
    
    //MEM_valid
    always @(posedge clk)
    begin
        if (!resetn || cancel)
        begin
            MEM_valid <= 1'b0;
        end
        else if (MEM_allow_in)
        begin
            MEM_valid <= EXE_over;
        end
    end
    
    //WB_valid
    always @(posedge clk)
    begin
        if (!resetn || cancel)
        begin
            WB_valid <= 1'b0;
        end
        else if (WB_allow_in)
        begin
            WB_valid <= MEM_over;
        end
    end
    
//调试信号
    assign cpu_allow_in= {8'b0          ,{4{IF_allow_in}},{4{ID_allow_in}},{4{REG_allow_in}},
                          {4{EXE_allow_in}},{4{MEM_allow_in}},{4{WB_allow_in}}};
    //展示5级的valid信号
    assign cpu_5_valid = {8'd0         ,{4{IF_valid }},{4{ID_valid}},{4{REG_valid}},
                          {4{EXE_valid}},{4{MEM_valid}},{4{WB_valid}}};
    //展示5级的over信号
    assign cpu_5_over = {8'd0         ,{4{IF_over }},{4{ID_over}},{4{REG_over}},
                          {4{EXE_over}},{4{MEM_over}},{4{WB_over}}};
          
//-------------------------{5级流水控制信号}end--------------------------//

//--------------------------{5级间的总线}begin---------------------------//
    wire [ 63:0] IF_ID_bus;   // IF->ID级总线
    wire [188:0] ID_REG_bus;  // ID->REG级总线
    wire [171:0] REG_EXE_bus; // REG->EXE级总线
    wire [153:0] EXE_MEM_bus; // EXE->MEM级总线
    wire [117:0] MEM_WB_bus;  // MEM->WB级总线
    
    //锁存以上总线信号
    reg [ 63:0] IF_ID_bus_r;
    reg [188:0] ID_REG_bus_r;
    reg [171:0] REG_EXE_bus_r;
    reg [153:0] EXE_MEM_bus_r;
    reg [117:0] MEM_WB_bus_r;
    initial begin
        IF_ID_bus_r={64'b0};
        ID_REG_bus_r={177'b0};
        REG_EXE_bus_r={172'b0};
        EXE_MEM_bus_r={154'b0};
        MEM_WB_bus_r={118'b0};
    end
    
    //IF到ID的锁存信号
    always @(posedge clk)
    begin
//        if(IF_over && ID_allow_in)
        //MOD 6级流水预测失败
        if(IF_over && ID_allow_in && ~predict_fail)
        begin
            IF_ID_bus_r <= IF_ID_bus;
        end
    end
    //ID到REG的锁存信号
    always @(posedge clk)
    begin
        if(ID_over && REG_allow_in)
        begin
            ID_REG_bus_r <= ID_REG_bus;
        end
    end
    //REG到EXE的锁存信号
    always @(posedge clk)
    begin
        if(REG_over && EXE_allow_in)
        begin
            REG_EXE_bus_r <= REG_EXE_bus;
        end
    end
    //EXE到MEM的锁存信号
    always @(posedge clk)
    begin
        if(EXE_over && MEM_allow_in)
        begin
            EXE_MEM_bus_r <= EXE_MEM_bus;
        end
    end    
    //MEM到WB的锁存信号
    always @(posedge clk)
    begin
        if(MEM_over && WB_allow_in)
        begin
            MEM_WB_bus_r <= MEM_WB_bus;
        end
    end
//---------------------------{5级间的总线}end----------------------------//

//--------------------------{其他交互信号}begin--------------------------//
    //跳转总线
//    wire [ 32:0] jbr_bus;    
    //MOD 跳转总线
    wire [ 32:0] j_bus;
    wire [ 32:0] br_bus;

    //IF与inst_rom交互
    wire [31:0] inst_addr;
    wire [31:0] inst;

//    ID与EXE、MEM、WB交互 （MOD 其实也是旁路线）
    wire [ 4:0] EXE_wdest;
    wire [ 4:0] MEM_wdest;
    wire [ 4:0] WB_wdest;
    
    //MOD 6级流水旁路数据线
    wire [31:0] EXE_wvalue;
    wire [31:0] MEM_wvalue;
    wire [31:0] WB_wvalue;
    wire EXE_wvalid;
    wire MEM_wvalid;
    wire WB_wvalid;
    
    //MEM与data_ram交互    
    wire [ 3:0] dm_wen;
    wire [31:0] dm_addr;
    wire [31:0] dm_wdata;
    wire [31:0] dm_rdata;

    //ID与regfile交互
    wire [ 4:0] rs;
    wire [ 4:0] rt;   
    wire [31:0] rs_value;
    wire [31:0] rt_value;
    
    //WB与regfile交互
    wire        rf_wen;
    wire [ 4:0] rf_wdest;
    wire [31:0] rf_wdata;    
    
    //WB与IF间的交互信号
    wire [32:0] exc_bus;
//---------------------------{其他交互信号}end---------------------------//

//-------------------------{各模块实例化}begin---------------------------//
    wire next_fetch; //即将运行取指模块，需要先锁存PC值
    //IF允许进入时，即锁存PC值，取下一条指令
    assign next_fetch = IF_allow_in;
    fetch IF_module(             // 取指级
        .clk       (clk       ),  // I, 1
        .resetn    (resetn    ),  // I, 1
        .IF_valid  (IF_valid  ),  // I, 1
        .next_fetch(next_fetch),  // I, 1
        .inst      (inst      ),  // I, 32
//        .jbr_bus   (jbr_bus   ),  // I, 33
        .inst_addr (inst_addr ),  // O, 32
        .IF_over   (IF_over   ),  // O, 1
        .IF_ID_bus (IF_ID_bus ),  // O, 64
        
        //5级流水新增接口
        .exc_bus   (exc_bus   ),  // I, 32
        
        //MOD 6级流水修改
        .br_bus    (br_bus    ), 
        .j_bus    (j_bus    ), 
        
        //展示PC和取出的指令
        .IF_pc     (IF_pc     ),  // O, 32
        .IF_inst   (IF_inst   ),  // O, 32
        .dbg_next_pc(dbg_next_pc)
    );

    decode ID_module(               // 译码级
        .ID_valid   (ID_valid   ),  // I, 1
        .IF_ID_bus_r(IF_ID_bus_r),  // I, 64
//        .rs_value   (rs_value   ),  // I, 32
//        .rt_value   (rt_value   ),  // I, 32
//        .rs         (rs         ),  // O, 5
//        .rt         (rt         ),  // O, 5
//        .jbr_bus    (jbr_bus    ),  // O, 33
        .ID_over    (ID_over    ),  // O, 1
        .ID_EXE_bus (ID_REG_bus),  // O, 167
        
        //5级流水新增
        .IF_over     (IF_over     ),// I, 1
//        .EXE_wdest   (EXE_wdest   ),// I, 5
//        .MEM_wdest   (MEM_wdest   ),// I, 5
//        .WB_wdest    (WB_wdest    ),// I, 5
        
        //MOD 6级流水修改
        .j_bus    (j_bus    ),
        
        //展示PC
        .ID_pc       (ID_pc       ) // O, 32
    );
    
    //MOD 6级流水修改
    read REG_module(               // 读寄存器级
        .REG_valid(REG_valid),
        .ID_REG_bus(ID_REG_bus_r),
        .IF_over     (IF_over     ),// I, 1
        .rs_value   (rs_value   ),  // I, 32
        .rt_value   (rt_value   ),  // I, 32
        .rs         (rs         ),  // O, 5
        .rt         (rt         ),  // O, 5
        .EXE_wdest   (EXE_wdest   ),// I, 5
        .MEM_wdest   (MEM_wdest   ),// I, 5
        .WB_wdest    (WB_wdest    ),// I, 5
        .EXE_wvalue  (EXE_wvalue),
        .MEM_wvalue  (MEM_wvalue),
        .WB_wvalue   (WB_wvalue),
        .EXE_wvalid  (EXE_wvalid),
        .MEM_wvalid  (MEM_wvalid),
        .WB_wvalid   (WB_wvalid ),
        
        .REG_over(REG_over),
        .REG_EXE_bus(REG_EXE_bus),
        .br_bus    (br_bus    ),
        .predict_fail(predict_fail),
        
        .REG_pc(REG_pc)
    );

    exe EXE_module(                   // 执行级
        .EXE_valid   (EXE_valid   ),  // I, 1
        .ID_EXE_bus_r(REG_EXE_bus_r),  // I, 167
        .EXE_over    (EXE_over    ),  // O, 1 
        .EXE_MEM_bus (EXE_MEM_bus ),  // O, 154
        //MOD store rt 的旁路
        .MEM_wdest   (MEM_wdest   ),// I, 5
        .WB_wdest    (WB_wdest    ),// I, 5
        .MEM_wvalue  (MEM_wvalue),
        .WB_wvalue   (WB_wvalue),
        .MEM_wvalid  (MEM_wvalid),
        .WB_wvalid   (WB_wvalid ),
        //5级流水新增
        .clk         (clk         ),  // I, 1
        .EXE_wdest   (EXE_wdest   ),  // O, 5
        
        //数据旁路
        .EXE_wvalue(EXE_wvalue),
        .EXE_wvalid(EXE_wvalid),
        
        //展示PC
        .EXE_pc      (EXE_pc      )   // O, 32
    );

    mem MEM_module(                     // 访存级
        .clk          (clk          ),  // I, 1
        .MEM_valid    (MEM_valid    ),  // I, 1
        .EXE_MEM_bus_r(EXE_MEM_bus_r),  // I, 154
        .dm_rdata     (dm_rdata     ),  // I, 32
        .dm_addr      (dm_addr      ),  // O, 32
        .dm_wen       (dm_wen       ),  // O, 4 
        .dm_wdata     (dm_wdata     ),  // O, 32
        .MEM_over     (MEM_over     ),  // O, 1 
        .MEM_WB_bus   (MEM_WB_bus   ),  // O, 118
        
        //5级流水新增接口
        .MEM_allow_in (MEM_allow_in ),  // I, 1
        .MEM_wdest    (MEM_wdest    ),  // O, 5
        
        //6级旁路
        .MEM_wvalue    (MEM_wvalue  ),
        .MEM_wvalid    (MEM_wvalid  ),
        
        //展示PC
        .MEM_pc       (MEM_pc       )   // O, 32
    );          
 
    wb WB_module(                     // 写回级
        .WB_valid    (WB_valid    ),  // I, 1
        .MEM_WB_bus_r(MEM_WB_bus_r),  // I, 118
        .rf_wen      (rf_wen      ),  // O, 1
        .rf_wdest    (rf_wdest    ),  // O, 5
        .rf_wdata    (rf_wdata    ),  // O, 32
          .WB_over     (WB_over     ),  // O, 1
        
        //5级流水新增接口
        .clk         (clk         ),  // I, 1
      .resetn      (resetn      ),  // I, 1
        .exc_bus     (exc_bus     ),  // O, 32
        .WB_wdest    (WB_wdest    ),  // O, 5
        .cancel      (cancel      ),  // O, 1
        .WB_wvalid   (WB_wvalid   ),
        .WB_wvalue   (WB_wvalue   ),
        
        //展示PC和HI/LO值
        .WB_pc       (WB_pc       ),  // O, 32
        .HI_data     (HI_data     ),  // O, 32
        .LO_data     (LO_data     )   // O, 32
    );

    inst_rom inst_rom_module(         // 指令存储器
        .clka       (clk           ),  // I, 1 ,时钟
        .addra      (inst_addr[9:2]),  // I, 8 ,指令地址
        .douta      (inst          )   // O, 32,指令
    );

    regfile rf_module(        // 寄存器堆模块
        .clk    (clk      ),  // I, 1
        .wen    (rf_wen   ),  // I, 1
        .raddr1 (rs       ),  // I, 5
        .raddr2 (rt       ),  // I, 5
        .waddr  (rf_wdest ),  // I, 5
        .wdata  (rf_wdata ),  // I, 32
        .rdata1 (rs_value ),  // O, 32
        .rdata2 (rt_value ),  // O, 32

        //display rf
        .test_addr(rf_addr),  // I, 5
        .test_data(rf_data)   // O, 32
    );
    
    data_ram data_ram_module(   // 数据存储模块
        .clka   (clk         ),  // I, 1,  时钟
        .wea    (dm_wen      ),  // I, 1,  写使能
        .addra  (dm_addr[9:2]),  // I, 8,  读地址
        .dina   (dm_wdata    ),  // I, 32, 写数据
        .douta  (dm_rdata    ),  // O, 32, 读数据

        //display mem
        .clkb   (clk          ),  // I, 1,  时钟
        .web    (4'd0         ),  // 不使用端口2的写功能
        .addrb  (mem_addr[9:2]),  // I, 8,  读地址
        .doutb  (mem_data     ),  // I, 32, 写数据
        .dinb   (32'd0        )   // 不使用端口2的写功能
    );
//--------------------------{各模块实例化}end----------------------------//
    //展示
    assign dbg_inst=inst;
    assign dbg_IF_allow_in=IF_allow_in;
    assign dbg_inst_addr=inst_addr;
    assign dbg_ID_inst=IF_ID_bus_r[31:0];
    assign dbg_j_bus=j_bus;
    assign dbg_br_bus=br_bus;
    assign dbg_rs=rs;
    assign dbg_rt=rt;
    assign dbg_rs_value=rs_value;
    assign dbg_rt_value=rt_value;
    assign dbg_EXE_wdest=EXE_wdest;
    assign dbg_MEM_wdest=MEM_wdest;
    assign dbg_WB_wdest=WB_wdest;
    assign dbg_EXE_wvalid=EXE_wvalid;
    assign dbg_MEM_wvalid=MEM_wvalid;
    assign dbg_WB_wvalid=WB_wvalid;
    assign dbg_EXE_wvalue=EXE_wvalue;
    assign dbg_MEM_wvalue=MEM_wvalue;
    assign dbg_WB_wvalue=WB_wvalue;
endmodule
