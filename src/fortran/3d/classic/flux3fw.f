c
c
c     ==================================================================
      subroutine flux3(ixyz,maxm,meqn,mwaves,mbc,mx,
     &                 q1d,dtdx1d,dtdy,dtdz,aux1,aux2,aux3,maux,
     &                 method,mthlim,qadd,fadd,gadd,hadd,cfl1d,
     &                 fwave,s,amdq,apdq,cqxx,
     &                 bmamdq,bmapdq,bpamdq,bpapdq,
     &                 cmamdq,cmapdq,cpamdq,cpapdq,
     &                 cmamdq2,cmapdq2,cpamdq2,cpapdq2,
     &                 bmcqxxp,bpcqxxp,bmcqxxm,bpcqxxm,
     &                 cmcqxxp,cpcqxxp,cmcqxxm,cpcqxxm,
     &                 bmcmamdq,bmcmapdq,bpcmamdq,bpcmapdq,
     &                 bmcpamdq,bmcpapdq,bpcpamdq,bpcpapdq,
     &                 rpn3,rpt3,rptt3)
c     ==================================================================
c
----------------------------------------------------------------------
c     # flux3fw is a modified version of flux3 to use fwave instead of wave.
c     # A modified Riemann solver rp3n must be used in conjunction with this
c     # routine, which returns fwave's instead of wave's.
c     # See http://amath.washington.edu/~claw/fwave.html
c
c     # Limiters are applied to the fwave's, and the only significant
c     # modification of this code is in the loop for the
c     # second order corrections.
c
----------------------------------------------------------------------
c
c
c     # Compute the modification to fluxes f, g and h that are generated by
c     # all interfaces along a 1D slice of the 3D grid.
c     #    ixyz = 1  if it is a slice in x
c     #           2  if it is a slice in y
c     #           3  if it is a slice in z
c     # This value is passed into the Riemann solvers. The flux modifications
c     # go into the arrays fadd, gadd and hadd.  The notation is written
c     # assuming we are solving along a 1D slice in the x-direction.
c
c     # fadd(i,.) modifies F to the left of cell i
c     # gadd(i,.,1,slice) modifies G below cell i (in the z-direction)
c     # gadd(i,.,2,slice) modifies G above cell i
c     #                   The G flux in the surrounding slices may
c     #                   also be updated.
c     #                   slice  =  -1     The slice below in y-direction
c     #                   slice  =   0     The slice used in the 2D method
c     #                   slice  =   1     The slice above in y-direction
c     # hadd(i,.,1,slice) modifies H below cell i (in the y-direction)
c     # hadd(i,.,2,slice) modifies H above cell i
c     #                   The H flux in the surrounding slices may
c     #                   also be updated.
c     #                   slice  =  -1     The slice below in z-direction
c     #                   slice  =   0     The slice used in the 2D method
c     #                   slice  =   1     The slice above in z-direction
c     #
c     # The method used is specified by method(2) and method(3):
c
c        method(2) = 1 No correction waves
c                  = 2 if second order correction terms are to be added, with
c                      a flux limiter as specified by mthlim.  No transverse
c                      propagation of these waves.
c
c         method(3) specify how the transverse wave propagation
c         of the increment wave and the correction wave are performed.
c         Note that method(3) is given by a two digit number, in
c         contrast to what is the case for claw2. It is convenient
c         to define the scheme using the pair (method(2),method(3)).
c
c         method(3) <  0 Gives dimensional splitting using Godunov
c                        splitting, i.e. formally first order
c                        accurate.
c                      0 Gives the Donor cell method. No transverse
c                        propagation of neither the increment wave
c                        nor the correction wave.
c                   = 10 Transverse propagation of the increment wave
c                        as in 2D. Note that method (2,10) is
c                        unconditionally unstable.
c                   = 11 Corner transport upwind of the increment
c                        wave. Note that method (2,11) also is
c                        unconditionally unstable.
c                   = 20 Both the increment wave and the correction
c                        wave propagate as in the 2D case. Only to
c                        be used with method(2) = 2.
c                   = 21 Corner transport upwind of the increment wave,
c                        and the correction wave propagates as in 2D.
c                        Only to be used with method(2) = 2.
c                   = 22 3D propagation of both the increment wave and
c                        the correction wave. Only to be used with
c                        method(2) = 2.
c
c         Recommended settings:   First order schemes:
c                                       (1,10) Stable for CFL < 1/2
c                                       (1,11) Stable for CFL < 1
c                                 Second order schemes:
c                                        (2,20) Stable for CFL < 1/2
c                                        (2,22) Stable for CFL < 1
c
c         WARNING! The schemes (2,10), (2,11) are unconditionally
c                  unstable.
c
c                       ----------------------------------
c
c     Note that if method(6)=1 then the capa array comes into the second
c     order correction terms, and is already included in dtdx1d:
c     If ixyz = 1 then
c        dtdx1d(i) = dt/dx                      if method(6) = 0
c                  = dt/(dx*capa(i,jcom,kcom))  if method(6) = 1
c     If ixyz = 2 then
c        dtdx1d(j) = dt/dy                      if method(6) = 0
c                  = dt/(dy*capa(icom,j,kcom))  if method(6) = 1
c     If ixyz = 3 then
c        dtdx1d(k) = dt/dz                      if method(6) = 0
c                  = dt/(dz*capa(icom,jcom,k))  if method(6) = 1
c
c     Notation:
c        The jump in q (q1d(i,:)-q1d(i-1,:))  is split by rpn3 into
c            amdq =  the left-going flux difference  A^- Delta q
c            apdq = the right-going flux difference  A^+ Delta q
c        Each of these is split by rpt3 into
c            bmasdq = the down-going transverse flux difference B^- A^* Delta q
c            bpasdq =   the up-going transverse flux difference B^+ A^* Delta q
c        where A^* represents either A^- or A^+.
c
c
      implicit real*8(a-h,o-z)
      external rpn3,rpt3, rptt3
      dimension     q1d(meqn,1-mbc:maxm+mbc)
      dimension    amdq(meqn,1-mbc:maxm+mbc)
      dimension    apdq(meqn,1-mbc:maxm+mbc)
      dimension  bmamdq(meqn,1-mbc:maxm+mbc)
      dimension  bmapdq(meqn,1-mbc:maxm+mbc)
      dimension  bpamdq(meqn,1-mbc:maxm+mbc)
      dimension  bpapdq(meqn,1-mbc:maxm+mbc)
      dimension   cqxx(meqn,1-mbc:maxm+mbc)
      dimension   qadd(meqn,1-mbc:maxm+mbc)
      dimension   fadd(meqn,1-mbc:maxm+mbc)
      dimension   gadd(meqn,2,-1:1,1-mbc:maxm+mbc)
      dimension   hadd(meqn,2,-1:1,1-mbc:maxm+mbc)
