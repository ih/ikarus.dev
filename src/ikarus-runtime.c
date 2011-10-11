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
#include <time.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <limits.h>
#include <fcntl.h>
#include <string.h>
#include <strings.h>
#include <errno.h>
#include <unistd.h>
#include <sys/mman.h>
#include <assert.h>
#include <sys/time.h>
#include <sys/resource.h>
#include <sys/wait.h>
#include <sys/param.h>
#include <dirent.h>
#ifdef __CYGWIN__
#include "ikarus-winmmap.h"
#endif


extern ikptr ik_errno_to_code();

int total_allocated_pages = 0;
         
extern char **environ;


#define segment_size  (pagesize*pagesize/4)
#define segment_shift (pageshift+pageshift-2)
#define segment_index(x) (((unsigned long int)(x)) >> segment_shift)

ikptr ik_mmap(unsigned long int size);
void ik_munmap(ikptr mem, unsigned long int size);

static void
extend_table_maybe(ikptr p, unsigned long int size, ikpcb* pcb){
  assert(size == align_to_next_page(size));
  ikptr q = p + size;
  if(p < pcb->memory_base){
    unsigned long int new_lo = segment_index(p);
    unsigned long int old_lo = segment_index(pcb->memory_base);
    unsigned long int hi = segment_index(pcb->memory_end);
    unsigned long int new_vec_size = (hi - new_lo) * pagesize;
    unsigned long int old_vec_size = (hi - old_lo) * pagesize;
    ikptr v = ik_mmap(new_vec_size);
    bzero((char*)(long)v, new_vec_size - old_vec_size);
    memcpy((char*)(long)(v+new_vec_size-old_vec_size),
           (char*)(long)pcb->dirty_vector_base, 
           old_vec_size);
    ik_munmap((ikptr)(long)pcb->dirty_vector_base, old_vec_size);
    pcb->dirty_vector_base = (unsigned int*)(long)v;
    pcb->dirty_vector = (v - new_lo * pagesize);
    ikptr s = ik_mmap(new_vec_size);
    bzero((char*)(long)s, new_vec_size - old_vec_size);
    memcpy((char*)(long)(s+new_vec_size-old_vec_size),
           (char*)(long)(pcb->segment_vector_base), 
           old_vec_size);
    ik_munmap((ikptr)(long)pcb->segment_vector_base, old_vec_size);
    pcb->segment_vector_base = (unsigned int*)(long)s;
    pcb->segment_vector = (unsigned int*)(long)(s - new_lo * pagesize);
    pcb->memory_base = (new_lo * segment_size);
  } 
  else if (q >= pcb->memory_end){
    unsigned long int lo = segment_index(pcb->memory_base);
    unsigned long int old_hi = segment_index(pcb->memory_end);
    unsigned long int new_hi = segment_index(q+segment_size-1);
    unsigned long int new_vec_size = (new_hi - lo) * pagesize;
    unsigned long int old_vec_size = (old_hi - lo) * pagesize;
    ikptr v = ik_mmap(new_vec_size);
    memcpy((char*)(long)v, 
           (char*)(long)pcb->dirty_vector_base,
           old_vec_size);
    bzero((char*)(long)(v+old_vec_size), new_vec_size - old_vec_size);
    ik_munmap((ikptr)(long)pcb->dirty_vector_base, old_vec_size);
    pcb->dirty_vector_base = (unsigned int*)(long)v;
    pcb->dirty_vector = (v - lo * pagesize);
    ikptr s = ik_mmap(new_vec_size);
    memcpy((char*)(long)s, pcb->segment_vector_base, old_vec_size);
    bzero((char*)(long)(s+old_vec_size), new_vec_size - old_vec_size);
    ik_munmap((ikptr)(long)pcb->segment_vector_base, old_vec_size);
    pcb->segment_vector_base = (unsigned int*)(long) s;
    pcb->segment_vector = (unsigned int*)(s - lo * pagesize);
    pcb->memory_end = (new_hi * segment_size);
  }
}


static void
set_segment_type(ikptr base, unsigned long int size, unsigned int type, ikpcb* pcb){
  assert(base >= pcb->memory_base);
  assert((base+size) <= pcb->memory_end);
  assert(size == align_to_next_page(size));
  unsigned int* p = pcb->segment_vector + page_index(base);
  unsigned int* q = p + page_index(size);
  while(p < q){
    *p = type;
    p++;
  }
}

