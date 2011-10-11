/*
 *  Ikarus Scheme -- A compiler for R6RS Scheme.
 *  Copyright (C) 2006,2007,2008  Abdulaziz Ghuloum
 *  
 *  This program is free software: you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License version 3 as
 *  published by the Free Software Foundation.
 *  
 *  This program is distributed in the hope that it will be useful, but
 *  WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 *  General Public License for more details.
 *  
 *  You should have received a copy of the GNU General Public License
 *  along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */


#include "ikarus-data.h"
#include <stdio.h>
#include <stdlib.h>
#include <assert.h>
#include <string.h>


#undef DEBUG_EXEC 

ikptr ik_exec_code(ikpcb* pcb, ikptr code_ptr, ikptr argcount, ikptr cp){
  ikptr argc = ik_asm_enter(pcb, code_ptr+off_code_data, argcount, cp);
  ikptr next_k =  pcb->next_k;
  while(next_k){
    cont* k = (cont*)(long)(next_k - vector_tag);
    if (k->tag == system_continuation_tag) {
      break;
    }
    ikptr top = k->top;
    ikptr rp = ref(top, 0);
    long int framesize = (long int) ref(rp, disp_frame_size);
#ifdef DEBUG_EXEC
    fprintf(stderr, "exec framesize=0x%016lx  ksize=%ld  rp=0x%016lx\n", 
        framesize, k->size, rp);
#endif
    if(framesize == 0){
      framesize = ref(top, wordsize);
    }
    if(framesize <= 0){
      fprintf(stderr, "invalid framesize %ld\n", framesize);
      exit(-10);
    }
    if(framesize < k->size){
      cont* nk = (cont*)(long)ik_unsafe_alloc(pcb, sizeof(cont));
      nk->tag = k->tag;
      nk->next = k->next;
      nk->top = top + framesize;
      nk->size = k->size - framesize;
      k->size = framesize;
      k->next = vector_tag + (ikptr)(long)nk;
      /* record side effect */
      unsigned long int idx = ((unsigned long int)(&k->next)) >> pageshift;
      ((unsigned int*)(long)(pcb->dirty_vector))[idx] = -1;
    } else if (framesize > k->size) {
      fprintf(stderr, 
              "ikarus internal error: invalid framesize %ld, expected %ld or less\n",
          framesize, k->size);
      long int offset = ref(rp, disp_frame_offset);
      fprintf(stderr, "rp = 0x%016lx\n", rp);
      fprintf(stderr, "rp offset = %ld\n", offset);
      exit(-10);
    }
    pcb->next_k = k->next;
    ikptr fbase = pcb->frame_base - wordsize;
    ikptr new_fbase = fbase - framesize;
    memmove((char*)(long)new_fbase + argc,
            (char*)(long)fbase + argc,
            -argc);
    memcpy((char*)(long)new_fbase, (char*)(long)top, framesize);
    argc = ik_asm_reenter(pcb, new_fbase, argc);
    next_k =  pcb->next_k;
  }
  ikptr rv = ref(pcb->frame_base, -2*wordsize);
  return rv;
}