c
      dimension  cmamdq(meqn,1-mbc:maxm+mbc)
      dimension  cmapdq(meqn,1-mbc:maxm+mbc)
      dimension  cpamdq(meqn,1-mbc:maxm+mbc)
      dimension  cpapdq(meqn,1-mbc:maxm+mbc)
c
      dimension  cmamdq2(meqn,1-mbc:maxm+mbc)
      dimension  cmapdq2(meqn,1-mbc:maxm+mbc)
      dimension  cpamdq2(meqn,1-mbc:maxm+mbc)
      dimension  cpapdq2(meqn,1-mbc:maxm+mbc)
c
      dimension  bmcqxxm(meqn,1-mbc:maxm+mbc)
      dimension  bpcqxxm(meqn,1-mbc:maxm+mbc)
      dimension  cmcqxxm(meqn,1-mbc:maxm+mbc)
      dimension  cpcqxxm(meqn,1-mbc:maxm+mbc)
c
      dimension  bmcqxxp(meqn,1-mbc:maxm+mbc)
      dimension  bpcqxxp(meqn,1-mbc:maxm+mbc)
      dimension  cmcqxxp(meqn,1-mbc:maxm+mbc)
      dimension  cpcqxxp(meqn,1-mbc:maxm+mbc)
c
      dimension  bpcmamdq(meqn,1-mbc:maxm+mbc)
      dimension  bpcmapdq(meqn,1-mbc:maxm+mbc)
      dimension  bpcpamdq(meqn,1-mbc:maxm+mbc)
      dimension  bpcpapdq(meqn,1-mbc:maxm+mbc)
      dimension  bmcmamdq(meqn,1-mbc:maxm+mbc)
      dimension  bmcmapdq(meqn,1-mbc:maxm+mbc)
      dimension  bmcpamdq(meqn,1-mbc:maxm+mbc)
      dimension  bmcpapdq(meqn,1-mbc:maxm+mbc)
