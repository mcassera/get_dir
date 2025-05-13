10    bload "get_dir.bin",$7F00
15    buffer=$7700:buffloc=$7FBB
20    directory(buffer,0,"")
30    for n=buffer to peekw(buffloc)
40    cprint chr$(peek(n));
50    if peek(n)=0 then print 
60    next 
70    print 
80    end 
1000  proc directory(loc,len,path$)
1010  buffloc=$7FBB
1020  pathlength=$7FBD
1030  pathloc=$7FBE
1040  getdir=$7F00
1050  pokew buffloc,loc
1060  poke pathlength,len
1070  for n=0 to len
1080  poke pathloc+n,asc(mid$(path$,n+1,1))
1090  next 
1100  call getdir
1120  endproc 
