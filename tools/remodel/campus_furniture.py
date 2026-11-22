"""Furniture in the existing game's seat, tabletop and bunk coordinate frames."""
from math import cos, pi, sin

from campus_mesh import Part

STEEL, CHROME, FOOT, WOOD = '839094', 'b5bec0', '454d4c', 'c9aa7e'
BLUE, YELLOW = '56829c', 'd7af48'


def plate(p, x,y,z, w,h,d, radius, top, edge):
    outline=[]
    for cx,cz,start in [(w/2-radius,d/2-radius,0),(-w/2+radius,d/2-radius,90),
                        (-w/2+radius,-d/2+radius,180),(w/2-radius,-d/2+radius,270)]:
        for k in range(4):
            a=(start+30*k)*pi/180
            outline.append((x+cx+radius*cos(a),z+cz+radius*sin(a)))
    lower=[(xx,y-h,zz) for xx,zz in outline]
    upper=[(xx,y,zz) for xx,zz in outline]
    p.face(upper[::-1],top)
    p.face(lower,edge)
    for i in range(len(upper)):
        j=(i+1)%len(upper)
        p.face([lower[i],upper[i],upper[j],lower[j]],edge)


def chair(tint):
    p=Part()
    for x in (-.145,.145):
        for z in (-.138,.14):
            p.tube((x*1.15,.017,z*1.19),(x,.417,z),.014,.013,CHROME,8)
            p.disk(x*1.15,0,z*1.19,.021,.027,FOOT,sides=8)
        p.tube((x,.396,.115),(x*.94,.776,.198),.012,.012,STEEL,8)
    plate(p,0,.445,0,.385,.041,.37,.065,tint,tint)
    # A moulded back with a grip slot and a gentle transverse curve.
    def point(x,y):
        return (x,y,.147+.14*(y-.5)+.026*(1-(x/.19)**2))
    cols=(-.19,-.138,-.077,.077,.138,.19)
    for i,(lo,hi) in enumerate(zip(cols,cols[1:])):
        for j,(a,b) in enumerate(((.52,.70),(.70,.748),(.748,.81))):
            if i==2 and j==1: continue
            taper=.024 if i in (0,4) else 0
            face=[point(lo,a),point(hi,a),point(hi,b-(taper if i==4 else 0)),point(lo,b-(taper if i==0 else 0))]
            back=[(x,y,z+.020) for x,y,z in face]
            p.face(face[::-1],tint)
            p.face(back,tint)
            for k in range(4):
                n=(k+1)%4
                p.face([face[k],face[n],back[n],back[k]],tint)
    return p


def desk():
    p=Part()
    plate(p,0,.761,0,.78,.037,.51,.035,'dfcda5','aa8c65')
    for x in (-.31,.31):
        p.block((x,.58,0),(.032,.28,.38),STEEL)
        for z in (-.18,.18):
            p.tube((x,.025,z),(x,.735,z),.019,.021,CHROME,8)
            p.disk(x,.003,z,.024,.032,FOOT,sides=8)
    p.block((0,.595,-.19),(.62,.20,.025),'bbc3bc')
    p.block((0,.49,-.01),(.63,.025,.38),'b1b9b4')
    return p


def lab(chemistry):
    p=Part()
    p.block((0,.435,-.035),(.81,.78,.59),'c5d5cc')
    p.block((0,.057,-.035),(.75,.07,.52),'52615c')
    for x in (-.20,.20):
        p.block((x,.44,.265),(.382,.71,.021),'b3c6ba')
        p.block((x+.125,.69,.285),(.035,.10,.025),STEEL)
    plate(p,0,.92,0,.93,.065,.75,.027,'417967','2c5c50')
    # Circular blue laboratory stool on the same footprint as the original.
    xx,zz=.02,.46
    p.disk(xx,.415,zz,.146,.036,'548aa6',sides=16)
    p.disk(xx,.395,zz,.137,.020,'37576a',sides=16)
    for dx,dz in ((-.085,-.076),(.085,-.076),(0,.096)):
        p.tube((xx+dx*1.25,.015,zz+dz*1.25),(xx+dx,.397,zz+dz),.012,.012,STEEL,6)
    if chemistry:
        plate(p,-.21,.926,.015,.29,.013,.24,.036,'a1b4b1',CHROME)
        plate(p,-.21,.93,.015,.24,.006,.19,.026,'435955','778a85')
        p.tube((-.34,.92,-.16),(-.34,1.16,-.16),.014,.014,CHROME,8)
        p.tube((-.34,1.16,-.16),(-.22,1.16,-.10),.014,.014,CHROME,8)
        p.tube((-.22,1.16,-.10),(-.22,1.10,-.10),.013,.013,CHROME,8)
        p.block((.21,.96,-.23),(.32,.08,.16),'e0d8c8')
        for x in (.13,.23,.30):
            p.disk(x,.997,-.23,.025,.112,'8cadad',sides=8)
    else:
        p.block((-.17,.985,-.13),(.32,.13,.22),'e3dcca')
        p.block((-.17,1.007,-.011),(.19,.064,.009),'414f4d')
        for x,tint in ((-.29,'a94d3a'),(-.08,FOOT)):
            p.disk(x,1.05,-.13,.019,.026,tint,sides=8)
        p.disk(.24,.92,.05,.105,.032,STEEL)
        p.tube((.24,.952,.05),(.24,1.28,.05),.009,.009,CHROME,8)
        p.tube((.24,1.22,.05),(.13,1.22,.05),.008,.008,CHROME,8)
    return p