c
      dimension dtdx1d(1-mbc:maxm+mbc)
      dimension aux1(maux,1-mbc:maxm+mbc,3)
      dimension aux2(maux,1-mbc:maxm+mbc,3)
      dimension aux3(maux,1-mbc:maxm+mbc,3)
c
      dimension    s(mwaves,1-mbc:maxm+mbc)
      dimension  fwave(meqn,mwaves,1-mbc:maxm+mbc)
c
      dimension method(7),mthlim(mwaves)
      logical limit
      common/comxyt/dtcom,dxcom,dycom,dzcom,tcom,icom,jcom,kcom


      limit = .false.
      do 5 mw=1,mwaves
         if (mthlim(mw) .gt. 0) limit = .true.
   5     continue
c
c     # initialize flux increments:
c     -----------------------------
c
      forall (m = 1:meqn, i = 1-mbc:mx+mbc)
          qadd(m,i) = 0.d0
          fadd(m,i) = 0.d0
      end forall
      forall (m = 1:meqn, i = 1-mbc:mx+mbc, j = -1:1, k = 1:2)
          gadd(m, k, j, i) = 0.d0
          hadd(m, k, j, i) = 0.d0
      end forall
c
c     # local method parameters
      if (method(3) .lt. 0) then
c        # dimensional splitting
         m3 = -1
         m4 = 0
      else
c        # unsplit method
         m3 = method(3)/10
         m4 = method(3) - 10*m3
      endif
c
c     -----------------------------------------------------------
c     # solve normal Riemann problem and compute Godunov updates
c     -----------------------------------------------------------
c
c     # aux2(1-mbc,1,2) is the start of a 1d array now used by rpn3
c
      call rpn3(ixyz,maxm,meqn,mwaves,mbc,mx,q1d,q1d,
     &      aux2(1,1-mbc,2),aux2(1,1-mbc,2),
     &          maux,fwave,s,amdq,apdq)

c
c     # Set qadd for the donor-cell upwind method (Godunov)
      forall (m = 1:meqn, i = 1:mx+1)
            qadd(m,i) = qadd(m,i) - dtdx1d(i)*apdq(m,i)
            qadd(m,i-1) = qadd(m,i-1) - dtdx1d(i-1)*amdq(m,i)
      end forall
c
c     # compute maximum wave speed for checking Courant number:
      cfl1d = 0.d0
      do i=1,mx+1
         do mw=1,mwaves
c          # if s>0 use dtdx1d(i) to compute CFL,
c          # if s<0 use dtdx1d(i-1) to compute CFL:
            cfl1d = dmax1(cfl1d, dtdx1d(i)*s(mw,i),
     &                          -dtdx1d(i-1)*s(mw,i))
         end do
      end do
c
      if (method(2).eq.1) go to 130
c
c     -----------------------------------------------------------
c     # modify F fluxes for second order q_{xx} correction terms:
c     #   F fluxes are in normal, or x-like, direction
c     -----------------------------------------------------------
c
c     # apply limiter to waves:
      if (limit) call limiter(maxm,meqn,mwaves,mbc,mx,fwave,s,mthlim)
c
      do 120 i = 2-mbc,mx+mbc
c
c        # For correction terms below, need average of dtdx in cell
c        # i-1 and i.  Compute these and overwrite dtdx1d:
c
         dtdxave = 0.5d0 * (dtdx1d(i-1) + dtdx1d(i))
c
         forall (m = 1:meqn)
             cqxx(m,i) = 0.d0
         end forall
         do mw = 1,mwaves
            do m = 1,meqn
               cqxx(m,i) = cqxx(m,i) + 0.5d0 * dsign(s(mw,i))
     &             * (1.d0 - dabs(s(mw,i))*dtdxave) * fwave(m,mw,i)
            end do
         end do
         do m = 1,meqn
            fadd(m,i) = fadd(m,i) + cqxx(m,i)
         end do
c
  130 continue
c
      if (m3 .le. 0) return !! no transverse propagation
c
c     --------------------------------------------
c     # TRANSVERSE PROPAGATION
c     --------------------------------------------
c
c     # split the left-going flux difference into down-going and up-going
c     # flux differences (in the y-direction).
c
      call rpt3(ixyz,2,maxm,meqn,mwaves,mbc,mx,q1d,q1d,aux1,aux2,
     &          aux3,maux,1,amdq,bmamdq,bpamdq)
