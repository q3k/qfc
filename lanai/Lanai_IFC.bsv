package Lanai_IFC;

import GetPut :: *;
import ClientServer :: *;

import CPU_Defs :: *;

export Word, Lanai_IFC (..), DMemReq (..);

typedef struct {
    Word addr;
    Maybe#(Word) data;
} DMemReq deriving (Bits);

interface Lanai_IFC;
    interface Client #(DMemReq, Word) dmem_client;
    interface Client #(Word, Word) imem_client;
    method Word readPC;
endinterface

endpackage
