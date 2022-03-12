package Lanai_IFC;

import GetPut :: *;
import ClientServer :: *;
import Wishbone :: *;

import CPU_Defs :: *;

export Word, Lanai_IFC (..), DMemReq (..), DMemReqWidth (..);

typedef struct {
    Word addr;
    Maybe#(Word) data;
    DMemReqWidth width;
    Bool spurious;
    Word pc;
} DMemReq deriving (Bits);

interface Lanai_IFC;
    interface Client #(DMemReq, Word) dmem_client;
    interface Client #(Word, Word) imem_client;
    interface Wishbone::Master #(32, 32, 4) sysmem_client;
    method Word readPC;
endinterface

endpackage
