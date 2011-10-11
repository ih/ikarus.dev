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



#include "bootfileloc.h"
#include "ikarus-data.h"
#include <stdio.h>
#include <stdlib.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <string.h>
#include <errno.h>
#include <gmp.h>
#include <signal.h>
#include <sys/mman.h>


void register_handlers();
void register_alt_stack();


ikpcb* the_pcb;

int
file_exists(char* filename){
  struct stat sb;
  int s = stat(filename, &sb);
  return (s == 0);
}

extern int cpu_has_sse2();

int ikarus_main(int argc, char** argv, char* boot_file){
  if(! cpu_has_sse2()){
    fprintf(stderr, "Ikarus Scheme cannot run on your computer because\n");
    fprintf(stderr, "your CPU does not support the SSE2 instruction set.\n");
    fprintf(stderr, "Refer to the Ikarus Scheme User's Guide for the\n");
    fprintf(stderr, "minimum hardware requirements.\n");
    exit(-1);
  }
  if(sizeof(mp_limb_t) != sizeof(long int)){
    fprintf(stderr, "ERROR: limb size does not match\n");
    exit(-1);
  }
  if(mp_bits_per_limb != (8*sizeof(long int))){
    fprintf(stderr, "ERROR: invalid bits_per_limb=%d\n", mp_bits_per_limb);
    exit(-1);
  }
  ikpcb* pcb = ik_make_pcb();
  the_pcb = pcb;
  { /* set up arg_list */
    ikptr arg_list = null_object;
    int i = argc-1;
    while(i > 0){
      char* s = argv[i];
      int n = strlen(s);
      ikptr bv = ik_unsafe_alloc(pcb, align(disp_bytevector_data+n+1)) 
                 + bytevector_tag;
      ref(bv, off_bytevector_length) = fix(n);
      memcpy((char*)(bv+off_bytevector_data), s, n+1);
      ikptr p = ik_unsafe_alloc(pcb, pair_size);
      ref(p, disp_car) = bv;
      ref(p, disp_cdr) = arg_list;
      arg_list = p+pair_tag;
      i--;
    }
    pcb->arg_list = arg_list;
  }
  register_handlers();
  register_alt_stack();
  ik_fasl_load(pcb, boot_file);
  /*
  fprintf(stderr, "collect time: %d.%03d utime, %d.%03d stime (%d collections)\n", 
                  pcb->collect_utime.tv_sec, 
                  pcb->collect_utime.tv_usec/1000, 
                  pcb->collect_stime.tv_sec, 
                  pcb->collect_stime.tv_usec/1000,
                  pcb->collection_id );
                  */
  ik_delete_pcb(pcb);
  return 0;
}

#if 0
Notice how the bsd manpages have incorrect type for the handler.

     #include <signal.h>

     struct  sigaction {
             union {
                     void    (*__sa_handler)(int);
                     void    (*__sa_sigaction)(int, struct __siginfo *, void *);
             } __sigaction_u;                /* signal handler */
             int     sa_flags;               /* see signal options below */
             sigset_t sa_mask;               /* signal mask to apply */
     };

     #define sa_handler      __sigaction_u.__sa_handler
     #define sa_sigaction    __sigaction_u.__sa_sigaction

     int
     sigaction(int sig, const struct sigaction * restrict act,
         struct sigaction * restrict oact);
#endif

void handler(int signo, siginfo_t* info, void* uap){
  signo=signo; info=info; uap=uap; /* no warning */
  the_pcb->engine_counter = fix(-1);
  the_pcb->interrupted = 1;
}

void
register_handlers(){
  struct sigaction sa;
  sa.sa_sigaction = handler;
#ifdef __CYGWIN__
  sa.sa_flags = SA_SIGINFO;
#else
  sa.sa_flags = SA_SIGINFO | SA_ONSTACK;
#endif
  sigemptyset(&sa.sa_mask);
  int err = sigaction(SIGINT, &sa, 0);
  if(err){
    fprintf(stderr, "Sigaction Failed: %s\n", strerror(errno));
    exit(-1);
  }

  /* ignore sigpipes */
  {
    sigset_t set;
    sigprocmask(0, 0, &set); /* get the set */
    sigaddset(&set, SIGPIPE);
    int err = sigprocmask(SIG_SETMASK, &set, &set);
    if(err){
      fprintf(stderr, "Sigprocmask Failed: %s\n", strerror(errno));
      exit(-1);
    }
  }
}


#if 0
SYNOPSIS
     #include <sys/types.h>
     #include <signal.h>

     struct sigaltstack {
             char   *ss_sp;
             int     ss_size;
             int     ss_flags;
     };

     int
     sigaltstack(const struct sigaltstack *ss, struct sigaltstack *oss);
#endif

void
register_alt_stack(){
#if HAVE_SIGALTSTACK
  char* stk = mmap(0, SIGSTKSZ, PROT_READ|PROT_WRITE|PROT_EXEC, 
                   MAP_PRIVATE|MAP_ANON, -1, 0);
//  char* stk = ik_mmap(SIGSTKSZ);
  if(stk == (char*)-1){
    fprintf(stderr, "Cannot maloc an alt stack\n");
    exit(-1);
  }

  stack_t sa;
  sa.ss_sp = stk;
  sa.ss_size = SIGSTKSZ;
  sa.ss_flags = 0;
  int err = sigaltstack(&sa, 0);
  if(err){
    fprintf(stderr, "Cannot set alt stack: %s\n", strerror(errno));
    exit(-1);
  }
#endif
}