c
c     # split the right-going flux difference into down-going and up-going
c     # flux differences (in the y-direction).
c
      call rpt3(ixyz,2,maxm,meqn,mwaves,mbc,mx,q1d,q1d,aux1,aux2,
     &          aux3,maux,2,apdq,bmapdq,bpapdq)
c
c     # split the left-going flux difference into down-going and up-going
c     # flux differences (in the z-direction).
c
      call rpt3(ixyz,3,maxm,meqn,mwaves,mbc,mx,q1d,q1d,aux1,aux2,
     &          aux3,maux,1,amdq,cmamdq,cpamdq)
c
c     # split the right-going flux difference into down-going and up-going
c     # flux differences (in the y-direction).
c
      call rpt3(ixyz,3,maxm,meqn,mwaves,mbc,mx,q1d,q1d,aux1,aux2,
     &          aux3,maux,2,apdq,cmapdq,cpapdq)
c
c     # Split the correction wave into transverse propagating waves
c     # in the y-direction and z-direction.
c
      if (m3.eq.2) then
         if (maux > 0) then
c            # The corrections cqxx affect both cell i-1 to left and cell i
c            # to right of interface.  Transverse splitting will affect
c            # fluxes on both sides.
c            # If there are aux arrays, then we must split cqxx twice in
c            # each transverse direction, once with imp=1 and once with imp=2:

c            # imp = 1 or 2 is used to indicate whether we are propagating
c            # amdq or apdq, i.e. cqxxm or cqxxp

c            # in the y-like direction with imp=1
              call rpt3(ixyz,2,maxm,meqn,mwaves,mbc,mx,q1d,q1d,
     &            aux1,aux2,aux3,maux,1,cqxx,bmcqxxm,bpcqxxm)

c            # in the y-like direction with imp=2
              call rpt3(ixyz,2,maxm,meqn,mwaves,mbc,mx,q1d,q1d,
     &            aux1,aux2,aux3,maux,2,cqxx,bmcqxxp,bpcqxxp)

c            # in the z-like direction with imp=1
              call rpt3(ixyz,3,maxm,meqn,mwaves,mbc,mx,q1d,q1d,
     &            aux1,aux2, aux3,maux,1,cqxx,cmcqxxm,cpcqxxm)

c            # in the z-like direction with imp=2
             call rpt3(ixyz,3,maxm,meqn,mwaves,mbc,mx,q1d,q1d,
     &            aux1,aux2,aux3,maux,2,cqxx,cmcqxxp,cpcqxxp)
           else
c            # aux arrays aren't being used, so we only need to split
c            # cqxx once in each transverse direction and the same result can
c            # presumably be used to left and right.  
c            # Set imp = 0 since this shouldn't be needed in rpt3 in this case.

c            # in the y-like direction 
              call rpt3(ixyz,2,maxm,meqn,mwaves,mbc,mx,q1d,q1d,
     &              aux1,aux2,aux3,maux,0,cqxx,bmcqxxm,bpcqxxm)

c            # in the z-like direction 
              call rpt3(ixyz,3,maxm,meqn,mwaves,mbc,mx,q1d,q1d,
     &              aux1,aux2,aux3,maux,0,cqxx,cmcqxxm,cpcqxxm)

c             # use the same splitting to left and right:
              forall (m = 1:meqn, i = 0:mx+2)
                  bmcqxxp(m,i) = bmcqxxm(m,i)
                  bpcqxxp(m,i) = bpcqxxm(m,i)
                  cmcqxxp(m,i) = cmcqxxm(m,i)
                  cpcqxxp(m,i) = cpcqxxm(m,i)
              end forall
           endif
        endif
c
c      --------------------------------------------
c      # modify G fluxes in the y-like direction
c      --------------------------------------------
c
c     # If the correction wave also propagates in a 3D sense, incorporate
c     # cpcqxx,... into cmamdq, cpamdq, ... so that it is split also.
c
      if(m4 .eq. 1)then
         forall (m = 1:meqn, i = 0:mx+2)
             cpapdq2(m,i) = cpapdq(m,i)
             cpamdq2(m,i) = cpamdq(m,i)
             cmapdq2(m,i) = cmapdq(m,i)
             cmamdq2(m,i) = cmamdq(m,i)
         end forall
      else if(m4 .eq. 2)then
         forall (m = 1:meqn, i = 0:mx+2)
             cpapdq2(m,i) = cpapdq(m,i) - 3.d0*cpcqxxp(m,i)
             cpamdq2(m,i) = cpamdq(m,i) + 3.d0*cpcqxxm(m,i)
             cmapdq2(m,i) = cmapdq(m,i) - 3.d0*cmcqxxp(m,i)
             cmamdq2(m,i) = cmamdq(m,i) + 3.d0*cmcqxxm(m,i)
         end forall
      endif
