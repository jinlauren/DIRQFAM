!======================================================================!

      module ddpc1_scan

!======================================================================!
      implicit none;

      logical          :: ddpc1_scan_loaded = .false.;
      double precision :: ddpc1_scan_b_tv   =  1.8360d0;
      double precision :: ddpc1_scan_d_tv   =  0.6403d0;

      contains

          subroutine read_ddpc1_scan()
              implicit none;
              integer            :: unit;
              integer            :: ios;
              character(len=256) :: line;

              ddpc1_scan_loaded = .false.;

              open( status='old' , action='read' , form='formatted' , &
                    newunit=unit , file='ddpc1_scan.in' , iostat=ios );

              if( ios /= 0 ) return;

              do
                  read(unit,'(a)',iostat=ios) line;
                  if( ios /= 0 ) exit;
                  line = adjustl(line);
                  if( len_trim(line)==0 ) cycle;
                  if( line(1:1)=='#' .or. line(1:1)=='!' ) cycle;

                  read(line,*,iostat=ios) ddpc1_scan_b_tv, ddpc1_scan_d_tv;
                  if( ios /= 0 ) stop 'Could not read b_TV and d_TV from ddpc1_scan.in.';

                  ddpc1_scan_loaded = .true.;
                  exit;
              end do

              close(unit);

          return;
          end subroutine read_ddpc1_scan

      end module ddpc1_scan
