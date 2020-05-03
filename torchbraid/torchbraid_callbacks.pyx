# cython: profile=True
# cython: linetrace=True

import torch
import numpy as np
cimport numpy as np

from cpython.mem cimport PyMem_Malloc, PyMem_Realloc, PyMem_Free
from cpython.ref cimport PyObject, Py_INCREF, Py_DECREF
from cython cimport view

##
# Define your Python Braid Vector as a C-struct

cdef int my_access(braid_App app,braid_Vector u,braid_AccessStatus status):
  pyApp = <object> app

  cdef double t

  with pyApp.timer("my_access"):
    # Create Numpy wrapper around u.v
    ten_u = <object> u

    braid_AccessStatusGetT(status, &t)

    pyApp.access(t,ten_u)
  return 0

cdef int my_step(braid_App app, braid_Vector ustop, braid_Vector fstop, braid_Vector vec_u, braid_StepStatus status):
  pyApp = <object> app

  cdef double tstart
  cdef double tstop
  cdef int level

  with pyApp.timer("my_step"):

    tstart = 0.0
    tstop = 5.0
    level = -1
    braid_StepStatusGetTstartTstop(status, &tstart, &tstop)
    braid_StepStatusGetLevel(status, &level)

    u =  <object> vec_u
    temp = pyApp.eval(u,tstart,tstop,level)

    u.tensor().copy_(temp.tensor())

  return 0
# end my_access

cdef int my_init(braid_App app, double t, braid_Vector *u_ptr):
  pyApp = <object> app
  with pyApp.timer("my_init"):
    u_mem = pyApp.buildInit(t)
    Py_INCREF(u_mem) # why do we need this?
    u_ptr[0] = <braid_Vector> u_mem

  return 0

cdef int my_free(braid_App app, braid_Vector u):
  pyApp = <object> app
  with pyApp.timer("my_free"):

    # Cast u as a PyBraid_Vector
    pyU = <object> u
    # Decrement the smart pointer
    Py_DECREF(pyU) 
    del pyU
  return 0

cdef int my_sum(braid_App app, double alpha, braid_Vector x, double beta, braid_Vector y):
  # This routine cna be made faster by using the pyTorch tensor operations
  # My initial attempt at this failed however

  pyApp = <object>app

  cdef np.ndarray[float,ndim=1] np_X
  cdef np.ndarray[float,ndim=1] np_Y
  cdef int sz

  with pyApp.timer("my_sum"):
    # Cast x and y as a PyBraid_Vector
    np_X = (<object> x).tensor().numpy().ravel()
    np_Y = (<object> y).tensor().numpy().ravel()
    sz = len(np_X)

    # in place copy 
    for k in range(sz):
      np_Y[k] = alpha*np_X[k]+beta*np_Y[k]

  return 0

cdef int my_clone(braid_App app, braid_Vector u, braid_Vector *v_ptr):
  pyApp = <object> app
  with pyApp.timer("my_clone"):
    ten_U = <object> u 
    v_mem = ten_U.clone()
    Py_INCREF(v_mem) # why do we need this?
    v_ptr[0] = <braid_Vector> v_mem

  return 0

cdef int my_norm(braid_App app, braid_Vector u, double *norm_ptr):
  pyApp = <object> app
  with pyApp.timer("my_norm"):
    # Compute norm 
    ten_U = (<object> u).tensor()
    norm_ptr[0] = torch.norm(ten_U)

  return 0

cdef int my_bufsize(braid_App app, int *size_ptr, braid_BufferStatus status):
  pyApp = <object> app
  cdef int cnt 
  with pyApp.timer("my_bufsize"):
    cnt = pyApp.x0.tensor().size().numel()

    # Note size_ptr is an integer array of size 1, and we index in at location [0]
    # the int size encodes the level
    size_ptr[0] = sizeof(float)*cnt + sizeof(float) + sizeof(int)
                   # vector                 time             level

  return 0

cdef int my_bufpack(braid_App app, braid_Vector u, void *buffer,braid_BufferStatus status):

  # Convert void * to a double array (note fbuffer is a C-array, so no bounds checking is done) 
  cdef int * ibuffer = <int *> buffer
  cdef float * fbuffer = <float *>(buffer+sizeof(int))
  cdef np.ndarray[float,ndim=1] np_U
  cdef int sz
  cdef view.array my_buf 

  pyApp = <object>app
  with pyApp.timer("my_bufpack"):
    # Cast u as a PyBraid_Vector
    ten_U = (<object> u).tensor()
    np_U  = ten_U.numpy().ravel() # ravel provides a flatten accessor to the array

    ibuffer[0] = (<object> u).level()
    fbuffer[0] = (<object> u).getTime()

    sz = len(np_U)
    my_buf = <float[:sz]> (fbuffer+1)

    my_buf[:] = np_U

  return 0

cdef int my_bufunpack(braid_App app, void *buffer, braid_Vector *u_ptr,braid_BufferStatus status):
  pyApp = <object>app

  cdef int * ibuffer = <int *> buffer
  cdef float * fbuffer = <float *>(buffer+sizeof(int))
  cdef np.ndarray[float,ndim=1] np_U
  cdef int sz
  cdef view.array my_buf 

  with pyApp.timer("my_bufunpack"):
  
    # allocate memory
    u_obj = pyApp.x0.clone()
    Py_INCREF(u_obj) # why do we need this?
    u_ptr[0] = <braid_Vector> u_obj 
  
    u_obj.level_ = ibuffer[0]
    u_obj.setTime(fbuffer[0])

    ten_U = u_obj.tensor()
    np_U = ten_U.numpy().ravel() # ravel provides a flatten accessor to the array
  
    # this is almost certainly slow
    sz = len(np_U)
    my_buf = <float[:sz]> (fbuffer+1)
    np_U[:] = my_buf

  return 0