c
c     # The transverse flux differences in the z-direction are split
c     # into waves propagating in the y-direction. If m4 = 2,
c     # then the transverse propagating correction waves in the z-direction
c     # are also split. This yields terms of the form BCAu_{xzy} and
c     # BCAAu_{xxzy}.
c
      if( m4.gt.0 )then
          call rptt3(ixyz,2,maxm,meqn,mwaves,mbc,mx,q1d,q1d,aux1,aux2,
     &              aux3,maux,2,2,cpapdq2,bmcpapdq,bpcpapdq)
          call rptt3(ixyz,2,maxm,meqn,mwaves,mbc,mx,q1d,q1d,aux1,aux2,
     &              aux3,maux,1,2,cpamdq2,bmcpamdq,bpcpamdq)
          call rptt3(ixyz,2,maxm,meqn,mwaves,mbc,mx,q1d,q1d,aux1,aux2,
     &              aux3,maux,2,1,cmapdq2,bmcmapdq,bpcmapdq)
          call rptt3(ixyz,2,maxm,meqn,mwaves,mbc,mx,q1d,q1d,aux1,aux2,
     &              aux3,maux,1,1,cmamdq2,bmcmamdq,bpcmamdq)
      endif
c
c     -----------------------------
c     # The updates for G fluxes :
c     -----------------------------
c
      do 180 i = 1, mx+1
         do 180 m=1,meqn
c
c           # Transverse propagation of the increment waves
c           # between cells sharing interfaces, i.e. the 2D approach.
c           # Yields BAu_{xy}.
c
            gadd(m,1,0,i-1) = gadd(m,1,0,i-1)
     &                      - 0.5d0*dtdx1d(i-1)*bmamdq(m,i)
            gadd(m,2,0,i-1) = gadd(m,2,0,i-1)
     &                      - 0.5d0*dtdx1d(i-1)*bpamdq(m,i)
            gadd(m,1,0,i)   = gadd(m,1,0,i)
     &                      - 0.5d0*dtdx1d(i)*bmapdq(m,i)
            gadd(m,2,0,i)   = gadd(m,2,0,i)
     &                      - 0.5d0*dtdx1d(i)*bpapdq(m,i)
c
c           # Transverse propagation of the increment wave (and the
c           # correction wave if m4=2) between cells
c           # only having a corner or edge in common. Yields terms of the
c           # BCAu_{xzy} and BCAAu_{xxzy}.
c
            if( m4.gt.0 )then
c

                gadd(m,2,0,i) = gadd(m,2,0,i)
     &                  + (1.d0/6.d0)*dtdx1d(i)*dtdz
     &                  * (bpcpapdq(m,i) - bpcmapdq(m,i))
                gadd(m,1,0,i) = gadd(m,1,0,i)
     &                  + (1.d0/6.d0)*dtdx1d(i)*dtdz
     &                  * (bmcpapdq(m,i) - bmcmapdq(m,i))


                gadd(m,2,1,i) = gadd(m,2,1,i)
     &                          - (1.d0/6.d0)*dtdx1d(i)*dtdz
     &                          * bpcpapdq(m,i)
                gadd(m,1,1,i) = gadd(m,1,1,i)
     &                          - (1.d0/6.d0)*dtdx1d(i)*dtdz
     &                          * bmcpapdq(m,i)
                gadd(m,2,-1,i) = gadd(m,2,-1,i)
     &                          + (1.d0/6.d0)*dtdx1d(i)*dtdz
     &                          * bpcmapdq(m,i)
                gadd(m,1,-1,i) = gadd(m,1,-1,i)
     &                          + (1.d0/6.d0)*dtdx1d(i)*dtdz
     &                          * bmcmapdq(m,i)
