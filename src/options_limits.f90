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
!  Copyright (C) 2005-2011 Daniel Price. All rights reserved.
!  Contact: daniel.price@monash.edu
!
!-----------------------------------------------------------------

!-------------------------------------------------------------------------
! Module containing settings and options related to the plot limits
! includes default values of these options and submenu for changing them
!-------------------------------------------------------------------------
module settings_limits
 implicit none
 logical :: iadapt, iadaptcoords, adjustlimitstodevice
 real    :: scalemax
 real, dimension(3) :: xminoffset_track, xmaxoffset_track

contains

!---------------------------------------------
! set default values for these options
!---------------------------------------------
subroutine defaults_set_limits
  use multiplot, only:itrans
  implicit none

  iadapt           = .true.  ! adaptive plot limits
  iadaptcoords     = .false.
  adjustlimitstodevice = .false.
  scalemax         = 1.0     ! for rescaling adaptive limits
  itrans(:)        = 0       ! no transformations (log10 etc)
  xminoffset_track = 0.5     ! offset of limits from tracked particle
  xmaxoffset_track = 0.5     !

  return
end subroutine defaults_set_limits

!----------------------------------------------------------------------
! submenu with options relating to plot limits
!----------------------------------------------------------------------
subroutine submenu_limits(ichoose)
 use filenames,      only:nsteps,nstepsinfile,ifileopen
 use settings_data,  only:ndataplots,numplot,ndim,ivegotdata,iCalcQuantities, &
                          DataIsBuffered,itrackpart
 use calcquantities, only:calc_quantities
 !use settings_page, only:nstepsperpage
 use multiplot,      only:itrans
 use prompting,      only:prompt,print_logical
 use limits,         only:lim,set_limits,range,rangeset,anyrangeset,print_rangeinfo
 use labels,         only:label,ix,irad,is_coord
 use transforms,     only:ntrans,transform_label
 implicit none
 integer, intent(in) :: ichoose
 integer             :: iaction,ipick,i,index,itrackpartprev
 real                :: diff, mid, zoom
 character(len=120)  :: transprompt
 character(len=5)    :: string,string2

 zoom = 1.0

 iaction = ichoose
 if (iadapt) then
    string = 'ADAPT'
 else
    string = 'FIXED'
 endif
 if (iadaptcoords) then
    string2 = 'ADAPT'
 else
    string2 = 'FIXED'
 endif

 print "(a)",'------------------ limits options ---------------------'
10 format( &
        ' 0) exit ',/,                 &
        ' 1) use adaptive/fixed limits                  ( ',a,', ',a,' )   ',/,  &
        ' 2) set limits manually ',/,     &
        ' 3) xy limits/radius relative to particle          ( ',i8,' )',/,   &
        ' 4) zoom in/out                                        ( ',f4.2,' )',/, &
        ' 5) apply log/other transformations to columns ',/, &
        ' 6) reset limits for all columns  ',/, &
        ' 7) use subset of data restricted by parameter range     ( ',a,')')
 if (iaction.le.0 .or. iaction.gt.7) then
    print 10,trim(string),trim(string2),itrackpart,zoom,print_logical(anyrangeset())
    call prompt('enter option ',iaction,0,7)
 endif
!
!--limits
!
 select case(iaction)
!------------------------------------------------------------------------
 case(1)

!+ With limits set to adaptive, plot limits are minimum
!+ and maximum of quantities at current timestep.
!+ However, the co-ordinate limits are not adapted
!+ in the case of rendered plots. With fixed limits, the
!+ plot limits retain their default values for all timesteps.

    call prompt('Use adaptive plot limits?',iadapt)
    call prompt('Use adaptive plot limits on coordinate axes?',iadaptcoords)
    call prompt('Adjust limits to aspect ratio of device?',adjustlimitstodevice)
    print "(a)",'adaptive plot limits = '//print_logical(iadapt)// &
                ' on coords = '//print_logical(iadaptcoords)
    !if (nstepsperpage.gt.1 .and. (iadapt .or. iadaptcoords)) then
    !   print*,'WARNING: adaptive limits and multiple steps per page don''t mix'
    !endif
!------------------------------------------------------------------------
 case(2)