void
ik_munmap_from_segment(ikptr base, unsigned long int size, ikpcb* pcb){
  assert(base >= pcb->memory_base);
  assert((base+size) <= pcb->memory_end);
  assert(size == align_to_next_page(size));
  unsigned int* p = 
    ((unsigned int*)(long)(pcb->segment_vector)) + page_index(base);
  unsigned int* s = 
    ((unsigned int*)(long)(pcb->dirty_vector)) + page_index(base);
  unsigned int* q = p + page_index(size);
  while(p < q){
    assert(*p != hole_mt);
    *p = hole_mt; /* holes */
    *s = 0;  
    p++; s++;
  }
  ikpage* r = pcb->uncached_pages;
  if (r){
    ikpage* cache = pcb->cached_pages;
    do{
      r->base = base;
      ikpage* next = r->next;
      r->next = cache;
      cache = r;
      r = next;
      base += pagesize;
      size -= pagesize;
    } while(r && size);
    pcb->cached_pages = cache;
    pcb->uncached_pages = r;
  }
  if(size){
    ik_munmap(base, size);
  }
}



ikptr
ik_mmap_typed(unsigned long int size, unsigned int type, ikpcb* pcb){
  ikptr p;
  if(size == pagesize) {
    ikpage* s = pcb->cached_pages;
    if(s){
      p = s->base;
      pcb->cached_pages = s->next;
      s->next = pcb->uncached_pages;
      pcb->uncached_pages = s; 
    } 
    else {
      p = ik_mmap(size);
    }
  } 
  else {
    p = ik_mmap(size);
  }
  extend_table_maybe(p, size, pcb);
  set_segment_type(p, size, type, pcb);
  return p;
}

ikptr
ik_mmap_ptr(unsigned long int size, int gen, ikpcb* pcb){
  return ik_mmap_typed(size, pointers_mt | gen, pcb);
}

ikptr
ik_mmap_data(unsigned long int size, int gen, ikpcb* pcb){
  return ik_mmap_typed(size, data_mt | gen, pcb);
}

ikptr
ik_mmap_code(unsigned long int size, int gen, ikpcb* pcb){
  ikptr p = ik_mmap_typed(size, code_mt | gen, pcb);
  if(size > pagesize){
    set_segment_type(p+pagesize, size-pagesize, data_mt|gen, pcb);
  }
  return p;
}


ikptr
ik_mmap_mixed(unsigned long int size, ikpcb* pcb){
  return ik_mmap_typed(size, mainheap_mt, pcb);
}




ikptr
ik_mmap(unsigned long int size){
  unsigned long int pages = (size + pagesize - 1) / pagesize;
  total_allocated_pages += pages;
  unsigned long int mapsize = pages * pagesize;
  assert(size == mapsize);
#ifndef __CYGWIN__
  char* mem = mmap(
      0,
      mapsize,
      PROT_READ | PROT_WRITE | PROT_EXEC,
      MAP_PRIVATE | MAP_ANON,
      -1,
      0);
  /* FIXME: check if in range */
  if(mem == MAP_FAILED){
    fprintf(stderr, "Mapping (0x%lx bytes) failed: %s\n", size, strerror(errno));
    exit(-1);
  }
#else
  char* mem = win_mmap(mapsize);
#endif
  memset(mem, -1, mapsize);
#ifndef NDEBUG
  fprintf(stderr, "MMAP 0x%016lx .. 0x%016lx\n", (long int)mem,
      ((long int)(mem))+mapsize-1);
#endif
  return (ikptr)(long)mem;
}

void
ik_munmap(ikptr mem, unsigned long int size){
  unsigned long int pages = (size + pagesize - 1) / pagesize;
  unsigned long int mapsize = pages * pagesize;
  assert(size == mapsize);
  assert(((-pagesize) & (int)mem) == (int)mem);
  total_allocated_pages -= pages;
#ifndef __CYGWIN__
  int err = munmap((char*)mem, mapsize);
  if(err != 0){
    fprintf(stderr, "ik_munmap failed: %s\n", strerror(errno));
    exit(-1);
  }
#else 
  win_munmap((char*)mem, mapsize);
#endif
#ifndef NDEBUG
  fprintf(stderr, "UNMAP 0x%016lx .. 0x%016lx\n", (long int)mem,
      ((long int)(mem))+mapsize-1);
#endif
}

int total_malloced = 0;

void* 
ik_malloc(int size){
  void* x = malloc(size);
  if(x == NULL){
    fprintf(stderr, "malloc failed: %s\n", strerror(errno));
    exit(-1);
  }
  total_malloced += size;
  return x;
}

void ik_free(void* x, int size){
  total_malloced -= size;
  free(x);
}


#define CACHE_SIZE (pagesize * 1) /* must be multiple of pagesize*/

