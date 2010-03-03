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
!  Copyright (C) 2005-2009 Daniel Price. All rights reserved.
!  Contact: daniel.price@sci.monash.edu.au
!
!-----------------------------------------------------------------

!-------------------------------------------------------------------------
! Module containing settings and options relating to power spectrum plots
! includes default values of these options and submenu for changing them
!-------------------------------------------------------------------------
module settings_powerspec
 implicit none
 integer :: ipowerspecy, ipowerspecx, nfreqspec
 integer :: nwavelengths
 logical :: idisordered
 real :: wavelengthmax, wavelengthmin
 
 namelist /powerspecopts/ ipowerspecy,idisordered,nwavelengths,nfreqspec

contains

!---------------------------------------------
! set default values for these options
!---------------------------------------------
subroutine defaults_set_powerspec
  use settings_data, only:ndim
  implicit none

  idisordered = .true.
  ipowerspecy = max(ndim+1,2)
  ipowerspecx = 0 ! reset later
  nwavelengths = 128
  wavelengthmax = 1.0 ! reset later
  wavelengthmin = wavelengthmax/nwavelengths
  nfreqspec = 1

  return
end subroutine defaults_set_powerspec

!----------------------------------------------------------------------
! sets options and parameters for power spectrum calculation/plotting
!----------------------------------------------------------------------
subroutine options_powerspec
 use settings_data, only:ndim,ndataplots,numplot
 use limits, only:lim
 use labels, only:ipowerspec
 use prompting, only:prompt
 implicit none
 real :: boxsize

 if (ipowerspecy.lt.ndim+1) ipowerspecy = ndim+1
 if (ipowerspecy.gt.ndataplots) ipowerspecy = ndataplots
 call prompt('enter data to take power spectrum of',ipowerspecy,ndim+1,ndataplots)
 if (ipowerspecx.ne.1) then
    if (ipowerspecx.lt.1) ipowerspecx = 1
    if (ipowerspecx.gt.ndataplots) ipowerspecx = ndataplots
    call prompt('enter column to use as "time" or "space"',ipowerspecx,1,ndataplots) 
 endif
!
!--if box size has not been set then use x limits
!
 if (abs(wavelengthmax-1.0).lt.tiny(wavelengthmax)) then
    boxsize = abs(lim(1,2) - lim(1,1))
    if (boxsize.gt.tiny(boxsize)) wavelengthmax = boxsize
 endif
 call prompt('enter box size (max wavelength)',wavelengthmax,0.0)
 call prompt('enter number of wavelengths to sample ',nwavelengths,1)
 wavelengthmin = wavelengthmax/nwavelengths
 
 if (ipowerspec.le.ndataplots .or. ipowerspec.gt.numplot) then
    !--this should never happen
    print*,'*** ERROR: something wrong in powerspectrum limit setting'
 else
    print*,' wavelength range ',wavelengthmin,'->',wavelengthmax
    lim(ipowerspec,1) = 1./wavelengthmax
    lim(ipowerspec,2) = 1./wavelengthmin
    print*,' frequency range ',lim(ipowerspec,1),'->',lim(ipowerspec,2)
    if (nfreqspec.le.1) nfreqspec = 2*nwavelengths
    call prompt('how many frequency points between these limits? ',nfreqspec,nwavelengths)
 endif

!! call prompt('use Lomb periodogram? (no=interpolate and fourier) ',idisordered)

 return
end subroutine options_powerspec

end module settings_powerspec