!+ Manually sets the plot limits for each column of data

    ipick = 1
    do while (ipick.gt.0)
       ipick = 0
       !write(*,*)
       call prompt('Enter column number to set limits (0=quit)',ipick,0,numplot)
       if (ipick.gt.0) then
          call prompt(trim(label(ipick))//' min ',lim(ipick,1))
          call prompt(trim(label(ipick))//' max ',lim(ipick,2))
          print*,'>> '//trim(label(ipick))//' limits set (min,max) = ',lim(ipick,1),lim(ipick,2)
          if (is_coord(ipick,ndim)) then
             iadaptcoords = .false.
          elseif (ipick.le.numplot) then
             iadapt = .false.
          endif
       endif
    enddo
    return
!------------------------------------------------------------------------
 case(3)

!+ Co-ordinate limits are centred on the selected
!+ particle for all timesteps, with offsets as input by the user.
!+ This effectively gives the `Lagrangian' perspective.

    itrackpartprev = itrackpart
    call prompt('Enter particle to track: ',itrackpart,0)
    print*,'tracking particle ',itrackpart
    if (itrackpart.gt.0) then
       do i=1,ndim
          call prompt('Enter offset for '//trim(label(ix(i)))//'min:', &
                      xminoffset_track(i))
          call prompt('Enter offset for '//trim(label(ix(i)))//'max :', &
                      xmaxoffset_track(i))
       enddo
       if (itrackpart.ne.itrackpartprev .and. iCalcQuantities  &
           .and. irad.gt.0 .and. irad.le.numplot) then
       !--radius calculation is relative to tracked particle
          print "(a)",' recalculating radius relative to tracked particle '
          if (DataIsBuffered) then
             call calc_quantities(1,nsteps)
          else
             call calc_quantities(1,nstepsinfile(ifileopen))
          endif
       endif
    endif
!------------------------------------------------------------------------
 case(4)

!+ Zooms in/out (alternatively do this in interactive mode)

    if (.not.iadapt) then
       call prompt('Enter zoom factor for fixed limits',zoom,0.0)
       do i=1,numplot
          diff = lim(i,2)- lim(i,1)
          mid = 0.5*(lim(i,1) + lim(i,2))
          lim(i,1) = mid - 0.5*zoom*diff
          lim(i,2) = mid + 0.5*zoom*diff
       enddo
    else
       call prompt('Enter scale factor (adaptive limits)',scalemax,0.0)
    endif
!------------------------------------------------------------------------
  case(5)

!+ Applies log, inverse and other transformations to data columns

     index = 1
     do i=1,ntrans
        write(transprompt(index:),"(1x,i1,'=',a,',')") i,trim(transform_label('x',i))
        index = len_trim(transprompt) + 1
     enddo

     ipick = 1
     do while (ipick.gt.0 .and. ipick.le.numplot)
        ipick = 0
        call prompt('Enter column to apply transform (0=quit,-1=all) ',ipick)
        if (ipick.le.numplot .and. ipick.ne.0) then
           print "(a)", trim(transprompt)
           if (ipick.lt.0) then
              ipick = 0
              call prompt('Which transform (or multiple e.g. 321)?',ipick,0)
              itrans(:) = ipick
              ipick = -99
           else
              call prompt('Which transform (or multiple e.g. 321)?',itrans(ipick),0)
           endif
        endif
     enddo
     return
!------------------------------------------------------------------------
  case(6)

!+ Resets plot limits using all data currently in memory
!+ Note that these limits will only apply when fixed limits are used

     if (ivegotdata) then
        if (DataIsBuffered) then
           call set_limits(1,nsteps,1,ndataplots)
        else
           call set_limits(1,nstepsinfile(ifileopen),1,ndataplots)
        endif
     else
        print*,'no data with which to set limits!!'
     endif
!------------------------------------------------------------------------
 case(7)

!+ Plot subset of data by restricting parameter range

    ipick = 1
    do while (ipick.gt.0)
       ipick = 0
       call print_rangeinfo()

       call prompt('Enter column to use to restrict data set (-1=none/unset all,0=quit)',ipick,-1,ndataplots)
       if (ipick.gt.0) then
          print*,'current plot limits for '//trim(label(ipick))//': (min,max) = ',lim(ipick,1),lim(ipick,2)
          call prompt(trim(label(ipick))//' min value ',range(ipick,1))
          call prompt(trim(label(ipick))//' max value ',range(ipick,2),range(ipick,1))
          if (.not.rangeset(ipick)) then
             print*,'>> min=max: no restriction set'
          endif
       elseif (ipick.eq.-1) then
          print "(a)",'>> removing all range restrictions on data set'
          range(:,:) = 0.
       endif
       write(*,*)
    enddo
    return
  end select

 return
end subroutine submenu_limits

end module settings_limits
