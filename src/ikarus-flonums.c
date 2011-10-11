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



#define _ISOC99_SOURCE
#include "ikarus-data.h"
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <math.h>

ikptr
ikrt_fl_round(ikptr x, ikptr y){
  flonum_data(y) = round(flonum_data(x));
  return y;
}

ikptr
ikrt_fl_exp(ikptr x, ikptr y){
  flonum_data(y) = exp(flonum_data(x));
  return y;
}

ikptr
ikrt_flfl_expt(ikptr a, ikptr b, ikptr z){
  flonum_data(z) = exp(flonum_data(b) * log(flonum_data(a)));
  return z;
}

ikptr
ikrt_bytevector_to_flonum(ikptr x, ikpcb* pcb){
  double v = strtod((char*)(long)x+off_bytevector_data, NULL);
  ikptr r = ik_unsafe_alloc(pcb, flonum_size) + vector_tag;
  ref(r, -vector_tag) = (ikptr)flonum_tag;
  flonum_data(r) = v;
  return r;
}

ikptr
ikrt_fl_plus(ikptr x, ikptr y,ikpcb* pcb){
  ikptr r = ik_unsafe_alloc(pcb, flonum_size) + vector_tag;
  ref(r, -vector_tag) = (ikptr)flonum_tag;
  flonum_data(r) = flonum_data(x) + flonum_data(y);
  return r;
}

ikptr
ikrt_fl_minus(ikptr x, ikptr y,ikpcb* pcb){
  ikptr r = ik_unsafe_alloc(pcb, flonum_size) + vector_tag;
  ref(r, -vector_tag) = (ikptr)flonum_tag;
  flonum_data(r) = flonum_data(x) - flonum_data(y);
  return r;
}

ikptr
ikrt_fl_times(ikptr x, ikptr y,ikpcb* pcb){
  ikptr r = ik_unsafe_alloc(pcb, flonum_size) + vector_tag;
  ref(r, -vector_tag) = (ikptr)flonum_tag;
  flonum_data(r) = flonum_data(x) * flonum_data(y);
  return r;
}

ikptr
ikrt_fl_div(ikptr x, ikptr y,ikpcb* pcb){
  ikptr r = ik_unsafe_alloc(pcb, flonum_size) + vector_tag;
  ref(r, -vector_tag) = (ikptr)flonum_tag;
  flonum_data(r) = flonum_data(x) / flonum_data(y);
  return r;
}

ikptr
ikrt_fl_invert(ikptr x, ikpcb* pcb){
  ikptr r = ik_unsafe_alloc(pcb, flonum_size) + vector_tag;
  ref(r, -vector_tag) = (ikptr)flonum_tag;
  flonum_data(r) = 1.0 / flonum_data(x);
  return r;
}

ikptr
ikrt_fl_sin(ikptr x, ikpcb* pcb){
  ikptr r = ik_unsafe_alloc(pcb, flonum_size) + vector_tag;
  ref(r, -vector_tag) = (ikptr)flonum_tag;
  flonum_data(r) = sin(flonum_data(x));
  return r;
}

ikptr
ikrt_fl_cos(ikptr x, ikpcb* pcb){
  ikptr r = ik_unsafe_alloc(pcb, flonum_size) + vector_tag;
  ref(r, -vector_tag) = (ikptr)flonum_tag;
  flonum_data(r) = cos(flonum_data(x));
  return r;
}

ikptr
ikrt_fl_tan(ikptr x, ikpcb* pcb){
  ikptr r = ik_unsafe_alloc(pcb, flonum_size) + vector_tag;
  ref(r, -vector_tag) = (ikptr)flonum_tag;
  flonum_data(r) = tan(flonum_data(x));
  return r;
}

ikptr
ikrt_fl_asin(ikptr x, ikpcb* pcb){
  ikptr r = ik_unsafe_alloc(pcb, flonum_size) + vector_tag;
  ref(r, -vector_tag) = (ikptr)flonum_tag;
  flonum_data(r) = asin(flonum_data(x));
  return r;
}

ikptr
ikrt_fl_acos(ikptr x, ikpcb* pcb){
  ikptr r = ik_unsafe_alloc(pcb, flonum_size) + vector_tag;
  ref(r, -vector_tag) = (ikptr)flonum_tag;
  flonum_data(r) = acos(flonum_data(x));
  return r;
}

ikptr
ikrt_fl_atan(ikptr x, ikpcb* pcb){
  ikptr r = ik_unsafe_alloc(pcb, flonum_size) + vector_tag;
  ref(r, -vector_tag) = (ikptr)flonum_tag;
  flonum_data(r) = atan(flonum_data(x));
  return r;
}

ikptr
ikrt_atan2(ikptr y, ikptr x, ikpcb* pcb){
  ikptr r = ik_unsafe_alloc(pcb, flonum_size) + vector_tag;
  ref(r, -vector_tag) = (ikptr)flonum_tag;
  flonum_data(r) = atan2(flonum_data(y), flonum_data(x));
  return r;
}

ikptr
ikrt_fl_sqrt(ikptr x, ikpcb* pcb){
  ikptr r = ik_unsafe_alloc(pcb, flonum_size) + vector_tag;
  ref(r, -vector_tag) = (ikptr)flonum_tag;
  flonum_data(r) = sqrt(flonum_data(x));
  return r;
}

