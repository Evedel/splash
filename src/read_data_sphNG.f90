!-----------------------------------------------------------------
!
!  This file is (or was) part of SPLASH, a visualisation tool
!  for Smoothed Particle Hydrodynamics written by Daniel Price:
!
!  http://users.monash.edu.au/~dprice/splash
!
!  SPLASH comes with ABSOLUTELY NO WARRANTY.
!  This is free software; and you are welcome to redistribute
!  it under the terms of the GNU General Public License
!  (see LICENSE file for details) and the provision that
!  this notice remains intact. If you modify this file, please
!  note section 2a) of the GPLv2 states that:
!
!  a) You must cause the modified files to carry prominent notices
!     stating that you changed the files and the date of any change.
!
!  Copyright (C) 2005-2013 Daniel Price. All rights reserved.
!  Contact: daniel.price@monash.edu
!
!-----------------------------------------------------------------

!-------------------------------------------------------------------------
! this subroutine reads from the data file(s)
! change this to change the format of data input
!
! THIS VERSION IS FOR READING UNFORMATTED OUTPUT FROM
! THE NEXT GENERATION SPH CODE (sphNG)
!
! (also my Phantom SPH code which uses a similar format)
!
! *** CONVERTS TO SINGLE PRECISION ***
!
! SOME CHOICES FOR THIS FORMAT CAN BE SET USING THE FOLLOWING
!  ENVIRONMENT VARIABLES:
!
! SSPLASH_RESET_CM if 'YES' then centre of mass is reset to origin
! SSPLASH_OMEGA if non-zero subtracts corotating velocities with omega as set
! SSPLASH_OMEGAT if non-zero subtracts corotating positions and velocities with omega as set
! SSPLASH_TIMEUNITS sets default time units, either 's','min','hrs','yrs' or 'tfreefall'
!
! the data is stored in the global array dat
!
! >> this subroutine must return values for the following: <<
!
! ncolumns    : number of data columns
! ndim, ndimV : number of spatial, velocity dimensions
! nstepsread  : number of steps read from this file
!
! maxplot,maxpart,maxstep      : dimensions of main data array
! dat(maxplot,maxpart,maxstep) : main data array
!
! npartoftype(1:6,maxstep) : number of particles of each type in each timestep
!
! time(maxstep)       : time at each step
! gamma(maxstep)      : gamma at each step
!
! most of these values are stored in global arrays
! in the module 'particle_data'
!
! Partial data read implemented Nov 2006 means that columns with
! the 'required' flag set to false are not read (read is therefore much faster)
!-------------------------------------------------------------------------
module sphNGread
 use params
 implicit none
 real(doub_prec) :: udist,umass,utime,umagfd
 real :: tfreefall
 integer :: istartmhd,istartrt,nmhd,idivvcol,icurlvxcol,icurlvycol,icurlvzcol
 integer :: nhydroreal4,istart_extra_real4
 integer :: nhydroarrays,nmhdarrays
 logical :: phantomdump,smalldump,mhddump,rtdump,usingvecp,igotmass,h2chem,rt_in_header
 logical :: usingeulr,cleaning
 logical :: batcode
 
contains

 !-------------------------------------------------------------------
 ! function mapping iphase setting in sphNG to splash particle types
 !-------------------------------------------------------------------
 elemental integer function itypemap_sphNG(iphase)
  integer*1, intent(in) :: iphase

  select case(int(iphase))
  case(0)
    itypemap_sphNG = 1
  case(1:9)
    itypemap_sphNG = 3
  case(10:)
    itypemap_sphNG = 4
  case default
    itypemap_sphNG = 5
  end select  
  
 end function itypemap_sphNG

 !---------------------------------------------------------------------
 ! function mapping iphase setting in Phantom to splash particle types
 !---------------------------------------------------------------------
 elemental integer function itypemap_phantom(iphase)
  integer*1, intent(in) :: iphase
  
  select case(int(iphase))
  case(1,2)
    itypemap_phantom = iphase
  case(3)
    itypemap_phantom = 4
  case(4)
    itypemap_phantom = 6
  case(-3)
    itypemap_phantom = 3
  case default
    itypemap_phantom = 5
  end select
  
 end function itypemap_phantom

end module sphNGread

subroutine read_data(rootname,indexstart,nstepsread)
  use particle_data,  only:dat,gamma,time,iamtype,npartoftype,maxpart,maxstep,maxcol,masstype
  !use params,         only:int1,int8
  use settings_data,  only:ndim,ndimV,ncolumns,ncalc,required,ipartialread,&
                      lowmemorymode,ntypes,iverbose
  use mem_allocation, only:alloc
  use system_utils,   only:lenvironment,renvironment
  use labels,         only:ipmass,irho,ih,ix,ivx,labeltype,print_types
  use calcquantities, only:calc_quantities
  use sphNGread
  implicit none
  integer, intent(in)  :: indexstart
  integer, intent(out) :: nstepsread
  character(len=*), intent(in) :: rootname
  integer, parameter :: maxarrsizes = 10, maxreal = 50
  integer, parameter :: ilocbinary = 24
  real,    parameter :: pi=3.141592653589
  integer :: i,j,k,ierr,iunit
  integer :: intg1,int2,int3
  integer :: i1,iarr,i2,iptmass1,iptmass2,ilocpmassinitial
  integer :: npart_max,nstep_max,ncolstep,icolumn,nptmasstot
  integer :: narrsizes,nints,nreals,nreal4s,nreal8s
  integer :: nskip,ntotal,npart,n1,n2,ninttypes,ngas
  integer :: nreassign,naccrete,nkill,iblock,nblocks,ntotblock,ncolcopy
  integer :: ipos,nptmass,nptmassi,nstar,nunknown,ilastrequired
  integer :: imaxcolumnread,nhydroarraysinfile,nremoved
  integer :: itype,iphaseminthistype,iphasemaxthistype,nthistype,iloc
  integer, dimension(maxparttypes) :: npartoftypei
  real,    dimension(maxparttypes) :: massoftypei
  real    :: pmassi,hi,rhoi,hrlim,rad2d
  logical :: iexist, doubleprec,imadepmasscolumn,gotbinary,gotiphase
  logical :: debug

  character(len=len(rootname)+10) :: dumpfile
  character(len=100) :: fileident
  character(len=10)  :: string

  integer*8, dimension(maxarrsizes) :: isize
  integer, dimension(maxarrsizes) :: nint,nint1,nint2,nint4,nint8,nreal,nreal4,nreal8
  integer*1, dimension(:), allocatable :: iphase
  integer, dimension(:), allocatable :: listpm
  real(doub_prec), dimension(:), allocatable :: dattemp
  real*4, dimension(:), allocatable :: dattempsingle
  real(doub_prec) :: r8
  real, dimension(maxreal) :: dummyreal
  real, dimension(:,:), allocatable :: dattemp2
  real :: rhozero,hfact,omega,r4,tff
  logical :: skip_corrupted_block_3

  nstepsread = 0
  nstep_max = 0
  npart_max = maxpart
  npart = 0
  iunit = 15
  ipmass = 4
  idivvcol = 0
  icurlvxcol = 0
  icurlvycol = 0
  icurlvzcol = 0
  nhydroreal4 = 0
  umass = 1.d0
  utime = 1.d0
  udist = 1.d0
  umagfd = 1.d0
  istartmhd = 0
  istartrt  = 0
  istart_extra_real4 = 100
  nmhd      = 0
  phantomdump = .false.
  smalldump   = .false.
  mhddump     = .false.
  rtdump      = .false.
  rt_in_header = .false.
  usingvecp   = .false.
  usingeulr   = .false.
  h2chem      = .false.
  igotmass    = .false.
  tfreefall   = 1.d0
  gotbinary   = .false.
  gotiphase   = .false.
  batcode     = .false.
  skip_corrupted_block_3 = .false.

  dumpfile = trim(rootname)
  !
  !--check if data file exists
  !
  inquire(file=dumpfile,exist=iexist)
  if (.not.iexist) then
     print "(a)",' *** error: '//trim(dumpfile)//': file not found ***'
     return
  endif
  !
  !--fix number of spatial dimensions
  !
  ndim = 3
  ndimV = 3

  j = indexstart
  nstepsread = 0
  doubleprec = .true.
  ilastrequired = 0
  do i=1,size(required)-1
     if (required(i)) ilastrequired = i
  enddo

  if (iverbose.ge.1) print "(1x,a)",'reading sphNG format'
  write(*,"(26('>'),1x,a,1x,26('<'))") trim(dumpfile)

  debug = lenvironment('SSPLASH_DEBUG')
  if (debug) iverbose = 1