ikpcb* ik_make_pcb(){
  ikpcb* pcb = ik_malloc(sizeof(ikpcb));
  bzero(pcb, sizeof(ikpcb));
  pcb->collect_key = false_object;
  #define STAKSIZE (1024 * 4096)
  //#define STAKSIZE (256 * 4096)
  pcb->heap_base = ik_mmap(IK_HEAPSIZE);
  pcb->heap_size = IK_HEAPSIZE;
  pcb->allocation_pointer = pcb->heap_base;
  pcb->allocation_redline = pcb->heap_base + IK_HEAPSIZE - 2 * 4096;

  pcb->stack_base = ik_mmap(STAKSIZE);
  pcb->stack_size = STAKSIZE;
  pcb->frame_pointer = pcb->stack_base + pcb->stack_size;
  pcb->frame_base = pcb->frame_pointer;
  pcb->frame_redline = pcb->stack_base + 2 * 4096;


  { /* make cache ikpage */
    ikpage* p = (ikpage*)(long)ik_mmap(CACHE_SIZE * sizeof(ikpage));
    pcb->cached_pages_base = (ikptr)(long)p;
    pcb->cached_pages_size = CACHE_SIZE * sizeof(ikpage);
    ikpage* q = 0;
    ikpage* e = p + CACHE_SIZE;
    while(p < e){
      p->next = q;
      q = p;
      p++;
    }
    pcb->uncached_pages = q;
  }

  {
    /* compute extent of heap and stack */
    ikptr lo_mem;
    ikptr hi_mem;
    if(pcb->heap_base < pcb->stack_base){
      lo_mem = pcb->heap_base - pagesize;
      hi_mem = pcb->stack_base + pcb->stack_size + pagesize;
    } else {
      lo_mem = pcb->stack_base - pagesize;
      hi_mem = pcb->heap_base + pcb->heap_size + pagesize;
    }

    unsigned long int lo_seg = segment_index(lo_mem);
    unsigned long int hi_seg = segment_index(hi_mem+segment_size-1);
    unsigned long int vec_size = (hi_seg - lo_seg) * pagesize;
    ikptr dvec = ik_mmap(vec_size);
    bzero((char*)(long)dvec, vec_size);
    pcb->dirty_vector_base = (unsigned int*)(long) dvec;
    pcb->dirty_vector = (dvec - lo_seg * pagesize);
    ikptr svec = ik_mmap(vec_size);
    bzero((char*)(long)svec, vec_size);
    pcb->segment_vector_base = (unsigned int*)(long)svec;
    pcb->segment_vector = (unsigned int*)(long)(svec - lo_seg * pagesize);
    pcb->memory_base = (ikptr)(lo_seg * segment_size);
    pcb->memory_end = (ikptr)(hi_seg * segment_size);
    set_segment_type(pcb->heap_base, 
        pcb->heap_size,
        mainheap_mt,
        pcb);
    set_segment_type(pcb->stack_base, 
        pcb->stack_size, 
        mainstack_mt,
        pcb);
  }
  /* initialize base rtd */
  {
    ikptr r = ik_unsafe_alloc(pcb, align(rtd_size)) + rtd_tag;
    ref(r, off_rtd_rtd) = r;
    ref(r, off_rtd_length) = (ikptr) (rtd_size-wordsize);
    ref(r, off_rtd_name) = 0;
    ref(r, off_rtd_fields) = 0;
    ref(r, off_rtd_printer) = 0;
    ref(r, off_rtd_symbol) = 0;
    pcb->base_rtd = r;
  }
  return pcb;
}

void ik_delete_pcb(ikpcb* pcb){
  ikpage* p = pcb->cached_pages;
  pcb->cached_pages = 0;
  pcb->uncached_pages = 0;
  while(p){
    ik_munmap(p->base, pagesize);
    p = p->next;
  }
  ik_munmap(pcb->cached_pages_base, pcb->cached_pages_size);
  {
    int i;
    for(i=0; i<generation_count; i++){
      ik_ptr_page* p = pcb->protected_list[i];
      while(p){
        ik_ptr_page* next = p->next;
        ik_munmap((ikptr)(long)p, pagesize);
        p = next;
      }
    }
  }
  ikptr base = pcb->memory_base;
  ikptr end = pcb->memory_end;
  unsigned int* segment_vec = pcb->segment_vector;
  long int i = page_index(base);
  long int j = page_index(end);
  while(i < j){
    unsigned int t = segment_vec[i];
    if(t != hole_mt){
      ik_munmap((ikptr)(i<<pageshift), pagesize);
    }
    i++;
  }
  long int vecsize = (segment_index(end) - segment_index(base)) * pagesize;
  ik_munmap((ikptr)(long)pcb->dirty_vector_base, vecsize);
  ik_munmap((ikptr)(long)pcb->segment_vector_base, vecsize);
  ik_free(pcb, sizeof(ikpcb));
}