ikptr
ikrt_fl_log(ikptr x, ikpcb* pcb){
  ikptr r = ik_unsafe_alloc(pcb, flonum_size) + vector_tag;
  ref(r, -vector_tag) = (ikptr)flonum_tag;
  flonum_data(r) = log(flonum_data(x));
  return r;
}

ikptr
ikrt_fx_sin(ikptr x, ikpcb* pcb){
  ikptr r = ik_unsafe_alloc(pcb, flonum_size) + vector_tag;
  ref(r, -vector_tag) = (ikptr)flonum_tag;
  flonum_data(r) = sin(unfix(x));
  return r;
}

ikptr
ikrt_fx_cos(ikptr x, ikpcb* pcb){
  ikptr r = ik_unsafe_alloc(pcb, flonum_size) + vector_tag;
  ref(r, -vector_tag) = (ikptr)flonum_tag;
  flonum_data(r) = cos(unfix(x));
  return r;
}

ikptr
ikrt_fx_tan(ikptr x, ikpcb* pcb){
  ikptr r = ik_unsafe_alloc(pcb, flonum_size) + vector_tag;
  ref(r, -vector_tag) = (ikptr)flonum_tag;
  flonum_data(r) = tan(unfix(x));
  return r;
}

ikptr
ikrt_fx_asin(ikptr x, ikpcb* pcb){
  ikptr r = ik_unsafe_alloc(pcb, flonum_size) + vector_tag;
  ref(r, -vector_tag) = (ikptr)flonum_tag;
  flonum_data(r) = asin(unfix(x));
  return r;
}

ikptr
ikrt_fx_acos(ikptr x, ikpcb* pcb){
  ikptr r = ik_unsafe_alloc(pcb, flonum_size) + vector_tag;
  ref(r, -vector_tag) = (ikptr)flonum_tag;
  flonum_data(r) = acos(unfix(x));
  return r;
}

ikptr
ikrt_fx_atan(ikptr x, ikpcb* pcb){
  ikptr r = ik_unsafe_alloc(pcb, flonum_size) + vector_tag;
  ref(r, -vector_tag) = (ikptr)flonum_tag;
  flonum_data(r) = atan(unfix(x));
  return r;
}

ikptr
ikrt_fl_sinh(ikptr x, ikpcb* pcb){
  ikptr r = ik_unsafe_alloc(pcb, flonum_size) + vector_tag;
  ref(r, -vector_tag) = (ikptr)flonum_tag;
  flonum_data(r) = sinh(flonum_data(x));
  return r;
}

ikptr
ikrt_fl_cosh(ikptr x, ikpcb* pcb){
  ikptr r = ik_unsafe_alloc(pcb, flonum_size) + vector_tag;
  ref(r, -vector_tag) = (ikptr)flonum_tag;
  flonum_data(r) = cosh(flonum_data(x));
  return r;
}

ikptr
ikrt_fl_tanh(ikptr x, ikpcb* pcb){
  ikptr r = ik_unsafe_alloc(pcb, flonum_size) + vector_tag;
  ref(r, -vector_tag) = (ikptr)flonum_tag;
  flonum_data(r) = tanh(flonum_data(x));
  return r;
}

ikptr
ikrt_fl_asinh(ikptr x, ikpcb* pcb){
  ikptr r = ik_unsafe_alloc(pcb, flonum_size) + vector_tag;
  ref(r, -vector_tag) = (ikptr)flonum_tag;
  flonum_data(r) = asinh(flonum_data(x));
  return r;
}

ikptr
ikrt_fl_acosh(ikptr x, ikpcb* pcb){
  ikptr r = ik_unsafe_alloc(pcb, flonum_size) + vector_tag;
  ref(r, -vector_tag) = (ikptr)flonum_tag;
  flonum_data(r) = acosh(flonum_data(x));
  return r;
}

ikptr
ikrt_fl_atanh(ikptr x, ikpcb* pcb){
  ikptr r = ik_unsafe_alloc(pcb, flonum_size) + vector_tag;
  ref(r, -vector_tag) = (ikptr)flonum_tag;
  flonum_data(r) = atanh(flonum_data(x));
  return r;
}



ikptr
ikrt_fx_sqrt(ikptr x, ikpcb* pcb){
  ikptr r = ik_unsafe_alloc(pcb, flonum_size) + vector_tag;
  ref(r, -vector_tag) = (ikptr)flonum_tag;
  flonum_data(r) = sqrt(unfix(x));
  return r;
}

ikptr
ikrt_fx_log(ikptr x, ikpcb* pcb){
  ikptr r = ik_unsafe_alloc(pcb, flonum_size) + vector_tag;
  ref(r, -vector_tag) = (ikptr)flonum_tag;
  flonum_data(r) = log(unfix(x));
  return r;
}

ikptr
ikrt_fixnum_to_flonum(ikptr x, ikptr r, ikpcb* pcb){
  flonum_data(r) = unfix(x);
  return r;
}

ikptr
ikrt_fl_equal(ikptr x, ikptr y){
  if(flonum_data(x) == flonum_data(y)){
    return true_object;
  } else {
    return false_object;
  }
}

ikptr
ikrt_fl_less_or_equal(ikptr x, ikptr y){
  if(flonum_data(x) <= flonum_data(y)){
    return true_object;
  } else {
    return false_object;
  }
}

ikptr
ikrt_fl_less(ikptr x, ikptr y){
  if(flonum_data(x) < flonum_data(y)){
    return true_object;
  } else {
    return false_object;
  }
}