!
!--open the (unformatted) binary file
!
   open(unit=iunit,iostat=ierr,file=dumpfile,status='old',form='unformatted')
   if (ierr /= 0) then
      print "(a)",'*** ERROR OPENING '//trim(dumpfile)//' ***'
      return
   else
      !
      !--read header key to work out precision
      !
      doubleprec = .true.
      read(iunit,iostat=ierr) intg1,r8,int2,i1,int3
      if (intg1.ne.690706) then
         print "(a)",'*** ERROR READING HEADER: corrupt file/zero size/wrong endian?'
         close(iunit)
         return
      endif
      if (int2.ne.780806) then
         print "(a)",' single precision dump'
         rewind(iunit)
         read(iunit,iostat=ierr) intg1,r4,int2,i1,int3
         if (int2.ne.780806) then
            print "(a)",'ERROR determining single/double precision in file header'
         endif
         doubleprec = .false.
      elseif (int3.ne.690706) then
         print "(a)",'*** WARNING: default int appears to be int*8: not implemented'
      else
         if (debug) print "(a)",' double precision dump' ! no need to print this
      endif
   endif
!
!--read file ID
!
   read(iunit,iostat=ierr) fileident
   if (ierr /=0) then
      print "(a)",'*** ERROR READING FILE ID ***'
      close(iunit)
      return
   else
      print "(a)",' File ID: '//trim(fileident)
   endif
   smalldump = .false.
   mhddump = .false.
   usingvecp = .false.
   rtdump = .false.
   imadepmasscolumn = .false.
   cleaning = .false.
   if (fileident(1:1).eq.'S') then
      smalldump = .true.
   endif
   if (index(fileident,'Phantom').ne.0) then
      phantomdump = .true.
   else
      phantomdump = .false.
   endif
   if (index(fileident,'vecp').ne.0) then
      usingvecp = .true.
   endif
   if (index(fileident,'eulr').ne.0) then
      usingeulr = .true.
   endif
   if (index(fileident,'clean').ne.0) then
      cleaning = .true.
   endif
   if (index(fileident,'H2chem').ne.0) then
      h2chem = .true.
   endif
   if (index(fileident,'RT=on').ne.0) then
      rt_in_header = .true.
   endif
   if (index(fileident,'This is a test').ne.0) then
      batcode = .true.
   endif
!
!--read global dump header
!
   nblocks = 1 ! number of MPI blocks
   npartoftypei(:) = 0
   read(iunit,iostat=ierr) nints
   if (ierr /=0) then
      print "(a)",'error reading nints'
      close(iunit)
      return
   else
      if (nints.lt.3) then
         if (.not.phantomdump) print "(a)",'WARNING: npart,n1,n2 NOT IN HEADER??'
         read(iunit,iostat=ierr) npart
         npartoftypei(1) = npart
      elseif (phantomdump) then
         if (nints.lt.7) then
            ntypes = nints - 1
            read(iunit,iostat=ierr) npart,npartoftypei(1:ntypes)
         else
            ntypes = 5
            read(iunit,iostat=ierr) npart,npartoftypei(1:5),nblocks
         endif
         if (debug) then
            print*,'DEBUG: ntypes = ',ntypes,' npartoftype = ',npartoftypei(:)
         endif
         n1 = npartoftypei(1)
         n2 = 0
      elseif (nints.ge.7) then
         read(iunit,iostat=ierr) npart,n1,n2,nreassign,naccrete,nkill,nblocks
      else
         print "(a)",'warning: nblocks not read from file (assuming non-MPI dump)'
         read(iunit,iostat=ierr) npart,n1,n2
      endif
      if (ierr /=0) then
         print "(a)",'error reading npart,n1,n2 and/or number of MPI blocks'
         close(iunit)
         return
      elseif (nblocks.gt.2000) then
         print *,'npart = ',npart,' MPI blocks = ',nblocks
         nblocks = 1
         print*,' corrupt number of MPI blocks, assuming 1 '
      else
         if (iverbose.ge.1) print *,'npart = ',npart,' MPI blocks = ',nblocks
      endif
   endif
!--int*1, int*2, int*4, int*8
   do i=1,4
      read(iunit,end=55,iostat=ierr) ninttypes
      if (ninttypes.gt.0) read(iunit,end=55,iostat=ierr)
      if (ierr /=0) print "(a)",'error skipping int types'
   enddo
!--default reals
   read(iunit,end=55,iostat=ierr) nreals
   if (ierr /=0) then
      print "(a)",'error reading default reals'
      close(iunit)
      return
   else
!      print*,'nreals = ',nreals
      if (nreals.gt.maxreal) then
         print*,'WARNING: nreal> array size'
         nreals = maxreal
      endif
      if (doubleprec) then
         if (allocated(dattemp)) deallocate(dattemp)
         allocate(dattemp(nreals),stat=ierr)
         if (ierr /=0) print*,'ERROR in memory allocation'
         read(iunit,end=55,iostat=ierr) dattemp(1:nreals)
         dummyreal(1:nreals) = real(dattemp(1:nreals))
      else
         read(iunit,end=55,iostat=ierr) dummyreal(1:nreals)
      endif
   endif
!--real*4, real*8
   read(iunit,end=55,iostat=ierr) nreal4s
!   print "(a,i3)",' nreal4s = ',nreal4s
   if (nreal4s.gt.0) read(iunit,end=55,iostat=ierr)

   read(iunit,end=55,iostat=ierr) nreal8s
!   print "(a,i3)",' ndoubles = ',nreal8s
   if (iverbose.ge.1) print "(4(a,i3),a)",' header contains ',nints,' ints, ',&
                            nreals,' reals,',nreal4s,' real4s, ',nreal8s,' doubles'
   if (nreal8s.ge.4) then
      read(iunit,end=55,iostat=ierr) udist,umass,utime,umagfd
   elseif (nreal8s.ge.3) then
      read(iunit,end=55,iostat=ierr) udist,umass,utime
      umagfd = 1.0
   else
      print "(a)",'*** WARNING: units not found in file'
      udist = 1.0
      umass = 1.0
      utime = 1.0
      umagfd = 1.0
   endif
   if (ierr /= 0) then
      print "(a)",'*** error reading units'
   endif
!
!--Total number of array blocks in the file
!
   read(iunit,end=55,iostat=ierr) narrsizes
   if (debug) print*,' nblocks(total)=',narrsizes
   narrsizes = narrsizes/nblocks
   if (ierr /= 0) then
      print "(a)",'*** error reading number of array sizes ***'
      close(iunit)
      return
   elseif (narrsizes.gt.maxarrsizes) then
      narrsizes = maxarrsizes
      print "(a,i2)",'WARNING: too many array sizes: reading only ',narrsizes
   endif
   if (narrsizes.ge.4 .and. nreal8s.lt.4) then
      print "(a)",' WARNING: could not read magnetic units from dump file'
   endif
   if (debug) print*,' number of array sizes = ',narrsizes
!
!--Attempt to read all MPI blocks
!
   ntotal = 0
   ntotblock = 0
   nptmasstot = 0
   i2 = 0
   iptmass2 = 0
   igotmass = .true.
   massoftypei(:) = 0.

   over_MPIblocks: do iblock=1,nblocks

      !if (nblocks.gt.1) print "(10('-'),' MPI block ',i4,1x,10('-'))",iblock
!
!--read array header from this block
!
   if (iblock.eq.1) ncolstep = 0
   do iarr=1,narrsizes
      read(iunit,end=55,iostat=ierr) isize(iarr),nint(iarr),nint1(iarr),nint2(iarr), &
                 nint4(iarr),nint8(iarr),nreal(iarr),nreal4(iarr),nreal8(iarr)
      if (iarr.eq.1) then
         ntotblock = isize(iarr)
         if (npart.le.0) npart = ntotblock
         ntotal = ntotal + ntotblock
      elseif (iarr.eq.2) then
         nptmasstot = nptmasstot + isize(iarr)
      endif
      if (debug) print*,'DEBUG: array size ',iarr,' size = ',isize(iarr)
      if (isize(iarr).gt.0 .and. iblock.eq.1) then
         string = ''
         if (iarr.eq.3 .and. (.not. phantomdump .and. (.not.rt_in_header))) then
            string = '[CORRUPT]'
            skip_corrupted_block_3 = .true.
         endif
         if (iverbose.ge.1) print "(1x,a,i1,a,i12,a,5(i2,1x),a,3(i2,1x),a)", &
            'block ',iarr,' dim = ',isize(iarr),' nint =',nint(iarr),nint1(iarr), &
            nint2(iarr),nint4(iarr),nint8(iarr),'nreal =',nreal(iarr),nreal4(iarr),nreal8(iarr),trim(string)
         if (iarr.eq.3 .and. skip_corrupted_block_3) then
            nreal(iarr) = 0
            nreal4(iarr) = 0
            nreal8(iarr) = 0
         endif
      endif