ikptr
ik_safe_alloc(ikpcb* pcb, int size){
  assert(size == align(size));
  ikptr ap = pcb->allocation_pointer;
  ikptr ep = pcb->heap_base + pcb->heap_size;
  ikptr nap = ap + size;
  if(nap < ep){
    pcb->allocation_pointer = nap;
    return ap;
  } 
  else {
    ik_collect(size, pcb);
    ikptr ap = pcb->allocation_pointer;
    ikptr ep = pcb->heap_base + pcb->heap_size;
    ikptr nap = ap + size;
    if(nap < ep){
      pcb->allocation_pointer = nap;
      return ap;
    } else {
      fprintf(stderr,
              "ikaurs: BUG: collector did not leave enough room for %d\n",
               size);
      exit(-1);
    }
  }
}




ikptr
ik_unsafe_alloc(ikpcb* pcb, int size){
  assert(size == align(size));
  ikptr ap = pcb->allocation_pointer;
  ikptr ep = pcb->heap_base + pcb->heap_size;
  ikptr nap = ap + size;
  if(nap < ep){
    pcb->allocation_pointer = nap;
    return ap;
  } 
  else {
    if(ap){
      ikpages* p = ik_malloc(sizeof(ikpages));
      p->base = pcb->heap_base;
      p->size = pcb->heap_size;
      p->next = pcb->heap_pages;
      pcb->heap_pages = p;
    }

    { /* ACCOUNTING */
      long int bytes =
        ((long int)pcb->allocation_pointer) -
        ((long int)pcb->heap_base);
      long int minor = bytes + pcb->allocation_count_minor;
      while(minor >= most_bytes_in_minor){
        minor -= most_bytes_in_minor;
        pcb->allocation_count_major++;
      }
      pcb->allocation_count_minor = minor;
    }

    int new_size = (size > IK_HEAP_EXT_SIZE) ? size : IK_HEAP_EXT_SIZE;
    new_size += 2 * 4096;
    new_size = align_to_next_page(new_size);
    ap = ik_mmap_mixed(new_size, pcb);
    pcb->heap_base = ap;
    pcb->heap_size = new_size;
    pcb->allocation_redline = ap + new_size - 2 * 4096;
    nap = ap + size;
    pcb->allocation_pointer = nap;
    return ap;
  }
}



void ik_error(ikptr args){
  fprintf(stderr, "Error: ");
  ik_fprint(stderr, args);
  fprintf(stderr, "\n");
  exit(0);
}


void ik_stack_overflow(ikpcb* pcb){
#ifndef NDEBUG
  fprintf(stderr, "entered ik_stack_overflow pcb=0x%016lx\n", (long int)pcb);
#endif
  set_segment_type(pcb->stack_base, pcb->stack_size, data_mt, pcb);
  
  ikptr frame_base = pcb->frame_base;
  ikptr underflow_handler = ref(frame_base, -wordsize);
#ifndef NDEBUG
  fprintf(stderr, "underflow_handler = 0x%08x\n", (int)underflow_handler);
#endif
  /* capture continuation and set it as next_k */
  ikptr k = ik_unsafe_alloc(pcb, align(continuation_size)) + vector_tag;
  ref(k, -vector_tag) = continuation_tag;
  ref(k, off_continuation_top) = pcb->frame_pointer;
  ref(k, off_continuation_size) = 
    pcb->frame_base - pcb->frame_pointer - wordsize;
  ref(k, off_continuation_next) = pcb->next_k;
  pcb->next_k = k;

  pcb->stack_base = (ikptr)(long)ik_mmap_typed(STAKSIZE, mainstack_mt, pcb);
  pcb->stack_size = STAKSIZE;
  pcb->frame_base = pcb->stack_base + pcb->stack_size;
  pcb->frame_pointer = pcb->frame_base - wordsize;
  pcb->frame_redline = pcb->stack_base + 2 * 4096;
  ref(pcb->frame_pointer, 0) = underflow_handler;
  return;
}

/*
char* ik_uuid(char* str){
  assert((36 << fx_shift) == (int) ref(str, disp_string_length - string_tag));
  uuid_t u;
  uuid_clear(u); 
  uuid_generate(u);
  uuid_unparse_upper(u, str + disp_string_data - string_tag);
  return str;
}
*/


static const char* uuid_chars = 
"!$%&/0123456789<=>?ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz";
static int uuid_strlen = 1;
ikptr ik_uuid(ikptr bv){
  static int fd = -1;
  if(fd == -1){
    fd = open("/dev/urandom", O_RDONLY);
    if(fd == -1){
      return ik_errno_to_code();
    }
    uuid_strlen = strlen(uuid_chars);
  }
  long int n = unfix(ref(bv, off_bytevector_length));
  unsigned char* data = (unsigned char*)(long)(bv+off_bytevector_data);
  int r = read(fd, data, n);
  if(r < 0){
    return ik_errno_to_code();
  }
  unsigned char* p = data;
  unsigned char* q = data + n;
  while(p < q){
    *p = uuid_chars[*p % uuid_strlen];
    p++;
  }
  return bv;
}


