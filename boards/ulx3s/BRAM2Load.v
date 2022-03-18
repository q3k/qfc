// Taken from github.com/B-Lang-org/bsc, file src/Verilog/BRAM2Load.v.
// Modified to remove write enable from second port, allowing Yosys to infer
// that this is not a true dual-ported BRAM.
//
// Copyright (c) 2020 Bluespec, Inc. All rights reserved.
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are
// met:
// 
// 1. Redistributions of source code must retain the above copyright
//    notice, this list of conditions and the following disclaimer.
// 
// 2. Redistributions in binary form must reproduce the above copyright
//    notice, this list of conditions and the following disclaimer in the
//    documentation and/or other materials provided with the
//    distribution.
// 
// 3. Neither the name of the copyright holder nor the names of its
//    contributors may be used to endorse or promote products derived
//    from this software without specific prior written permission.
// 
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
// "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
// LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
// A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
// HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
// SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
// LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
// DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
// THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
// OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//
// SPDX-License-Identifier: BSD-3-Clause

`ifdef BSV_ASSIGNMENT_DELAY
`else
 `define BSV_ASSIGNMENT_DELAY
`endif

// Dual-Ported BRAM (WRITE FIRST)
module BRAM2Load(CLKA,
                 ENA,
                 WEA,
                 ADDRA,
                 DIA,
                 DOA,
                 CLKB,
                 ENB,
                 WEB,
                 ADDRB,
                 DIB,
                 DOB
                 );

   parameter                      FILENAME   = "";
   parameter                      PIPELINED  = 0;
   parameter                      ADDR_WIDTH = 1;
   parameter                      DATA_WIDTH = 1;
   parameter                      MEMSIZE    = 1;
   parameter                      BINARY     = 0;

   input                          CLKA;
   input                          ENA;
   input                          WEA;
   input [ADDR_WIDTH-1:0]         ADDRA;
   input [DATA_WIDTH-1:0]         DIA;
   output [DATA_WIDTH-1:0]        DOA;

   input                          CLKB;
   input                          ENB;
   input                          WEB;
   input [ADDR_WIDTH-1:0]         ADDRB;
   input [DATA_WIDTH-1:0]         DIB;
   output [DATA_WIDTH-1:0]        DOB;

   reg [DATA_WIDTH-1:0]           RAM[0:MEMSIZE-1] /* synthesis syn_ramstyle="no_rw_check" */ ;
   reg [DATA_WIDTH-1:0]           DOA_R;
   reg [DATA_WIDTH-1:0]           DOB_R;
   reg [DATA_WIDTH-1:0]           DOA_R2;
   reg [DATA_WIDTH-1:0]           DOB_R2;

   // synopsys translate_off
   initial
   begin : init_block
`ifdef BSV_NO_INITIAL_BLOCKS
`else
      DOA_R = { ((DATA_WIDTH+1)/2) { 2'b10 } };
      DOB_R = { ((DATA_WIDTH+1)/2) { 2'b10 } };
      DOA_R2 = { ((DATA_WIDTH+1)/2) { 2'b10 } };
      DOB_R2 = { ((DATA_WIDTH+1)/2) { 2'b10 } };
`endif // !`ifdef BSV_NO_INITIAL_BLOCKS
   end
   // synopsys translate_on

   initial
   begin : init_rom_block
      if (BINARY)
        $readmemb(FILENAME, RAM, 0, MEMSIZE-1);
      else
        $readmemh(FILENAME, RAM, 0, MEMSIZE-1);
   end

   always @(posedge CLKA) begin
      if (ENA) begin
         //if (WEA) begin
         //   RAM[ADDRA] <= `BSV_ASSIGNMENT_DELAY DIA;
         //   DOA_R <= `BSV_ASSIGNMENT_DELAY DIA;
         //end else begin
            DOA_R <= `BSV_ASSIGNMENT_DELAY RAM[ADDRA];
         //end
      end
      DOA_R2 <= `BSV_ASSIGNMENT_DELAY DOA_R;
   end

   always @(posedge CLKB) begin
      if (ENB) begin
         if (WEB) begin
            RAM[ADDRB] <= `BSV_ASSIGNMENT_DELAY DIB;
            DOB_R <= `BSV_ASSIGNMENT_DELAY DIB;
         end
         else begin
            DOB_R <= `BSV_ASSIGNMENT_DELAY RAM[ADDRB];
         end
      end
      DOB_R2 <= `BSV_ASSIGNMENT_DELAY DOB_R;
   end

   // Output drivers
   assign DOA = (PIPELINED) ? DOA_R2 : DOA_R;
   assign DOB = (PIPELINED) ? DOB_R2 : DOB_R;

endmodule // BRAM2Load
