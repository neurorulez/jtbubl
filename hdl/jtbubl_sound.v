/*  This file is part of JTBUBL.
    JTBUBL program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    JTBUBL program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with JTBUBL.  If not, see <http://www.gnu.org/licenses/>.

    Author: Jose Tejada Gomez. Twitter: @topapate
    Version: 1.0
    Date: 02-06-2020 */

module jtbubl_sound(
    input             rst,    // System reset
    input             rstn,   // from Main
    input             clk,
    input             cen3,   //  3   MHz
    // Interface with main CPU
    input      [ 7:0] snd_latch,
    input             snd_stb,
    output reg [ 7:0] main_latch,    
    output reg        main_stb,
    output            snd_flag,
    input             main_flag,
    // ROM
    output     [14:0] rom_addr,
    output  reg       rom_cs,
    input      [ 7:0] rom_data,
    input             rom_ok,

    // Sound output
    output signed [15:0] snd,
    output            sample
);

wire        [15:0] A;
wire               iorq_n, m1_n, wr_n, rd_n;
wire        [ 7:0] ram_dout, dout, fm0_dout, fm1_dout;
reg                ram_cs, fm1_cs, fm0_cs, io_cs, nmi_en;
wire               mreq_n, rfsh_n;
reg         [ 7:0]  din;
wire               intn_fm0, intn_fm1;
wire               int_n;
wire               flag_clr;
wire               nmi_n;
wire signed [15:0] fm0_snd,  fm1_snd;
wire        [ 9:0] psg_snd;
wire signed [ 9:0] psg2x; // DC-removed version of psg0
wire               snd_rstn = ~rst & rstn;

assign int_n      = intn_fm0 & intn_fm1;
assign rom_addr   = A[14:0];
assign nmi_n      = snd_flag | ~nmi_en;
assign flag_clr   = (io_cs && !rd_n && A[1:0]==2'b0) || ~snd_rstn;

always @(*) begin
    rom_cs = !mreq_n && !A[15];
    ram_cs = !mreq_n &&  A[15] && A[14:12]==3'b00;
    fm0_cs = !mreq_n &&  A[15] && A[14:12]==3'b01;
    fm1_cs = !mreq_n &&  A[15] && A[14:12]==3'b10;
    io_cs  = !mreq_n &&  A[15] && A[14:12]==3'b11;
end

always @(posedge clk) begin
    case( 1'b1 )
        rom_cs:   din <= rom_data;
        fm0_cs:   din <= fm0_dout;
        fm1_cs:   din <= fm1_dout;
        io_cs:    din <= A[1] ? 8'hff : (
                         A[0] ? {6'h3f, main_stb, snd_flag} : snd_latch);
        ram_cs:   din <= ram_dout;
        default:  din <= 8'hff;
    endcase
end

always @(posedge clk, negedge snd_rstn) begin
    if( !snd_rstn ) begin
        main_latch <= 8'h00;
        main_stb   <= 0;
        nmi_en     <= 0;
    end else begin
        if( io_cs && !wr_n ) begin
            case( A[1:0] )
                2'd0: begin
                    main_latch <= dout;
                    main_stb   <= 1;
                end
                2'd1: nmi_en     <= 1; // enables NMI
                2'd2: nmi_en     <= 0;
            endcase
        end else begin
            main_stb <= 0;
        end
    end
end

jtframe_ff u_flag(
    .clk    ( clk      ),
    .rst    ( rst      ),
    .cen    ( 1'b1     ),
    .din    ( 1'b1     ),
    .q      (          ),
    .qn     ( snd_flag ),
    .set    ( 1'b0     ),
    .clr    ( flag_clr ),
    .sigedge( snd_stb  )
);

jtframe_sysz80 #(.RAM_AW(13)) u_cpu(
    .rst_n      ( snd_rstn    ),
    .clk        ( clk         ),
    .cen        ( cen3        ),
    .cpu_cen    (             ),
    .int_n      ( int_n       ),
    .nmi_n      ( nmi_n       ),
    .busrq_n    ( 1'b1        ),
    .m1_n       (             ),
    .mreq_n     ( mreq_n      ),
    .iorq_n     (             ),
    .rd_n       ( rd_n        ),
    .wr_n       ( wr_n        ),
    .rfsh_n     (             ),
    .halt_n     (             ),
    .busak_n    (             ),
    .A          ( A           ),
    .cpu_din    ( din         ),
    .cpu_dout   ( dout        ),
    .ram_dout   ( ram_dout    ),
    .ram_cs     ( ram_cs      ),
    .rom_cs     ( rom_cs      ),
    .rom_ok     ( rom_ok      )
);

jt49_dcrm2 #(.sw(10)) u_dcrm (
    .clk    (  clk      ),
    .cen    (  cen3     ),
    .rst    (  rst      ),
    .din    (  psg_snd  ),
    .dout   (  psg2x    )
);

// Both FM chips have the same gain according to the schematics
// YM2203 to YM3526 ratio = 8:1
jt12_mixer #(.w0(16),.w1(16),.w2(10),.w3(8),.wout(16)) u_mixer(
    .clk    ( clk          ),
    .cen    ( cen3         ),
    .ch0    ( fm0_snd      ),
    .ch1    ( fm1_snd      ),
    .ch2    ( psg2x        ),
    .ch3    ( 8'd0         ),
    .gain0  ( 8'hC0        ), // YM2203 - Fx
    .gain1  ( 8'h18        ), // YM3526 - Music
    .gain2  ( 8'h60        ), // PSG - Unused?
    .gain3  ( 8'd0         ),
    .mixed  ( snd          )
);

jt03 u_2203(
    .rst        ( ~snd_rstn  ),
    .clk        ( clk        ),
    .cen        ( cen3       ),
    .din        ( dout       ),
    .dout       ( fm0_dout   ),
    .addr       ( A[0]       ),
    .cs_n       ( ~fm0_cs    ),
    .wr_n       ( wr_n       ),
    .psg_snd    ( psg_snd    ),
    .fm_snd     ( fm0_snd    ),
    .snd_sample ( sample     ),
    .irq_n      ( intn_fm0   ),
    // unused outputs
    .psg_A      (            ),
    .psg_B      (            ),
    .psg_C      (            ),
    .snd        (            )
);

jtopl u_opl(
    .rst        ( ~snd_rstn  ),
    .clk        ( clk        ),
    .cen        ( cen3       ),
    .din        ( dout       ),
    .dout       ( fm1_dout   ),
    .addr       ( A[0]       ),
    .cs_n       ( ~fm1_cs    ),
    .wr_n       ( wr_n       ),
    .irq_n      ( intn_fm1   ),
    .snd        ( fm1_snd    ),
    .sample     ( sample     )
);

`ifdef SIMULATION
    integer fsnd;
    initial begin
        fsnd=$fopen("fm_sound.raw","wb");
    end
    always @(posedge sample) begin
        $fwrite(fsnd,"%u", {fm0_snd, fm1_snd});
    end
`endif

endmodule