ikptr
ikrt_stat(ikptr filename, ikptr follow /*, ikpcb* pcb */){
  char* fn = (char*)(filename + off_bytevector_data);
  struct stat s;
  int r;
  if(follow == false_object){
    r = lstat(fn, &s);
  } else{
    r = stat(fn, &s);
  }
  if(r == 0){
    if(S_ISREG(s.st_mode)){
      return fix(1);
    } 
    else if(S_ISDIR(s.st_mode)){
      return fix(2);
    }
    else if(S_ISLNK(s.st_mode)){
      return fix(3);
    }
    else {
      return fix(0);
    }
  }  
  return ik_errno_to_code();
}


/* ikrt_file_exists needs to be removed.
   This is here only to be able to use old ikarus.boot.prebuilt */
ikptr
ikrt_file_exists(ikptr filename /*, ikpcb* pcb */){
  switch (ikrt_stat(filename, true_object /*, pcb */)){
    case fix(0):
    case fix(1):
    case fix(2):
    case fix(3):
      return true_object;
    default:
      return false_object;
  }
}

ikptr
ikrt_delete_file(ikptr filename){
  char* str;
  if(tagof(filename) == bytevector_tag){
    str = (char*)(long)(filename + off_bytevector_data);
  } else {
    fprintf(stderr, "bug in ikrt_delete_file\n");
    exit(-1);
  }
  int err = unlink(str);
  if(err == 0){
    return true_object;
  } 
  return ik_errno_to_code();
}

ikptr
ikrt_directory_list(ikptr filename, ikpcb* pcb){
  DIR* dir;
  struct dirent* de;
  if((dir = opendir((char*)(filename + off_bytevector_data))) == NULL){
    return ik_errno_to_code();
  }
  ikptr ac = null_object;
  pcb->root0 = &ac;
  while(1){
    errno = 0;
    de = readdir(dir);
    if(de == NULL){
      pcb->root0 = 0;
      ikptr retval = (errno ? ik_errno_to_code() : ac);
      closedir(dir);
      return retval;
    }
    int len = strlen(de->d_name);
    ikptr bv = ik_safe_alloc(pcb, align(disp_bytevector_data+len+1))
               + bytevector_tag;
    ref(bv, off_bytevector_length) = fix(len);
    memcpy((char*)(bv+off_bytevector_data), de->d_name, len+1);
    pcb->root1 = &bv;
    ikptr p = ik_safe_alloc(pcb, pair_size) + pair_tag;
    pcb->root1 = 0;
    ref(p, off_car) = bv;
    ref(p, off_cdr) = ac;
    ac = p;
  }
}

ikptr
ikrt_mkdir(ikptr path, ikptr mode /*, ikpcb* pcb */){
  int r = mkdir((char*)(path+off_bytevector_data), unfix(mode));
  if(r == 0){
    return true_object;
  }
  return ik_errno_to_code();
}

ikptr
ikrt_rmdir(ikptr path /*, ikpcb* pcb */){
  int r = rmdir((char*)(path+off_bytevector_data));
  if(r == 0){
    return true_object;
  }
  return ik_errno_to_code();
}

ikptr
ikrt_chmod(ikptr path, ikptr mode /*, ikpcb* pcb */){
  int r = chmod((char*)(path+off_bytevector_data), (mode_t)unfix(mode));
  if(r == 0){
    return true_object;
  }
  return ik_errno_to_code();
}

ikptr
ikrt_symlink(ikptr to, ikptr path /*, ikpcb* pcb */){
  int r = symlink((char*)(to+off_bytevector_data), (char*)(path+off_bytevector_data));
  if(r == 0){
    return true_object;
  }
  return ik_errno_to_code();
}

ikptr
ikrt_link(ikptr to, ikptr path /*, ikpcb* pcb */){
  int r = link((char*)(to+off_bytevector_data), (char*)(path+off_bytevector_data));
  if(r == 0){
    return true_object;
  }
  return ik_errno_to_code();
}

ikptr
ikrt_realpath(ikptr bv, ikpcb* pcb){
  char buff[PATH_MAX];
  char* p = realpath((char*)(bv+off_bytevector_data), buff);
  if(p == NULL){
    return ik_errno_to_code();
  }
  int n = strlen(p);
  ikptr r = ik_safe_alloc(pcb, align(disp_bytevector_data+n+1));
  ref(r, 0) = fix(n);
  memcpy((char*)(r+disp_bytevector_data), p, n+1);
  return r+bytevector_tag;
}