!--we are going to read all real arrays but need to convert them all to default real
      if (iarr.ne.2 .and. isize(iarr).eq.isize(1) .and. iblock.eq.1) then
         ncolstep = ncolstep + nreal(iarr) + nreal4(iarr) + nreal8(iarr)
      endif
   enddo
   if (debug) print*,'DEBUG: ncolstep=',ncolstep,' from file header, also nptmasstot = ',nptmasstot
!
!--this is a bug fix for a corrupt version of wdump outputting bad
!  small dump files
!
   if (smalldump .and. nreal(1).eq.5 .and. iblock.eq.1) then
      print*,'FIXING CORRUPT HEADER ON SMALL DUMPS: assuming nreal=3 not 5'
      nreal(1) = 3
      ncolstep = ncolstep - 2
   endif

   npart_max = maxval(isize(1:narrsizes))
   npart_max = max(npart_max,npart+nptmasstot,ntotal)
!
!--work out from array header what sort of dump this is and where things should lie
!
   if (iblock.eq.1) then
      igotmass = .true.
      if (smalldump .or. phantomdump) then
         if (phantomdump .or. nreals.eq.15) then
            ilocpmassinitial = 15
         else
            ilocpmassinitial = 23
         endif
         if (nreals.ge.ilocpmassinitial) then
            massoftypei(1) = dummyreal(ilocpmassinitial)
            if (debug) print*,'DEBUG: got massoftype(gas) = ',massoftypei(1)
            if (massoftypei(1).gt.tiny(0.) .and. .not.lowmemorymode) then
               ncolstep = ncolstep + 1  ! make an extra column to contain particle mass
               imadepmasscolumn = .true.
            elseif (lowmemorymode) then
               igotmass = .false.
            else
               igotmass = .false.
            endif
            !--read dust mass from phantom dumps
            if (phantomdump .and. nreals.ge.ilocpmassinitial+1) then
               massoftypei(2) = dummyreal(ilocpmassinitial+1)
            else
               massoftypei(2) = 0.
            endif
         else
            print "(a)",' error extracting particle mass from small dump file'
            massoftypei(1) = 0.
            igotmass = .false.
         endif
         if (abs(massoftypei(1)).lt.tiny(0.) .and. nreal(1).lt.4) then
            print "(a)",' error: particle masses not present in small dump file'
            igotmass = .false.
         endif
      endif
      if (debug) print*,'DEBUG: gotmass = ',igotmass, ' ncolstep = ',ncolstep