def extractor():
    p=Part()
    # The flared mouth is hollow. Its dark interior is visible at player eye height.
    p.block((0,2.93,-.20),(.30,.13,.30),'e8e6dd')
    elbow=(0,2.36,-.21)
    end=(.21,1.94,-.08)
    for a,b in [((0,2.90,-.20),elbow),(elbow,end)]:
        p.tube(a,b,.047,.047,'e3e1d6')
    for x,y,z in (elbow,end):
        p.tube((x-.059,y,z),(x+.059,y,z),.078,.078,'a3a6a0',12)
    p.tube(end,(.21,1.78,-.08),.065,.176,'e5e2d4',20)
    p.disk(.21,1.774,-.08,.15,.008,'7a837d',sides=20)
    return p


def bunk():
    p=Part()
    for x in (-.405,.405):
        for z in (-.667,.667):
            p.tube((x,.014,z),(x,1.845,z),.024,.024,'98a6a3',10)
            p.disk(x,1.845,z,.026,.02,'758280',sides=8)
    for y in (.30,1.33):
        for x in (-.402,.402):
            p.block((x,y,0),(.036,.084,1.37),'83918e')
        for z in (-.659,.659):
            p.block((0,y,z),(.83,.078,.037),'83918e')
        for i in range(8):
            p.block((0,y+.035,(i-3.5)*.16),(.785,.044,.155),('c6a16e','bf996b','d0ab79')[i%3])
        plate(p,-.008,y+.079,-.18,.71,.022,.81,.035,'b5c3b4','8fa597')
        plate(p,-.006,y+.128,-.46,.50,.056,.22,.045,'e7e3ce','d4cfba')
    for x in (-.41,.41):
        for y in (1.51,1.68):
            p.tube((x,y,-.64),(x,y,.22),.015,.015,CHROME,8)
        p.tube((x,1.37,.22),(x,1.68,.22),.016,.016,CHROME,8)
    for x in (.11,.37):
        p.tube((x,.02,.69),(x,1.69,.69),.017,.017,CHROME,8)
    for y in (.24,.50,.76,1.02,1.28):
        p.tube((.11,y,.69),(.37,y,.69),.014,.014,CHROME,8)
    return p


def canteen():
    p=Part()
    plate(p,0,.758,0,.86,.04,.80,.04,'e3e5d8','9cafae')
    for z in (-.52,.52):
        plate(p,0,.445,z,.78,.043,.257,.049,'acc8ca','819fa3')
        for x in (-.28,.28):
            p.block((x,.223,z),(.027,.403,.03),STEEL)
            p.block((x,.065,z*.72),(.032,.038,.34),STEEL)
    for x in (-.28,.28):
        for z in (-.28,.28):
            p.block((x,.367,z),(.036,.70,.036),CHROME)
    return p


def serving_bay():
    p=Part()
    for x in (-.455,.455):
        p.block((x,1.57,-.14),(.052,1.18,.055),CHROME)
    p.block((0,2.14,-.14),(.965,.23,.13),'a4cbd1')
    p.block((0,2.265,-.14),(.985,.025,.15),'ecede1')
    p.block((0,1.02,.15),(.965,.047,.24),CHROME)
    return p


def workstation():
    p=Part()
    # Felt dividers fitted to the back and sides of the existing computer desks.
    for x in (-.46,.46):
        p.block((x,1.06,-.03),(.032,.51,.58),'b8c4bd')
        p.block((x,1.325,-.03),(.038,.025,.59),'6c8d92')
    p.block((0,1.10,-.31),(.92,.59,.029),'c6d1cb')
    p.block((0,1.40,-.31),(.95,.024,.040),'62858a')
    return p


def furniture():
    return {'Desk':desk(), 'BlueChair':chair(BLUE), 'LanguageChair':chair(YELLOW),
            'PhysicsBench':lab(False), 'ChemistryBench':lab(True), 'Extractor':extractor(),
            'Bunk':bunk(), 'CanteenTable':canteen(), 'ServingBay':serving_bay(), 'Workstation':workstation()}