ikptr 
ik_system(ikptr str){
  if(tagof(str) == bytevector_tag){
    int r = system((char*)(long)(str+off_bytevector_data));
    if(r >= 0) {  
      return fix(r);
    } else {
      return ik_errno_to_code();
    }
  } else {
    fprintf(stderr, "bug in ik_system\n");
    exit(-1);
  }
}

static char*
mtname(unsigned int n){
  if(n == mainheap_type)  { return "HEAP_T"; }
  if(n == mainstack_type) { return "STAK_T"; }
  if(n == pointers_type)  { return "PTER_T"; }
  if(n == dat_type)       { return "DATA_T"; }
  if(n == code_type)      { return "CODE_T"; }
  if(n == hole_type)      { return "      "; }
  return "WHAT_T";
}

ikptr
ik_dump_metatable(ikpcb* pcb){
  unsigned int* s = pcb->segment_vector_base;
  ikptr p = pcb->memory_base;
  ikptr hi = pcb->memory_end;
  while(p < hi){
    unsigned int t = *s & type_mask;
    ikptr start = p;
    p += pagesize;
    s++;
    while((p < hi) && ((*s & type_mask) == t)){
      p += pagesize;
      s++;
    }
    fprintf(stderr, "0x%016lx + %5ld pages = %s\n", 
        (long int) start,
        ((long int)p-(long int)start)/pagesize,
        mtname(t));
  }
  return void_object;
}

ikptr
ik_dump_dirty_vector(ikpcb* pcb){
  unsigned int* s = pcb->dirty_vector_base;
  ikptr p = pcb->memory_base;
  ikptr hi = pcb->memory_end;
  while(p < hi){
    unsigned int t = *s;
    ikptr start = p;
    p += pagesize;
    s++;
    while((p < hi) && (*s == t)){
      p += pagesize;
      s++;
    }
    fprintf(stderr, "0x%016lx + %5ld pages = 0x%08x\n", 
        (long int) start,
        ((long int)p-(long int)start)/pagesize,
        t);
  }
  return void_object;
}

ikptr 
ikrt_make_code(ikptr codesizeptr, ikptr freevars, ikptr rvec, ikpcb* pcb){
  assert((fx_mask & (int)codesizeptr) == 0);
  long int code_size = unfix(codesizeptr);
  long int memreq = align_to_next_page(code_size + disp_code_data);
  ikptr mem = ik_mmap_code(memreq, 0, pcb);
  bzero((char*)(long)mem, memreq);
  ref(mem, 0) = code_tag;
  ref(mem, disp_code_code_size) = codesizeptr;
  ref(mem, disp_code_freevars) = freevars;
  ref(mem, disp_code_reloc_vector) = rvec;
  ref(mem, disp_code_annotation) = false_object;
  ik_relocate_code(mem);
  return mem+vector_tag;
}

ikptr
ikrt_set_code_reloc_vector(ikptr code, ikptr vec, ikpcb* pcb){
  ref(code, off_code_reloc_vector) = vec;
  ik_relocate_code(code-vector_tag);
  ((unsigned int*)(long)pcb->dirty_vector)[page_index(code)] = -1;
  return void_object;
}

ikptr
ikrt_set_code_annotation(ikptr code, ikptr annot, ikpcb* pcb){
  ref(code, off_code_annotation) = annot;
  ((unsigned int*)(long)pcb->dirty_vector)[page_index(code)] = -1;
  return void_object;
}



ikptr
ikrt_bvftime(ikptr outbv, ikptr fmtbv){
  time_t t;
  struct tm* tmp;
  t = time(NULL);
  tmp = localtime(&t);
  if(tmp == NULL){
    fprintf(stderr, "Error in time: %s\n", strerror(errno));
  }
  int rv = 
    strftime((char*)(long)(outbv+off_bytevector_data),
             unfix(ref(outbv, off_bytevector_length)) + 1,
             (char*)(long)(fmtbv+off_bytevector_data),
             tmp);
  if(rv == 0){
    fprintf(stderr, "Error in strftime: %s\n", strerror(errno));
  }
  return fix(rv);
}

ikptr
ikrt_register_guardian_pair(ikptr p0, ikpcb* pcb){
  ik_ptr_page* x = pcb->protected_list[0];
  if((x == NULL) || (x->count == ik_ptr_page_size)){
    assert(sizeof(ik_ptr_page) == pagesize);
    ik_ptr_page* y = (ik_ptr_page*)(long)ik_mmap(pagesize);
    y->count = 0;
    y->next = x;
    pcb->protected_list[0] = y;
    x = y;
  }
  x->ptr[x->count++] = p0;
  return void_object;
}

ikptr 
ikrt_register_guardian(ikptr tc, ikptr obj, ikpcb* pcb){
  ikptr p0 = ik_unsafe_alloc(pcb, pair_size) + pair_tag;
  ref(p0, off_car) = tc;
  ref(p0, off_cdr) = obj;
  return ikrt_register_guardian_pair(p0, pcb);
}