!
!--   to handle both small and full dumps, we need to place the quantities dumped
!     in both small and full dumps at the start of the dat array
!     quantities only in the full dump then come after
!     also means that hydro/MHD are "semi-compatible" in the sense that x,y,z,m,h and rho
!     are in the same place for both types of dump
!
      ix(1) = 1
      ix(2) = 2
      ix(3) = 3
      if (igotmass) then
         ipmass = 4
         ih = 5
         irho = 6
         nhydroarrays = 6 ! x,y,z,m,h,rho
      else
         ipmass = 0
         ih = 4
         irho = 5
         nhydroarrays = 5 ! x,y,z,h,rho
      endif
      nhydroarraysinfile = nreal(1) + nreal4(1) + nreal8(1)
      nhydroreal4 = nreal4(1)
      if (imadepmasscolumn) nhydroarraysinfile = nhydroarraysinfile + 1
      if (nhydroarraysinfile .lt.nhydroarrays .and. .not.phantomdump) then
         print "(a)",' ERROR: one of x,y,z,m,h or rho missing in small dump read'
         nhydroarrays = nreal(1)+nreal4(1)+nreal8(1)
      elseif (phantomdump .and. (nreal(1).lt.3 .or. nreal4(1).lt.1)) then
         print "(a)",' ERROR: x,y,z or h missing in phantom read'
      endif
      if (narrsizes.ge.4) then
         nmhdarrays = 3 ! Bx,By,Bz
         nmhd = nreal(4) + nreal4(4) + nreal8(4) - nmhdarrays ! how many "extra" mhd arrays
         if (debug) print*,'DEBUG: ',nmhd,' extra MHD arrays'
      else
         nmhdarrays = 0
      endif

      !--radiative transfer dump?
      if (narrsizes.ge.3 .and. isize(3).eq.isize(1)) rtdump = .true.
      !--mhd dump?
      if (narrsizes.ge.4) mhddump = .true.

      if (.not.(mhddump.or.smalldump)) then
         ivx = nhydroarrays+1
      elseif (mhddump .and. .not.smalldump) then
         ivx = nhydroarrays+nmhdarrays+1
      else
         ivx = 0
      endif
      !--need to force read of velocities e.g. for corotating frame subtraction
      if (any(required(ivx:ivx+ndimV-1))) required(ivx:ivx+ndimV-1) = .true.

      !--for phantom dumps, also make a column for density
      !  and divv, if a .divv file exists
      if (phantomdump) then
         ncolstep = ncolstep + 1
         inquire(file=trim(dumpfile)//'.divv',exist=iexist)
         if (iexist) then
            idivvcol   = ncolstep + 1
            icurlvxcol = ncolstep + 2
            icurlvycol = ncolstep + 3
            icurlvzcol = ncolstep + 4
            ncolstep   = ncolstep + 4
         endif
      endif
   endif
!
!--allocate memory now that we know the number of columns
!
   if (iblock.eq.1) then
      ncolumns = ncolstep + ncalc
      if (ncolumns.gt.maxplot) then
         print*,'ERROR with ncolumns = ',ncolumns,' in data read'
         return
      endif
      ilastrequired = 0
      do i=1,ncolumns
         if (required(i)) ilastrequired = i
      enddo
   endif

   if (npart_max.gt.maxpart .or. j.gt.maxstep .or. ncolumns.gt.maxcol) then
      if (lowmemorymode) then
         call alloc(max(npart_max+2,maxpart),j,ilastrequired)
      else
         call alloc(max(npart_max+2,maxpart),j,ncolumns,mixedtypes=.true.)
      endif
   endif

   if (iblock.eq.1) then
!--extract required information from the first block header
      time(j) = dummyreal(1)
      gamma(j) = dummyreal(3)
      rhozero = dummyreal(4)
      masstype(:,j) = massoftypei(:)

      if (rhozero.gt.0.) then
         tfreefall = SQRT((3. * pi) / (32. * rhozero))
         tff = time(j)/tfreefall
      else
         tfreefall = 0.
         tff = 0.
      endif
      if (phantomdump) then
         npartoftype(:,j) = 0.
         do i=1,ntypes !--map from phantom types to splash types
            itype = itypemap_phantom(int(i,kind=1))
            if (debug) print*,'DEBUG: npart of type ',itype,' += ',npartoftypei(i)
            npartoftype(itype,j) = npartoftype(itype,j) + npartoftypei(i)
         enddo
         npartoftype(3,j) = nptmasstot  ! sink particles
         if (nblocks.gt.1) then
            print "(a)",' setting ngas=npart for MPI code '
            npartoftype(1,j) = npart
            npartoftype(2:,j) = 0
         endif
         !
         !--if Phantom calculation uses the binary potential
         !  then read this as two point mass particles
         !
         if (nreals.ge.ilocbinary + 14) then
            if (nreals.ge.ilocbinary + 15) then
               ipos = ilocbinary
            else
               print*,'*** WARNING: obsolete header format for external binary information ***'
               ipos = ilocbinary + 1
            endif
            if (debug) print*,'DEBUG: reading binary information from header ',ilocbinary
            if (any(dummyreal(ilocbinary:ilocbinary+14).ne.0.)) then
               gotbinary = .true.
               npartoftype(3,j) = 2
               ntotal = ntotal + 2
               dat(npart+1,ix(1),j) = dummyreal(ipos)
               dat(npart+1,ix(2),j) = dummyreal(ipos+1)
               dat(npart+1,ix(3),j) = dummyreal(ipos+2)
               if (debug) print *,npart+1,npart+2
               if (iverbose.ge.1) print *,'binary position:   primary: ',dummyreal(ipos:ipos+2)
               if (nreals.ge.ilocbinary+15) then
                  if (ipmass.gt.0) dat(npart+1,ipmass,j) = dummyreal(ipos+3)
                  dat(npart+1,ih,j)     = dummyreal(ipos+4)
                  dat(npart+2,ix(1),j)  = dummyreal(ipos+5)
                  dat(npart+2,ix(2),j)  = dummyreal(ipos+6)
                  dat(npart+2,ix(3),j)  = dummyreal(ipos+7)
                  if (ipmass.gt.0) dat(npart+2,ipmass,j) = dummyreal(ipos+8)
                  dat(npart+2,ih,j)     = dummyreal(ipos+9)
                  if (iverbose.ge.1) then
                     print *,'                 secondary: ',dummyreal(ipos+5:ipos+7)
                     print *,' m1: ',dummyreal(ipos+3),' m2:',dummyreal(ipos+8),&
                             ' h1: ',dummyreal(ipos+4),' h2:',dummyreal(ipos+9)
                  endif
                  ipos = ipos + 10
               else
                  dat(npart+1,ih,j)    = dummyreal(ipos+3)
                  dat(npart+2,ix(1),j) = dummyreal(ipos+4)
                  dat(npart+2,ix(2),j) = dummyreal(ipos+5)
                  dat(npart+2,ix(3),j) = dummyreal(ipos+6)
                  dat(npart+2,ih,j)    = dummyreal(ipos+7)
                  print *,'                 secondary: ',dummyreal(ipos+4:ipos+6)
                  ipos = ipos + 8
               endif
               if (ivx.gt.0) then
                  dat(npart+1,ivx,j)      = dummyreal(ipos)
                  dat(npart+1,ivx+1,j)    = dummyreal(ipos+1)
                  if (ndimV.eq.3) &
                     dat(npart+1,ivx+2,j) = dummyreal(ipos+2)
                  dat(npart+2,ivx,j)      = dummyreal(ipos+3)
                  dat(npart+2,ivx+1,j)    = dummyreal(ipos+4)
                  if (ndimV.eq.3) &
                     dat(npart+2,ivx+2,j) = dummyreal(ipos+5)
               endif
               npart  = npart  + 2
            endif
         endif
      else
         npartoftype(1,j) = npart
         npartoftype(2,j) = max(ntotal - npart,0)
      endif
      hfact = 1.2
      if (phantomdump) then
         if (nreals.lt.6) then
            print "(a)",' error: hfact not present in phantom dump'
         else
            hfact = dummyreal(6)
         endif
         print "(a,es12.4,a,f6.3,a,f5.2,a,es8.1)", &
               ' time = ',time(j),' gamma = ',gamma(j), &
               ' hfact = ',hfact,' tolh = ',dummyreal(7)
      elseif (batcode) then
         print "(a,es12.4,a,f9.5,a,f8.4,/,a,es12.4,a,es9.2,a,es10.2)", &
               '   time: ',time(j),  '   gamma: ',gamma(j), '   tsph: ',dummyreal(2), &
               '  radL1: ',dummyreal(4),'   PhiL1: ',dummyreal(5),'     Er: ',dummyreal(15)      
      else
         print "(a,es12.4,a,f9.5,a,f8.4,/,a,es12.4,a,es9.2,a,es10.2)", &
               '   time: ',time(j),  '   gamma: ',gamma(j), '   RK2: ',dummyreal(5), &
               ' t/t_ff: ',tff,' rhozero: ',rhozero,' dtmax: ',dummyreal(2)
      endif
      nstepsread = nstepsread + 1
      !
      !--stop reading file here if no columns required
      !
      if (ilastrequired.eq.0) exit over_MPIblocks

      if (allocated(iphase)) deallocate(iphase)
      allocate(iphase(npart_max+2))
      if (phantomdump) then
         iphase(:) = 1
      else
         iphase(:) = 0
      endif

      if (gotbinary) then
         iphase(npart-1) = -3
         iphase(npart)   = -3
      endif

   endif ! iblock = 1

!
!--Arrays
!
   imaxcolumnread = 0
   icolumn = 0
   istartmhd = 0
   istartrt = 0
   i1 = i2 + 1
   i2 = i1 + isize(1) - 1
   if (debug) then
      print "(1x,a10,i4,3(a,i12))",'MPI block ',iblock,':  particles: ',i1,' to ',i2,' of ',npart
   elseif (nblocks.gt.1) then
      if (iblock.eq.1) write(*,"(a,i1,a)",ADVANCE="no") ' reading MPI blocks: .'
      write(*,"('.')",ADVANCE="no")
   endif
   iptmass1 = iptmass2 + 1
   iptmass2 = iptmass1 + isize(2) - 1
   nptmass = nptmasstot
   if (nptmass.gt.0 .and. debug) print "(15x,3(a,i12))",'  pt. masses: ',iptmass1,' to ',iptmass2,' of ',nptmass

   do iarr=1,narrsizes
      if (nreal(iarr) + nreal4(iarr) + nreal8(iarr).gt.0) then
         if (iarr.eq.4) then
            istartmhd = imaxcolumnread + 1
            if (debug) print*,' istartmhd = ',istartmhd
         elseif (iarr.eq.3 .and. rtdump) then
            istartrt = max(nhydroarrays+nmhdarrays+1,imaxcolumnread + 1)
            if (debug) print*,' istartrt = ',istartrt
         endif
      endif
!--read iphase from array block 1
      if (iarr.eq.1) then
         !--skip default int
         nskip = nint(iarr)
         do i=1,nskip
            read(iunit,end=33,iostat=ierr)
         enddo
         if (nint1(iarr).lt.1) then
            if (.not.phantomdump .or. any(npartoftypei(2:).gt.0)) then
               print "(a)",' WARNING: can''t locate iphase in dump'
            elseif (phantomdump) then
               print "(a)",' WARNING: can''t locate iphase in dump'
            endif
            gotiphase = .false.
            !--skip remaining integer arrays
            nskip = nint1(iarr) + nint2(iarr) + nint4(iarr) + nint8(iarr)
         else
            gotiphase = .true.
            read(iunit,end=33,iostat=ierr) iphase(i1:i2)
            !--skip remaining integer arrays
            nskip = nint1(iarr) - 1 + nint2(iarr) + nint4(iarr) + nint8(iarr)
         endif
      elseif (smalldump .and. iarr.eq.2 .and. isize(iarr).gt.0 .and. .not.phantomdump) then
!--read listpm from array block 2 for small dumps (needed here to extract sink masses)
         if (allocated(listpm)) deallocate(listpm)
         allocate(listpm(isize(iarr)))
         if (nint(iarr).lt.1) then
            print "(a)",'ERROR: can''t locate listpm in dump'
            nskip = nint(iarr) + nint1(iarr) + nint2(iarr) + nint4(iarr) + nint8(iarr)
         else
            read(iunit,end=33,iostat=ierr) listpm(1:isize(iarr))
            nskip = nint(iarr) - 1 + nint1(iarr) + nint2(iarr) + nint4(iarr) + nint8(iarr)
         endif
      else
!--otherwise skip all integer arrays (not needed for plotting)
         nskip = nint(iarr) + nint1(iarr) + nint2(iarr) + nint4(iarr) + nint8(iarr)
      endif

      if (iarr.eq.3 .and. lenvironment('SSPLASH_BEN_HACKED')) then
         nskip = nskip - 1
         print*,' FIXING HACKED DUMP FILE'
      endif
      !print*,'skipping ',nskip
      do i=1,nskip
         read(iunit,end=33,iostat=ierr)
      enddo
!
!--real arrays
!
      if (iarr.eq.2) then
!--read sink particles from phantom dumps
         if (phantomdump .and. iarr.eq.2 .and. isize(iarr).gt.0) then
            if (nreal(iarr).lt.5) then
               print "(a)",'ERROR: not enough arrays written for sink particles in phantom dump'
               nskip = nreal(iarr)
            else
               iphase(npart+1:npart+isize(iarr)) = -3
               if (doubleprec) then
                  !--convert default real to single precision where necessary
                  if (debug) print*,'DEBUG: reading sink data, converting from double precision ',isize(iarr)
                  if (allocated(dattemp)) deallocate(dattemp)
                  allocate(dattemp(isize(iarr)),stat=ierr)
                  if (ierr /= 0) then
                     print "(a)",'ERROR in memory allocation'
                     return
                  endif
                  do k=1,nreal(iarr)
                     if (debug) print*,'DEBUG: reading sink array ',k,isize(iarr)
                     read(iunit,end=33,iostat=ierr) dattemp(1:isize(iarr))
                     if (ierr /= 0) print*,' ERROR during read of sink particle data, array ',k
                     select case(k)
                     case(1:3)
                        iloc = ix(k)
                     case(4)
                        iloc = ipmass
                     case(5)
                        iloc = ih
                     case(7:9)
                        iloc = ivx + k-7
                     case default
                        iloc = 0
                     end select
                     if (iloc.gt.size(dat(1,:,j))) then; print*,' error iloc = ',iloc,ivx; stop; endif
                     if (iloc.gt.0) then
                        do i=1,isize(iarr)
                           dat(npart+i,iloc,j) = real(dattemp(i))
                        enddo
                     else
                        if (debug) print*,'DEBUG: skipping sink particle array ',k
                     endif
                  enddo
               else
                  if (debug) print*,'DEBUG: reading sink data, directly into array ',isize(iarr)
                  do k=1,nreal(iarr)
                     select case(k)
                     case(1:3)
                        iloc = ix(k)
                     case(4)
                        iloc = ipmass
                     case(5)
                        iloc = ih
                     case(7:9)
                        if (ivx.gt.0) then
                           iloc = ivx + k - 7
                        else
                           iloc = 0
                        endif
                     case default
                        iloc = 0
                     end select
                     if (iloc.gt.0) then
                        if (debug) print*,'DEBUG: reading sinks into ',npart+1,'->',npart+isize(iarr),iloc
                        read(iunit,end=33,iostat=ierr) dat(npart+1:npart+isize(iarr),iloc,j)
                        if (ierr /= 0) print*,' ERROR during read of sink particle data, array ',k
                     else
                        if (debug) print*,'DEBUG: skipping sink particle array ',k
                        read(iunit,end=33,iostat=ierr)
                     endif
                  enddo
               endif
               npart  = npart + isize(iarr)
            endif
         elseif (smalldump .and. iarr.eq.2 .and. allocated(listpm)) then
!--for sphNG, read sink particle masses from block 2 for small dumps
            if (nreal(iarr).lt.1) then
               if (isize(iarr).gt.0) print "(a)",'ERROR: sink masses not present in small dump'
               nskip = nreal(iarr) + nreal4(iarr) + nreal8(iarr)
            else
               if (doubleprec) then
                  !--convert default real to single precision where necessary
                  if (allocated(dattemp)) deallocate(dattemp)
                  allocate(dattemp(isize(iarr)),stat=ierr)
                  if (ierr /=0) print "(a)",'ERROR in memory allocation'
                  read(iunit,end=33,iostat=ierr) dattemp(1:isize(iarr))
                  if (nptmass.ne.isize(iarr)) print "(a)",'ERROR: nptmass.ne.block size'
                  if (ipmass.gt.0) then
                     do i=1,isize(iarr)
                        dat(listpm(iptmass1+i-1),ipmass,j) = real(dattemp(i))
                     enddo
                  else
                     print*,'WARNING: sink particle masses not read because no mass array allocated'
                  endif
               else
                  read(iunit,end=33,iostat=ierr) (dat(listpm(i),ipmass,j),i=iptmass1,iptmass2)
               endif
               nskip = nreal(iarr) - 1 + nreal4(iarr) + nreal8(iarr)
            endif
         else
!--for other blocks, skip real arrays if size different
            nskip = nreal(iarr) + nreal4(iarr) + nreal8(iarr)
         endif
         do i=1,nskip
            read(iunit,end=33,iostat=ierr)
         enddo
      elseif (isize(iarr).eq.isize(1)) then
!
!--read all real arrays defined on all the particles (same size arrays as block 1)
!
         if ((doubleprec.and.nreal(iarr).gt.0).or.nreal8(iarr).gt.0) then
            if (allocated(dattemp)) deallocate(dattemp)
            allocate(dattemp(isize(iarr)),stat=ierr)
            if (ierr /=0) print "(a)",'ERROR in memory allocation (read_data_sphNG: dattemp)'
         endif
!        default reals may need converting
         do i=1,nreal(iarr)
            if (iarr.eq.1.and.((phantomdump.and.i.eq.4) &
               .or.(.not.phantomdump.and.i.eq.6))) then
               ! read x,y,z,m,h and then place arrays after always-present ones
               ! (for phantom read x,y,z only)
               icolumn = nhydroarrays+nmhdarrays + 1
            elseif (.not.phantomdump .and. (iarr.eq.4 .and. i.le.3)) then
               icolumn = nhydroarrays + i
            else
               icolumn = imaxcolumnread + 1
            endif
            imaxcolumnread = max(imaxcolumnread,icolumn)
            if (debug) print*,' reading real ',icolumn
            if (required(icolumn)) then
               if (doubleprec) then
                  read(iunit,end=33,iostat=ierr) dattemp(1:isize(iarr))
                  dat(i1:i2,icolumn,j) = real(dattemp(1:isize(iarr)))
               else
                  read(iunit,end=33,iostat=ierr) dat(i1:i2,icolumn,j)
               endif
            else
               read(iunit,end=33,iostat=ierr)
            endif
         enddo
!
!        set masses for equal mass particles (not dumped in small dump or in phantom)
!
         if (((smalldump.and.nreal(1).lt.ipmass).or.phantomdump).and. iarr.eq.1) then
            if (abs(massoftypei(1)).gt.tiny(massoftypei)) then
               icolumn = ipmass
               if (required(ipmass) .and. ipmass.gt.0) then
                  if (phantomdump) then
                     dat(i1:i2,ipmass,j) = massoftypei(itypemap_phantom(iphase(i1:i2)))
                  else
                     where (iphase(i1:i2).eq.0) dat(i1:i2,icolumn,j) = massoftypei(1)
                  endif
               endif
               !--dust mass for phantom particles
               if (phantomdump .and. npartoftypei(2).gt.0 .and. ipmass.gt.0) then
                  print *,' dust particle mass = ',massoftypei(2),' ratio dust/gas = ',massoftypei(2)/massoftypei(1)
               endif
               if (debug) print*,'mass ',icolumn
            elseif (phantomdump .and. npartoftypei(1).gt.0) then
               print*,' ERROR: particle mass zero in Phantom dump file!'
            endif
         endif
!
!        real4 arrays (may need converting if splash is compiled in double precision)
! 
         if (nreal4(iarr).gt.0 .and. kind(dat).eq.doub_prec) then
            if (allocated(dattempsingle)) deallocate(dattempsingle)
            allocate(dattempsingle(isize(iarr)),stat=ierr)
            if (ierr /=0) print "(a)",'ERROR in memory allocation (read_data_sphNG: dattempsingle)'
         endif

!        real4s may need converting
         imaxcolumnread = max(imaxcolumnread,icolumn)
         if ((nreal(iarr)+nreal4(iarr)).gt.6) imaxcolumnread = max(imaxcolumnread,6)
         do i=1,nreal4(iarr)
            if (phantomdump) then
               if (iarr.eq.1 .and. i.eq.1) then
                  icolumn = ih ! h is always first real4 in phantom dumps
                  !--density depends on h being read
                  if (required(irho)) required(ih) = .true.
                  if (any(npartoftypei(2:).gt.0)) required(ih) = .true.
               elseif (iarr.eq.4 .and. i.le.3) then
                  icolumn = nhydroarrays + i
               else
                  icolumn = max(nhydroarrays+nmhdarrays + 1,imaxcolumnread + 1)
                  if (iarr.eq.1) then
                     istart_extra_real4 = min(istart_extra_real4,icolumn)
                     if (debug) print*,' istart_extra_real4 = ',istart_extra_real4
                  endif
               endif
            else
               if (iarr.eq.1 .and. i.eq.1) then
                  icolumn = irho ! density
               elseif (iarr.eq.1 .and. smalldump .and. i.eq.2) then
                  icolumn = ih ! h which is real4 in small dumps
               !--this was a bug for sphNG files...
               !elseif (iarr.eq.4 .and. i.le.3) then
               !   icolumn = nhydroarrays + i
               else
                  icolumn = max(nhydroarrays+nmhdarrays + 1,imaxcolumnread + 1)
                  if (iarr.eq.1) then
                     istart_extra_real4 = min(istart_extra_real4,icolumn)
                     if (debug) print*,' istart_extra_real4 = ',istart_extra_real4
                  endif
               endif
            endif
            imaxcolumnread = max(imaxcolumnread,icolumn)
            if (debug) print*,'reading real4 ',icolumn
            if (required(icolumn)) then
               if (allocated(dattempsingle)) THEN
                  read(iunit,end=33,iostat=ierr) dattempsingle(1:isize(iarr))
                  dat(i1:i2,icolumn,j) = real(dattempsingle(1:isize(iarr)))
               else
                  read(iunit,end=33,iostat=ierr) dat(i1:i2,icolumn,j)
               endif
            else
               read(iunit,end=33,iostat=ierr)
            endif
            !--construct density for phantom dumps based on h, hfact and particle mass
            if (phantomdump .and. icolumn.eq.ih) then
               icolumn = irho ! density
               !
               !--dead particles have -ve smoothing lengths in phantom
               !  so use abs(h) for these particles and hide them
               !
               if (any(npartoftypei(2:).gt.0)) then
                  if (.not.required(ih)) print*,'ERROR: need to read h, but required=F'
                  !--need masses for each type if not all gas
                  if (debug) print*,'DEBUG: phantom: setting h for multiple types ',i1,i2
                  if (debug) print*,'DEBUG: massoftype = ',massoftypei(:)
                  do k=i1,i2
                     itype = itypemap_phantom(iphase(k))
                     pmassi = massoftypei(itype)
                     hi = dat(k,ih,j)
                     if (hi > 0.) then
                        if (required(irho)) dat(k,irho,j) = pmassi*(hfact/hi)**3
                     elseif (hi < 0.) then
                        npartoftype(itype,j) = npartoftype(itype,j) - 1
                        npartoftype(5,j) = npartoftype(5,j) + 1
                        if (required(irho)) dat(k,irho,j) = pmassi*(hfact/abs(hi))**3
                     else
                        if (required(irho)) dat(k,irho,j) = 0.
                     endif
                  enddo
               else
                  if (debug) print*,'debug: phantom: setting rho for all types'
                  !--assume all particles are gas particles
                  do k=i1,i2
                     hi = dat(k,ih,j)
                     if (hi.gt.0.) then
                        rhoi = massoftypei(1)*(hfact/hi)**3
                     elseif (hi.lt.0.) then
                        rhoi = massoftypei(1)*(hfact/abs(hi))**3
                        iphase(k) = -1
                     else ! if h = 0.
                        rhoi = 0.
                        iphase(k) = -2
                     endif
                     if (required(irho)) dat(k,irho,j) = rhoi
                  enddo
               endif

               if (debug) print*,'debug: making density ',icolumn
            endif
         enddo
         icolumn = imaxcolumnread
!        real 8's need converting
         do i=1,nreal8(iarr)
            icolumn = icolumn + 1
            if (debug) print*,'reading real8 ',icolumn
            if (required(icolumn)) then
               read(iunit,end=33,iostat=ierr) dattemp(1:isize(iarr))
               dat(i1:i2,icolumn,j) = real(dattemp(1:isize(iarr)))
            else
               read(iunit,end=33,iostat=ierr)
            endif
         enddo
      endif
   enddo ! over array sizes
   enddo over_MPIblocks
!
!--reached end of file (during data read)
!
   goto 34
33 continue
   print "(/,1x,a,/)",'*** WARNING: END OF FILE DURING READ ***'
   print*,'Press any key to continue (but there is likely something wrong with the file...)'
   read*
34 continue
 !
 !--read .divv file for phantom dumps
 !
    if (phantomdump .and. idivvcol.ne.0 .and. any(required(idivvcol:icurlvzcol))) then
       print "(a)",' reading divv from '//trim(dumpfile)//'.divv'
       open(unit=66,file=trim(dumpfile)//'.divv',form='unformatted',status='old',iostat=ierr)
       if (ierr /= 0) then
          print "(a)",' ERROR opening '//trim(dumpfile)//'.divv'
       else
          read(66,iostat=ierr) dat(1:ntotal,idivvcol,j)
          if (ierr /= 0) print "(a)",' WARNING: ERRORS reading divv from file'
          if (any(required(icurlvxcol:icurlvzcol))) then
             read(66,iostat=ierr) dat(1:ntotal,icurlvxcol,j)
             read(66,iostat=ierr) dat(1:ntotal,icurlvycol,j)
             read(66,iostat=ierr) dat(1:ntotal,icurlvzcol,j)
          endif
          if (ierr /= 0) print "(a)",' WARNING: ERRORS reading curlv from file'
          close(66)
       endif
    endif
 !
 !--reset centre of mass to zero if environment variable "SSPLASH_RESET_CM" is set
 !
    if (allocated(dat) .and. n1.GT.0 .and. lenvironment('SSPLASH_RESET_CM') .and. allocated(iphase)) then
       call reset_centre_of_mass(dat(1:n1,1:3,j),dat(1:n1,4,j),iphase(1:n1),n1)
    endif
 ! 
 !--remove particles at large H/R is "SSPLASH_REMOVE_LARGE_HR" is set
 !
    if (lenvironment('SSPLASH_REMOVE_LARGE_HR')) then
       hrlim = renvironment('SSPLASH_HR_LIMIT')
       print "(a)", 'SSPLASH_REMOVE_LARGE_HR set:'
       print "(a)", 'Removing particles at large H/R values'
       print "(a,F7.4)", 'H/R limit set to ',hrlim
       
       nremoved = 0
       do i = 1,npart
          if (int(iphase(i)) == 0) then
             rad2d = sqrt(dat(i,1,j)**2 + dat(i,2,j)**2)
             if (abs(dat(i,3,j) / rad2d) >= hrlim) then
                iphase(i) = -1
                nremoved  = nremoved + 1
             endif
          endif
       enddo
       print "(I5,a)", nremoved, ' particles removed at large H/R'
    endif
 !
 !--reset corotating frame velocities if environment variable "SSPLASH_OMEGA" is set
 !
    if (allocated(dat) .and. n1.GT.0 .and. all(required(1:2))) then
       omega = renvironment('SSPLASH_OMEGAT')
       if (abs(omega).gt.tiny(omega) .and. ndim.ge.2) then
          call reset_corotating_positions(n1,dat(1:n1,1:2,j),omega,time(j))
       endif

       if (.not. smalldump) then
          if (abs(omega).lt.tiny(omega)) omega = renvironment('SSPLASH_OMEGA')
          if (abs(omega).gt.tiny(omega) .and. ivx.gt.0) then
             if (.not.all(required(1:2)) .or. .not.all(required(ivx:ivx+1))) then
                print*,' ERROR subtracting corotating frame with partial data read'
             else
                call reset_corotating_velocities(n1,dat(1:n1,1:2,j),dat(1:n1,ivx:ivx+1,j),omega)
             endif
          endif
       endif
    endif

    !--set flag to indicate that only part of this file has been read
    if (.not.all(required(1:ncolstep))) ipartialread = .true.


    nptmassi = 0
    nunknown = 0
    ngas = 0
    nstar = 0
    !--can only do this loop if we have read the iphase array
    iphasealloc: if (allocated(iphase)) then
!
!--translate iphase into particle types (mixed type storage)
!
    if (size(iamtype(:,j)).gt.1) then
       if (phantomdump) then
       !
       !--phantom: translate iphase to splash types
       !
          do i=1,npart
             itype = itypemap_phantom(iphase(i))
             iamtype(i,j) = itype
             select case(itype)
             case(1,2,4) ! remove accreted particles
                if (ih.gt.0 .and. required(ih)) then
                   if (dat(i,ih,j) <= 0.) then
                      iamtype(i,j) = 5
                   endif
                endif
             case(5)
                nunknown = nunknown + 1
             end select
          enddo
       else
       !
       !--sphNG: translate iphase to splash types
       !
          do i=1,npart
             itype = itypemap_sphNG(iphase(i))
             iamtype(i,j) = itype
             select case(itype)
             case(1)
               ngas = ngas + 1
             case(3)
               nptmassi = nptmassi + 1
             case(4)
               nstar = nstar + 1
             case default
               nunknown = nunknown + 1
             end select
          enddo
          do i=npart+1,ntotal
             iamtype(i,j) = 2
          enddo
       endif
       !print*,'mixed types: ngas = ',ngas,nptmassi,nunknown

    elseif (any(iphase(1:ntotal).ne.0)) then
       if (phantomdump) then
          print*,'ERROR: low memory mode will not work correctly with phantom + multiple types'
          print*,'press any key to ignore this and continue anyway (at your own risk...)'
          read*
       endif
!
!--place point masses after normal particles
!  if not storing the iamtype array
!
       print "(a)",' sorting particles by type...'
       nunknown = 0
       do i=1,npart
          if (iphase(i).ne.0) nunknown = nunknown + 1
       enddo
       ncolcopy = min(ncolstep,maxcol)
       allocate(dattemp2(nunknown,ncolcopy))

       iphaseminthistype = 0  ! to avoid compiler warnings
       iphasemaxthistype = 0
       do itype=1,3
          nthistype = 0
          ipos = 0
          select case(itype)
          case(1) ! ptmass
             iphaseminthistype = 1
             iphasemaxthistype = 9
          case(2) ! star
             iphaseminthistype = 10
             iphasemaxthistype = huge(iphasemaxthistype)
          case(3) ! unknown
             iphaseminthistype = -huge(iphaseminthistype)
             iphasemaxthistype = -1
          end select

          do i=1,ntotal
             ipos = ipos + 1
             if (iphase(i).ge.iphaseminthistype .and. iphase(i).le.iphasemaxthistype) then
                nthistype = nthistype + 1
                !--save point mass information in temporary array
                if (nptmassi.gt.size(dattemp2(:,1))) stop 'error: ptmass array bounds exceeded in data read'
                dattemp2(nthistype,1:ncolcopy) = dat(i,1:ncolcopy,j)
   !             print*,i,' removed', dat(i,1:3,j)
                ipos = ipos - 1
             endif
            !--shuffle dat array
             if (ipos.ne.i .and. i.lt.ntotal) then
     !           print*,'copying ',i+1,'->',ipos+1
                dat(ipos+1,1:ncolcopy,j) = dat(i+1,1:ncolcopy,j)
                !--must also shuffle iphase (to be correct for other types)
                iphase(ipos+1) = iphase(i+1)
             endif
          enddo

          !--append this type to end of dat array
          do i=1,nthistype
             ipos = ipos + 1
   !          print*,ipos,' appended', dattemp2(i,1:3)
             dat(ipos,1:ncolcopy,j) = dattemp2(i,1:ncolcopy)
             !--we make iphase = 1 for point masses (could save iphase and copy across but no reason to)
             iphase(ipos) = iphaseminthistype
          enddo

          select case(itype)
          case(1)
             nptmassi = nthistype
             if (nptmassi.ne.nptmass) print *,'WARNING: nptmass from iphase =',nptmassi,'not equal to nptmass =',nptmass
          case(2)
             nstar = nthistype
          case(3)
             nunknown = nthistype
          end select
       enddo

     endif

     endif iphasealloc

     if (allocated(dattemp)) deallocate(dattemp)
     if (allocated(dattempsingle)) deallocate(dattempsingle)
     if (allocated(dattemp2)) deallocate(dattemp2)
     if (allocated(iphase)) deallocate(iphase)
     if (allocated(listpm)) deallocate(listpm)

     call set_labels
     if (.not.phantomdump) then
        npartoftype(1,j) = npart - nptmassi - nstar - nunknown
        npartoftype(2,j) = ntotal - npart
        npartoftype(3,j) = nptmassi
        npartoftype(4,j) = nstar
        npartoftype(5,j) = nunknown
     else
        npartoftype(1,j) = npartoftype(1,j) - nunknown
        npartoftype(5,j) = npartoftype(5,j) + nunknown
     endif

     call print_types(npartoftype(:,j),labeltype)

     close(15)
     if (debug) print*,' finished data read, npart = ',npart, ntotal, npartoftype(1:ntypes,j)

     return

55 continue
   print "(a)", ' *** ERROR: end of file during header read ***'

close(15)

return

contains

!
!--reset centre of mass to zero
!
 subroutine reset_centre_of_mass(xyz,pmass,iphase,np)
  implicit none
  integer, intent(in) :: np
  real, dimension(np,3), intent(inout) :: xyz
  real, dimension(np), intent(in) :: pmass
  integer(kind=int1), dimension(np), intent(in) :: iphase
  real :: masstot,pmassi
  real, dimension(3) :: xcm
  integer :: i

  !
  !--get centre of mass
  !
  xcm(:) = 0.
  masstot = 0.
  do i=1,np
     if (iphase(i).ge.0) then
        pmassi = pmass(i)
        masstot = masstot + pmass(i)
        where (required(1:3)) xcm(:) = xcm(:) + pmassi*xyz(i,:)
     endif
  enddo
  xcm(:) = xcm(:)/masstot
  print*,'RESETTING CENTRE OF MASS (',pack(xcm,required(1:3)),') TO ZERO '

  if (required(1)) xyz(1:np,1) = xyz(1:np,1) - xcm(1)
  if (required(2)) xyz(1:np,2) = xyz(1:np,2) - xcm(2)
  if (required(3)) xyz(1:np,3) = xyz(1:np,3) - xcm(3)

  return
 end subroutine reset_centre_of_mass

 subroutine reset_corotating_velocities(np,xy,velxy,omeg)
  implicit none
  integer, intent(in) :: np
  real, dimension(np,2), intent(in) :: xy
  real, dimension(np,2), intent(inout) :: velxy
  real, intent(in) :: omeg
  integer :: ip

  print*,'SUBTRACTING COROTATING VELOCITIES, OMEGA = ',omeg
  do ip=1,np
     velxy(ip,1) = velxy(ip,1) + xy(ip,2)*omeg
  enddo
  do ip=1,np
     velxy(ip,2) = velxy(ip,2) - xy(ip,1)*omeg
  enddo

  return
 end subroutine reset_corotating_velocities

 subroutine reset_corotating_positions(np,xy,omeg,t)
  implicit none
  integer, intent(in) :: np
  real, dimension(np,2), intent(inout) :: xy
  real, intent(in) :: omeg,t
  real :: phii,phinew,r
  integer :: ip

  print*,'SUBTRACTING COROTATING POSITIONS, OMEGA = ',omeg,' t = ',t
!$omp parallel default(none) &
!$omp shared(xy,np) &
!$omp firstprivate(omeg,t) &
!$omp private(ip,r,phii,phinew)
!$omp do
  do ip=1,np
     r = sqrt(xy(ip,1)**2 + xy(ip,2)**2)
     phii = atan2(xy(ip,2),xy(ip,1))
     phinew = phii + omeg*t
     xy(ip,1) = r*COS(phinew)
     xy(ip,2) = r*SIN(phinew)
  enddo
!$omp end do
!$omp end parallel

  return
 end subroutine reset_corotating_positions

end subroutine read_data

!!------------------------------------------------------------
!! set labels for each column of data
!!------------------------------------------------------------

subroutine set_labels
  use labels, only:label,unitslabel,labelzintegration,labeltype,labelvec,iamvec, &
              ix,ipmass,irho,ih,iutherm,ivx,iBfirst,idivB,iJfirst,icv,iradenergy
  use params
  use settings_data,   only:ndim,ndimV,ntypes,ncolumns,UseTypeInRenderings
  use geometry,        only:labelcoord
  use settings_units,  only:units,unitzintegration
  use sphNGread
  use asciiutils,      only:lcase
  use system_commands, only:get_environment
  use system_utils,    only:lenvironment
  implicit none
  integer :: i
  real(doub_prec)   :: uergg
  character(len=20) :: string

  if (ndim.le.0 .or. ndim.gt.3) then
     print*,'*** ERROR: ndim = ',ndim,' in set_labels ***'
     return
  endif
  if (ndimV.le.0 .or. ndimV.gt.3) then
     print*,'*** ERROR: ndimV = ',ndimV,' in set_labels ***'
     return
  endif
!--all formats read the following columns
  do i=1,ndim
     ix(i) = i
  enddo
  if (igotmass) then
     ipmass = 4   !  particle mass
     ih = 5       !  smoothing length
  else
     ipmass = 0
     ih = 4       !  smoothing length
  endif
  irho = ih + 1     !  density
  if (smalldump .and. nhydroreal4.ge.3) iutherm = irho+1

!--the following only for mhd small dumps or full dumps
  if (ncolumns.ge.7) then
     if (mhddump) then
        iBfirst = irho+1
        if (.not.smalldump) then
           ivx = iBfirst+ndimV
           iutherm = ivx+ndimV

           if (phantomdump) then
              !--phantom MHD full dumps
              if (nmhd.ge.4) then
                 iamvec(istartmhd:istartmhd+ndimV-1) = istartmhd
                 labelvec(istartmhd:istartmhd+ndimV-1) = 'A'
                 do i=1,ndimV
                    label(istartmhd+i-1) = trim(labelvec(istartmhd))//'\d'//labelcoord(i,1)
                 enddo
                 if (nmhd.ge.7) then
                    label(istartmhd+3) = 'Euler beta\dx'
                    label(istartmhd+4) = 'Euler beta\dy'
                    label(istartmhd+5) = 'Euler beta\dz'
                    idivB = istartmhd+2*ndimV
                 else
                    idivB = istartmhd+ndimV
                 endif
              elseif (nmhd.ge.3) then
                 label(istartmhd) = 'Euler alpha'
                 label(istartmhd+1) = 'Euler beta'
                 idivB = istartmhd + 2
              elseif (nmhd.ge.2) then
                 label(istartmhd) = 'Psi'
                 idivB = istartmhd + 1
              elseif (nmhd.ge.1) then
                 idivB = istartmhd
              endif
              iJfirst = 0
              if (ncolumns.ge.idivB+1) then
                 label(idivB+1) = 'alpha\dB\u'
              endif

           else
              !--sphNG MHD full dumps
              label(iutherm+1) = 'grad h'
              label(iutherm+2) = 'grad soft'
              label(iutherm+3) = 'alpha'
              if (nmhd.ge.7 .and. usingvecp) then
                 iamvec(istartmhd:istartmhd+ndimV-1) = istartmhd
                 labelvec(istartmhd:istartmhd+ndimV-1) = 'A'
                 do i=1,ndimV
                    label(istartmhd+i-1) = trim(labelvec(16))//'\d'//labelcoord(i,1)
                 enddo
                 idivB = istartmhd+ndimV
              elseif (nmhd.ge.6 .and. usingeulr) then
                 label(istartmhd) = 'Euler alpha'
                 label(istartmhd+1) = 'Euler beta'
                 idivB = istartmhd + 2
              elseif (nmhd.ge.6) then
                 label(istartmhd) = 'psi'
                 idivB = istartmhd + 1
                 if (nmhd.ge.8) then
                    label(istartmhd+2+ndimV+1) = '\eta_{real}'
                    label(istartmhd+2+ndimV+2) = '\eta_{art}'
                    units(istartmhd+2+ndimV+1:istartmhd+2+ndimV+2) = udist*udist/utime
                    unitslabel(istartmhd+2+ndimV+1:istartmhd+2+ndimV+2) = ' [cm\u2\d/s]'
                 endif
                 if (nmhd.ge.14) then
                    label(istartmhd+2+ndimV+3) = 'fsym\dx'
                    label(istartmhd+2+ndimV+4) = 'fsym\dy'
                    label(istartmhd+2+ndimV+5) = 'fsym\dz'
                    labelvec(istartmhd+ndimV+5:istartmhd+ndimV+7) = 'fsym'
                    iamvec(istartmhd+ndimV+5:istartmhd+ndimV+7) = istartmhd+ndimV+5
                    label(istartmhd+2+ndimV+6) = 'faniso\dx'
                    label(istartmhd+2+ndimV+7) = 'faniso\dy'
                    label(istartmhd+2+ndimV+8) = 'faniso\dz'
                    labelvec(istartmhd+ndimV+8:istartmhd+ndimV+10) = 'faniso'
                    iamvec(istartmhd+ndimV+8:istartmhd+ndimV+10) = istartmhd+ndimV+8
                 endif
              elseif (nmhd.ge.1) then
                 idivB = istartmhd
              endif
              iJfirst = idivB + 1
              if (ncolumns.ge.iJfirst+ndimV) then
                 label(iJfirst+ndimV) = 'alpha\dB\u'
              endif
           endif
        else ! mhd small dump
           if (nhydroreal4.ge.3) iutherm = iBfirst+ndimV
        endif
     elseif (.not.smalldump) then
        ! pure hydro full dump
        ivx = irho+1
        iutherm = ivx + ndimV
        if (phantomdump) then
           if (istart_extra_real4.gt.0 .and. istart_extra_real4.lt.100) then
              label(istart_extra_real4) = 'alpha'
              label(istart_extra_real4+1) = 'alphau'
           endif
        else
           if (istart_extra_real4.gt.0 .and. istart_extra_real4.lt.100) then
              label(istart_extra_real4) = 'grad h'
              label(istart_extra_real4+1) = 'grad soft'
              label(istart_extra_real4+2) = 'alpha'
           endif
        endif
     endif

     if (phantomdump .and. h2chem) then
        if (smalldump) then
           label(nhydroarrays+nmhdarrays+1) = 'H_2 ratio'
        elseif (.not.smalldump .and. iutherm.gt.0) then
           label(iutherm+1) = 'H_2 ratio'
           label(iutherm+2) = 'HI abundance'
           label(iutherm+3) = 'proton abundance'
           label(iutherm+4) = 'e^- abundance'
           label(iutherm+5) = 'CO abundance'
        endif
     endif

     if (istartrt.gt.0 .and. istartrt.le.ncolumns .and. rtdump) then ! radiative transfer dump
        iradenergy = istartrt
        label(iradenergy) = 'radiation energy'
        uergg = (udist/utime)**2
        units(iradenergy) = uergg

        if (smalldump) then
           icv = istartrt+1
           !--the following lines refer to a format
           !  which was hopefully never used
           !iutherm = istartrt + 1
           !label(iutherm) = 'u'
           !icv = istartrt+2
        else
           label(istartrt+1) = 'opacity'
           units(istartrt+1) = udist**2/umass

           icv = istartrt+2

           label(istartrt+3) = 'lambda'
           units(istartrt+3) = 1.0

           label(istartrt+4) = 'eddington factor'
           units(istartrt+4) = 1.0
        endif

       if (icv.gt.0) then
          label(icv) = 'u/T'
          units(icv) = uergg
       endif
    else
       iradenergy = 0
       icv = 0
    endif
  endif


  label(ix(1:ndim)) = labelcoord(1:ndim,1)
  if (irho.gt.0) label(irho) = 'density'
  if (iutherm.gt.0) label(iutherm) = 'u'
  if (ih.gt.0) label(ih) = 'h       '
  if (ipmass.gt.0) label(ipmass) = 'particle mass'
  if (idivB.gt.0) label(idivB) = 'div B'
  if (idivvcol.gt.0) label(idivvcol) = 'div v'
  if (icurlvxcol.gt.0) label(icurlvxcol) = 'curl v\dx'
  if (icurlvycol.gt.0) label(icurlvycol) = 'curl v\dy'
  if (icurlvzcol.gt.0) label(icurlvzcol) = 'curl v\dz'
  if (icurlvxcol.gt.0 .and. icurlvycol.gt.0 .and. icurlvzcol.gt.0) then
     iamvec(icurlvxcol:icurlvzcol) = icurlvxcol
     labelvec(icurlvxcol:icurlvzcol) = 'curl v'
  endif

  !
  !--set labels for vector quantities
  !
  if (ivx.gt.0) then
     iamvec(ivx:ivx+ndimV-1) = ivx
     labelvec(ivx:ivx+ndimV-1) = 'v'
     do i=1,ndimV
        label(ivx+i-1) = trim(labelvec(ivx))//'\d'//labelcoord(i,1)
     enddo
  endif
  if (iBfirst.gt.0) then
     iamvec(iBfirst:iBfirst+ndimV-1) = iBfirst
     labelvec(iBfirst:iBfirst+ndimV-1) = 'B'
  endif
  if (iJfirst.gt.0) then
     iamvec(iJfirst:iJfirst+ndimV-1) = iJfirst
     labelvec(iJfirst:iJfirst+ndimV-1) = 'J'
  endif
  !
  !--set units for plot data
  !
!   npower = int(log10(udist))
!   udist = udist/10.**npower
!   udistAU = udist/1.495979e13
   if (ndim.ge.3) then
      units(1:3) = udist
      unitslabel(1:3) = ' [cm]'
   endif
!   do i=1,3
!      write(unitslabel(i),"('[ 10\u',i2,'\d cm]')") npower
!   enddo
   if (ipmass.gt.0) then
      units(ipmass) = umass
      unitslabel(ipmass) = ' [g]'
   endif
   units(ih) = udist
   unitslabel(ih) = ' [cm]'
   if (ivx.gt.0) then
      units(ivx:ivx+ndimV-1) = udist/utime
      unitslabel(ivx:ivx+ndimV-1) = ' [cm/s]'
   endif
   if (iutherm.gt.0) then
      units(iutherm) = (udist/utime)**2
      unitslabel(iutherm) = ' [erg/g]'
   endif
   units(irho) = umass/udist**3
   unitslabel(irho) = ' [g/cm\u3\d]'
   if (iBfirst.gt.0) then
      units(iBfirst:iBfirst+ndimV-1) = umagfd
      unitslabel(iBfirst:iBfirst+ndimV-1) = ' [G]'
   endif

   !--use the following two lines for time in years
   call get_environment('SSPLASH_TIMEUNITS',string)
   select case(trim(lcase(adjustl(string))))
   case('s','seconds')
      units(0) = utime
      unitslabel(0) = trim(string)
   case('min','minutes','mins')
      units(0) = utime/60.
      unitslabel(0) = trim(string)
   case('h','hr','hrs','hours','hour')
      units(0) = utime/3600.
      unitslabel(0) = trim(string)
   case('y','yr','yrs','years','year')
      units(0) = utime/3.1536e7
      unitslabel(0) = trim(string)
   case('d','day','days')
      units(0) = utime/(3600.*24.)
      unitslabel(0) = trim(string)
   case('tff','freefall','tfreefall')
   !--or use these two lines for time in free-fall times
      units(0) = 1./tfreefall
      unitslabel(0) = ' '
   case default
      units(0) = utime/3.1536e7
      unitslabel(0) = ' yrs'
   end select
   !--or use these two lines for time in free-fall times
   !units(0) = 1./tfreefall
   !unitslabel(0) = ' '

  unitzintegration = udist
  labelzintegration = ' [cm]'
  !
  !--set labels for each particle type
  !
  if (phantomdump) then  ! phantom
     ntypes = 5
     labeltype(1) = 'gas'
     labeltype(2) = 'dust'
     labeltype(3) = 'sink'
     labeltype(4) = 'boundary'
     labeltype(5) = 'unknown/dead'
     UseTypeInRenderings(1:2) = .true.
     if (lenvironment('SSPLASH_USE_DUST_PARTICLES')) then
        UseTypeInRenderings(2) = .false.
     endif
     UseTypeInRenderings(3) = .false.
     UseTypeInRenderings(4) = .true.
     UseTypeInRenderings(5) = .true.
  else
     ntypes = 5
     labeltype(1) = 'gas'
     labeltype(2) = 'ghost'
     labeltype(3) = 'sink'
     labeltype(4) = 'star'
     labeltype(5) = 'unknown/dead'
     UseTypeInRenderings(1) = .true.
     UseTypeInRenderings(2) = .true.
     UseTypeInRenderings(3) = .false.
     UseTypeInRenderings(4) = .true.
     UseTypeInRenderings(5) = .true.  ! only applies if turned on
  endif

!-----------------------------------------------------------

  return
end subroutine set_labels