c
                gadd(m,2,0,i-1) = gadd(m,2,0,i-1)
     &                   + (1.d0/6.d0)*dtdx1d(i-1)*dtdz
     &                   * (bpcpamdq(m,i) - bpcmamdq(m,i))
                gadd(m,1,0,i-1) = gadd(m,1,0,i-1)
     &                   + (1.d0/6.d0)*dtdx1d(i-1)*dtdz
     &                   * (bmcpamdq(m,i) - bmcmamdq(m,i))


                gadd(m,2,1,i-1) = gadd(m,2,1,i-1)
     &                          - (1.d0/6.d0)*dtdx1d(i-1)*dtdz
     &                          * bpcpamdq(m,i)
                gadd(m,1,1,i-1) = gadd(m,1,1,i-1)
     &                          - (1.d0/6.d0)*dtdx1d(i-1)*dtdz
     &                          * bmcpamdq(m,i)
                gadd(m,2,-1,i-1) = gadd(m,2,-1,i-1)
     &                          + (1.d0/6.d0)*dtdx1d(i-1)*dtdz
     &                          * bpcmamdq(m,i)
                gadd(m,1,-1,i-1) = gadd(m,1,-1,i-1)
     &                          + (1.d0/6.d0)*dtdx1d(i-1)*dtdz
     &                          * bmcmamdq(m,i)
c
            endif
c
c           # Transverse propagation of the correction wave between
c           # cells sharing faces. This gives BAAu_{xxy}.
c
            if(m3.lt.2) go to 180
               gadd(m,2,0,i)   = gadd(m,2,0,i)
     &                         + dtdx1d(i)*bpcqxxp(m,i)
               gadd(m,1,0,i)   = gadd(m,1,0,i)
     &                         + dtdx1d(i)*bmcqxxp(m,i)
               gadd(m,2,0,i-1) = gadd(m,2,0,i-1)
     &                         - dtdx1d(i-1)*bpcqxxm(m,i)
               gadd(m,1,0,i-1) = gadd(m,1,0,i-1)
     &                         - dtdx1d(i-1)*bmcqxxm(m,i)
c
  180       continue
c
c
c      --------------------------------------------
c      # modify H fluxes in the z-like direction
c      --------------------------------------------
c
c     # If the correction wave also propagates in a 3D sense, incorporate
c     # cqxx into bmamdq, bpamdq, ... so that is is split also.
c
      if(m4 .eq. 2)then
         forall (m = 1:meqn, i = 0:mx+2)
             bpapdq(m,i) = bpapdq(m,i) - 3.d0*bpcqxxp(m,i)
             bpamdq(m,i) = bpamdq(m,i) + 3.d0*bpcqxxm(m,i)
             bmapdq(m,i) = bmapdq(m,i) - 3.d0*bmcqxxp(m,i)
             bmamdq(m,i) = bmamdq(m,i) + 3.d0*bmcqxxm(m,i)
         end forall
      endif
c
c     # The transverse flux differences in the y-direction are split
c     # into waves propagating in the z-direction. If m4 = 2,
c     # then the transverse propagating correction waves in the y-direction
c     # are also split. This yields terms of the form BCAu_{xzy} and
c     # BCAAu_{xxzy}.
c
c     # note that the output to rptt3 below should logically be named
c     # cmbsasdq and cpbsasdq rather than bmcsasdq and bpcsasdq, but
c     # we are re-using the previous storage rather than requiring new arrays.
c
      if( m4.gt.0 )then
          call rptt3(ixyz,3,maxm,meqn,mwaves,mbc,mx,q1d,q1d,aux1,aux2,
     &              aux3,maux,2,2,bpapdq,bmcpapdq,bpcpapdq)
          call rptt3(ixyz,3,maxm,meqn,mwaves,mbc,mx,q1d,q1d,aux1,aux2,
     &              aux3,maux,1,2,bpamdq,bmcpamdq,bpcpamdq)
          call rptt3(ixyz,3,maxm,meqn,mwaves,mbc,mx,q1d,q1d,aux1,aux2,
     &              aux3,maux,2,1,bmapdq,bmcmapdq,bpcmapdq)
          call rptt3(ixyz,3,maxm,meqn,mwaves,mbc,mx,q1d,q1d,aux1,aux2,
     &              aux3,maux,1,1,bmamdq,bmcmamdq,bpcmamdq)
      endif
c
c     -----------------------------
c     # The updates for H fluxes :
c     -----------------------------
c
      do 200 i = 1, mx+1
         do 200 m=1,meqn