ikptr 
ikrt_stats_now(ikptr t, ikpcb* pcb){
  struct rusage r;
  struct timeval s;

  gettimeofday(&s, 0);
  getrusage(RUSAGE_SELF, &r);
  ref(t, off_record_data)                = fix(r.ru_utime.tv_sec);
  ref(t, off_record_data + wordsize)     = fix(r.ru_utime.tv_usec);
  ref(t, off_record_data + 2 * wordsize) = fix(r.ru_stime.tv_sec);
  ref(t, off_record_data + 3 * wordsize) = fix(r.ru_stime.tv_usec);
  ref(t, off_record_data + 4 * wordsize) = fix(s.tv_sec);
  ref(t, off_record_data + 5 * wordsize) = fix(s.tv_usec);
  ref(t, off_record_data + 6 * wordsize) = fix(pcb->collection_id);
  ref(t, off_record_data + 7 * wordsize) = fix(pcb->collect_utime.tv_sec);
  ref(t, off_record_data + 8 * wordsize) = fix(pcb->collect_utime.tv_usec);
  ref(t, off_record_data + 9 * wordsize) = fix(pcb->collect_stime.tv_sec);
  ref(t, off_record_data + 10 * wordsize) = fix(pcb->collect_stime.tv_usec);
  ref(t, off_record_data + 11 * wordsize) = fix(pcb->collect_rtime.tv_sec);
  ref(t, off_record_data + 12 * wordsize) = fix(pcb->collect_rtime.tv_usec);
  {
    /* minor bytes */
    long int bytes_in_heap = ((long int) pcb->allocation_pointer) -
                             ((long int) pcb->heap_base);
    long int bytes = bytes_in_heap + pcb->allocation_count_minor;
    ref(t, off_record_data + 13 * wordsize) = fix(bytes);
  }
  /* major bytes */
  ref(t, off_record_data + 14 * wordsize) = fix(pcb->allocation_count_major);
  return void_object;
}

ikptr 
ikrt_current_time(ikptr t){
  struct timeval s;
  gettimeofday(&s, 0);
  /* this will break in 8,727,224 years if we stay in 32-bit ptrs */
  ref(t, off_record_data + 0*wordsize) = fix(s.tv_sec / 1000000);
  ref(t, off_record_data + 1*wordsize) = fix(s.tv_sec % 1000000);
  ref(t, off_record_data + 2*wordsize) = fix(s.tv_usec);
  return t;
}

ikptr
ikrt_gmt_offset(ikptr t){
  time_t clock =
    unfix(ref(t, off_record_data + 0*wordsize)) * 1000000 
    + unfix(ref(t, off_record_data + 1*wordsize));
  struct tm* m = gmtime(&clock);
  time_t gmtclock = mktime(m);
  return fix(clock - gmtclock);
  /*
  struct tm* m = localtime(&clock);
  ikptr r = fix(m->tm_gmtoff);
  return r;
  */
}

ikptr 
ikrt_fork(){
  int pid = fork();
  if(pid >= 0){
    return fix(pid);
  } else {
    return ik_errno_to_code();
  }
}



ikptr 
ikrt_getenv(ikptr bv, ikpcb* pcb){
  char* v = getenv((char*)(long)(bv + off_bytevector_data));
  if(v){
    long int n = strlen(v);
    ikptr s = ik_safe_alloc(pcb, align(n+disp_bytevector_data+1))
              + bytevector_tag;
    ref(s, -bytevector_tag) = fix(n);
    memcpy((char*)(long)(s+off_bytevector_data), v, n+1);
    return s;
  } 
  else {
    return false_object;
  }
}

ikptr 
ikrt_make_vector1(ikptr len, ikpcb* pcb){
  int intlen = (int)len;
  if(is_fixnum(len) && (intlen >= 0)){
    ikptr s = ik_safe_alloc(pcb, align(len + disp_vector_data));
    ref(s, 0) = len;
    memset((char*)(long)(s+disp_vector_data), 0, len);
    return s+vector_tag;
  } else {
    return 0;
  }
}

#if 0
ikptr 
ikrt_make_vector2(ikptr len, ikptr obj, ikpcb* pcb){
  if(is_fixnum(len) && ((len >> 31)!=0)){
    pcb->root0 = &obj;
    ikptr s = ik_safe_alloc(pcb, align(((int)len) + disp_vector_data));
    pcb->root0 = 0;
    ref(s, 0) = len;
    memset(s+disp_vector_data, 0, (int)len);
    return s+vector_tag;
  } else {
    return false_object;
  }
}
#endif


ikptr 
ikrt_setenv(ikptr key, ikptr val, ikptr overwrite){
  int err = setenv((char*)(key+off_bytevector_data), 
                   (char*)(val+off_bytevector_data),
                   overwrite!=false_object);
  if(err){
    return false_object;
  } else {
    return true_object;
  }
}

ikptr 
ikrt_unsetenv(ikptr key){
  unsetenv((char*)(key+off_bytevector_data));
  return void_object;
}



ikptr 
ikrt_environ(ikpcb* pcb){
  char** es = environ;
  int i; char* e;
  ikptr ac = null_object;
  pcb->root0 = &ac;
  for(i=0; (e=es[i]); i++){
    long int n = strlen(e);
    ikptr s = ik_safe_alloc(pcb, align(n+disp_bytevector_data+1))
      + bytevector_tag;
    ref(s, -bytevector_tag) = fix(n);
    memcpy((char*)(long)(s+off_bytevector_data), e, n+1);
    pcb->root1 = &s;
    ikptr p = ik_safe_alloc(pcb, pair_size) + pair_tag;
    pcb->root1 = 0;
    ref(p, off_cdr) = ac;
    ref(p, off_car) = s;
    ac = p;
  }
  pcb->root0 = 0;
  return ac;
}

ikptr
ikrt_exit(ikptr status, ikpcb* pcb){
  ik_delete_pcb(pcb);
  assert(total_allocated_pages == 0);
  if(is_fixnum(status)){
    exit(unfix(status));
  } else {
    exit(EXIT_FAILURE);
  }
}

ikptr
ikrt_nanosleep(ikptr secs, ikptr nsecs /*, ikpcb* pcb */){
  struct timespec t;
  t.tv_sec = 
    is_fixnum(secs) 
      ? (unsigned long) unfix(secs) 
      : ref(secs, off_bignum_data);
  t.tv_nsec = 
    is_fixnum(nsecs) 
      ? (unsigned long) unfix(nsecs)
      : ref(nsecs, off_bignum_data);
  return fix(nanosleep(&t, NULL));
}

ikptr
ikrt_chdir(ikptr pathbv /*, ikpcb* pcb */){
  int err = chdir(off_bytevector_data+(char*)pathbv);
  if(err == 0){
    return true_object;
  }
  return ik_errno_to_code();
}

ikptr
ikrt_getcwd(ikpcb* pcb){
  char buff[MAXPATHLEN+1];
  char* path = getcwd(buff, MAXPATHLEN);
  if(! path){
    return ik_errno_to_code();
  }
  int len = strlen(path);
  ikptr bv = ik_safe_alloc(pcb, align(disp_bytevector_data+len+1));
  ref(bv,0) = fix(len);
  memcpy(disp_bytevector_data+(char*)(bv), path, len+1);
  return bv+bytevector_tag;
}



ikptr
ikrt_debug(ikptr x){
  fprintf(stderr, "DEBUG 0x%016lx\n", (long int)x);
  return 0;
}

ikptr
ikrt_access(ikptr filename, ikptr how /*, ikpcb* pcb */){
  char* fn = (char*)(filename + off_bytevector_data);
  int r;
  int ik_how;
  int c_how;

  ik_how = unfix(how);
  if (ik_how == 0) {
    c_how = F_OK;
  } else {
    c_how = 0;
    if (ik_how & 1) c_how |= R_OK;
    if (ik_how & 2) c_how |= W_OK;
    if (ik_how & 4) c_how |= X_OK;
  }
  
  r = access(fn, c_how);
  if (r == 0) {
    return true_object;
  } else if ((errno == EACCES) ||
             (errno == EROFS) ||
             (errno == ETXTBSY)) {
    return false_object;
  } else {
    return ik_errno_to_code();
  }
}

ikptr
ikrt_file_size(ikptr filename, ikpcb* pcb){
  char* fn = (char*)(filename + off_bytevector_data);
  struct stat s;
  int r = stat(fn, &s);
  if (r == 0) {
    if (sizeof(off_t) == sizeof(long)) {
      return u_to_number(s.st_size, pcb);
    } else if (sizeof(off_t) == sizeof(long long)) {
      return ull_to_number(s.st_size, pcb);
    } else {
      fprintf(stderr, "internal error in ikarus: invalid off_t size\n");
      exit(-1);
    }
  } else {
    return ik_errno_to_code();
  }
}

ikptr
ikrt_rename_file(ikptr src, ikptr dst /* ikpcb* pcb */){
  int err = rename((char*)(src + off_bytevector_data),
                   (char*)(dst + off_bytevector_data));
  if (err == 0) {
    return true_object;
  } else {
    return ik_errno_to_code();
  }
}

ikptr 
ikrt_last_errno(ikpcb* pcb){
  return s_to_number(pcb->last_errno, pcb);
}