c
c           # Transverse propagation of the increment waves
c           # between cells sharing interfaces, i.e. the 2D approach.
c           # Yields CAu_{xy}.
c
            hadd(m,1,0,i-1) = hadd(m,1,0,i-1)
     &                      - 0.5d0*dtdx1d(i-1)*cmamdq(m,i)
            hadd(m,2,0,i-1) = hadd(m,2,0,i-1)
     &                      - 0.5d0*dtdx1d(i-1)*cpamdq(m,i)
            hadd(m,1,0,i)   = hadd(m,1,0,i)
     &                      - 0.5d0*dtdx1d(i)*cmapdq(m,i)
            hadd(m,2,0,i)   = hadd(m,2,0,i)
     &                      - 0.5d0*dtdx1d(i)*cpapdq(m,i)
c
c           # Transverse propagation of the increment wave (and the
c           # correction wave if m4=2) between cells
c           # only having a corner or edge in common. Yields terms of the
c           # CBAu_{xzy} and CBAAu_{xxzy}.
c
            if( m4.gt.0 )then
c
                hadd(m,2,0,i)  = hadd(m,2,0,i)
     &                  + (1.d0/6.d0)*dtdx1d(i)*dtdy
     &                  * (bpcpapdq(m,i) - bpcmapdq(m,i))
                hadd(m,1,0,i)  = hadd(m,1,0,i)
     &                  + (1.d0/6.d0)*dtdx1d(i)*dtdy
     &                  * (bmcpapdq(m,i) - bmcmapdq(m,i))


                hadd(m,2,1,i)  = hadd(m,2,1,i)
     &                         - (1.d0/6.d0)*dtdx1d(i)*dtdy
     &                         * bpcpapdq(m,i)
                hadd(m,1,1,i)  = hadd(m,1,1,i)
     &                         - (1.d0/6.d0)*dtdx1d(i)*dtdy
     &                         * bmcpapdq(m,i)
                hadd(m,2,-1,i) = hadd(m,2,-1,i)
     &                         + (1.d0/6.d0)*dtdx1d(i)*dtdy
     &                         * bpcmapdq(m,i)
                hadd(m,1,-1,i) = hadd(m,1,-1,i)
     &                         + (1.d0/6.d0)*dtdx1d(i)*dtdy
     &                         * bmcmapdq(m,i)
c
                hadd(m,2,0,i-1)  = hadd(m,2,0,i-1)
     &                   + (1.d0/6.d0)*dtdx1d(i-1)*dtdy
     &                   * (bpcpamdq(m,i) - bpcmamdq(m,i))
                hadd(m,1,0,i-1)  = hadd(m,1,0,i-1)
     &                   + (1.d0/6.d0)*dtdx1d(i-1)*dtdy
     &                   * (bmcpamdq(m,i) - bmcmamdq(m,i))


                hadd(m,2,1,i-1)  = hadd(m,2,1,i-1)
     &                           - (1.d0/6.d0)*dtdx1d(i-1)*dtdy
     &                           * bpcpamdq(m,i)
                hadd(m,1,1,i-1)  = hadd(m,1,1,i-1)
     &                           - (1.d0/6.d0)*dtdx1d(i-1)*dtdy
     &                           * bmcpamdq(m,i)
                hadd(m,2,-1,i-1) = hadd(m,2,-1,i-1)
     &                           + (1.d0/6.d0)*dtdx1d(i-1)*dtdy
     &                           * bpcmamdq(m,i)
                hadd(m,1,-1,i-1) = hadd(m,1,-1,i-1)
     &                           + (1.d0/6.d0)*dtdx1d(i-1)*dtdy
     &                           * bmcmamdq(m,i)
c
            endif
c
c           # Transverse propagation of the correction wave between
c           # cells sharing faces. This gives CAAu_{xxy}.
c
            if(m3.lt.2) go to 200
               hadd(m,2,0,i)   = hadd(m,2,0,i)
     &                         + dtdx1d(i)*cpcqxxp(m,i)
               hadd(m,1,0,i)   = hadd(m,1,0,i)
     &                         + dtdx1d(i)*cmcqxxp(m,i)
               hadd(m,2,0,i-1) = hadd(m,2,0,i-1)
     &                         - dtdx1d(i-1)*cpcqxxm(m,i)
               hadd(m,1,0,i-1) = hadd(m,1,0,i-1)
     &                         - dtdx1d(i-1)*cmcqxxm(m,i)
c
  200    continue
c
      return
      end


