import numpy as np, wave
from pathlib import Path
R=44100; BPM=132; B=60/BPM; N=round(32*B*R); tw=2*np.pi
rng=np.random.default_rng(61412)
def ts(s):return np.arange(max(0,round(s*R)))/R
def hz(n):return 440*2**((n-69)/12)
def gate(t,s,a,d):return np.clip(t/a,0,1)*np.clip((s-t)/d,0,1)
def add(m,t,s,pan=0):
    ix=(round(t*R)+np.arange(len(s)))%len(m)
    m[ix,0]+=s*np.sqrt((1-pan)/2); m[ix,1]+=s*np.sqrt((1+pan)/2)
def sine(f,t):return np.sin(tw*f*t)
def voice(note,s,kind='lead'):
    t=ts(s);f=hz(note)
    if kind=='lead':
        v=np.sin(tw*f*t+.05*np.sin(tw*5.6*t))+.24*sine(f*2,t)+.29*sine(f*3,t)+.09*sine(f*5,t)
        v+=.12*sine(f*1.006,t)
        return v*gate(t,s,.012,.062)*(.70+.30*np.exp(-t*6))
    if kind=='bass':
        return (sine(f,t)+.24*sine(f*2,t)+.18*sine(f*3,t))*gate(t,s,.009,.037)*(.52+.48*np.exp(-t*8))
    if kind=='counter':
        return (sine(f,t)+.21*sine(f*2.01,t)+.12*sine(f*3,t))*gate(t,s,.013,.11)*np.exp(-t*3.9)
    return (sine(f,t)+.31*sine(f*1.005,t)+.16*sine(f*2,t))*gate(t,s,.51,.72)
def drum(k):
    s={'kick':.22,'snare':.17,'hat':.081,'tom':.25}[k];t=ts(s)
    n=rng.uniform(-1,1,len(t))
    if k=='kick':v=np.sin(tw*(50*t+1.52*(1-np.exp(-t*29))))*np.exp(-t*18)+.13*n*np.exp(-t*85)
    if k=='tom':v=np.sin(tw*(88*t+1.4*(1-np.exp(-t*18))))*np.exp(-t*13)
    if k=='snare':v=(n*.9+sin_bend(t)*.41)*np.exp(-t*24)
    if k=='hat':v=(n-np.roll(n,1))*.53*np.exp(-t*57)
    return v*gate(t,s,.002,.025)
def sin_bend(t):return np.sin(tw*(154*t+1.25*(1-np.exp(-t*19))))
# D minor. The four-note hook is D, F, G, A, with a rest between the answer and next cell.
# Positions are in quarter beats. Melody is written, not derived from a reference recording.
H=[
[(0,74,.30),(.5,77,.23),(1.25,79,.24),(1.5,81,.76),(2.75,79,.23),(3,77,.54)],
[(0,74,.26),(.5,77,.23),(1.25,81,.23),(1.5,84,1.0),(3,81,.24),(3.5,79,.34)],
[(0,77,.3),(.5,79,.26),(1.25,81,.23),(1.5,86,.82),(2.75,84,.22),(3,81,.6)],
[(.25,79,.26),(.75,77,.31),(1.5,74,1.04),(3.5,72,.25)],
[(0,74,.30),(.5,77,.23),(1.25,79,.24),(1.5,81,.79),(2.75,84,.23),(3,86,.66)],
[(0,84,.27),(.5,81,.29),(1.25,79,.24),(1.5,77,.88),(3,79,.48)],
[(0,81,.26),(.5,82,.25),(1.25,81,.25),(1.5,79,.64),(2.5,76,.25),(3,73,.55)],
[(0,74,1.25),(1.75,69,.3),(2.25,72,.32),(3,73,.38)]
]
BOSS=[
H[0],[(0,74,.30),(.5,77,.23),(1.25,79,.24),(1.5,82,.85),(3.25,81,.46)],
[(0,74,.30),(.5,77,.23),(1.25,79,.24),(1.5,81,.78),(3,76,.41)],
[(0,77,.36),(.75,75,.25),(1.5,74,1.34)],
H[0],[(0,74,.30),(.5,77,.23),(1.25,79,.24),(1.5,82,.85),(3,84,.44)],
[(0,81,.30),(.5,79,.31),(1.25,77,.31),(1.75,76,.70),(3,73,.46)],
[(0,74,1.2),(2.50,72,.31),(3,73,.64)]
]
def song(boss=False):
    m=np.zeros((N,2)); drums={k:drum(k) for k in ['kick','snare','hat','tom']}
    chords=([[38,45,50,53],[38,46,50,53],[39,46,50,55],[38,45,51,57],[38,45,50,53],[38,46,50,55],[33,45,49,55],[38,45,50,53]] if boss else
    [[38,45,50,53],[38,45,53,57],[34,46,53,57],[36,48,55,58],[38,45,50,53],[41,48,53,57],[33,45,49,55],[38,45,50,53]])
    for j,ch in enumerate(chords):
        o=j*4
        for p,n,l in (BOSS if boss else H)[j]:
            if boss:n-=12
            v=voice(n,l*B,'lead')
            add(m,(o+p)*B,v*(.124 if boss else .147),-.05)
            add(m,(o+p)*B+.76*B,v*.028,.62)
            add(m,(o+p)*B+1.23*B,v*.014,-.69)
        for i,n in enumerate(ch[1:]):
            add(m,(o-.54)*B,voice(n+12,4.75*B,'pad')*(.028 if boss else .036),(-.67,0,.68)[i])
        basspat=[(0,0,.4),(.5,0,.33),(1.25,7,.23),(1.75,0,.28),(2.5,0,.36),(3,12,.36),(3.5,0,.31)]
        if boss:basspat=[(0,0,.72),(.75,0,.24),(1.5,0,.32),(2.5,7,.26),(3,0,.38),(3.5,1 if j in (1,3,5) else 0,.33)]
        for p,n,l in basspat:
            add(m,(o+p)*B,voice(ch[0]+n,l*B,'bass')*(.175 if boss else .137))
        if not boss and (j==1 or j==3 or j==5 or j==7):
            for p,n in [(2.75,ch[1]+24),(3.25,ch[2]+24)]:
                add(m,(o+p)*B,voice(n,.48*B,'counter')*.066,.45)
        for p in ([0,1.5,2.75,3.5] if boss else [0,1.5,2.5]):
            add(m,(o+p)*B,drums['kick']*(.23 if boss else .176))
        for p in ([2] if boss else [1,3]):add(m,(o+p)*B,drums['snare']*.17,-.10)
        for p in (1.25,3.25) if boss else (.5,1.5,2.5,3.5):
            add(m,(o+p)*B,drums['hat']*(.029 if boss else .046),.27)
        if j in (3,7):
            for p,a in [(3.25,.072),(3.50,.095),(3.75,.107)]:
                add(m,(o+p)*B,drums['tom']*a,-.28)
    return m
def save(p,x):
    with wave.open(p,'wb') as a:
        a.setparams((2,2,R,0,'NONE','not compressed'))
        a.writeframes(np.int16(np.clip(x,-.999,.999)*32767).tobytes())
def win(m):
    t=ts(len(m)/R);return m*(np.minimum(t/.015,1)*np.minimum((len(m)/R-t)/.18,1))[:,None]
def rms(m):return np.sqrt(np.mean(m*m))
flight=song(); boss=song(True); boss*=rms(flight)/rms(boss)*.97
clip=np.vstack((win(flight),np.zeros((round(.45*R),2)),win(boss)))
clip*= .83/np.max(np.abs(clip))
save('arcade-theme.wav',clip)
# Offline check using the exact generated effects from the Godot source.
W=Path('/tmp/sbh-ui-draft/audio-engine')
def read(n):
    with wave.open(str(W/(n+'.wav'))) as w:
        return np.frombuffer(w.readframes(w.getnframes()),dtype='<i2').astype(float)/32768
if W.exists():
    beat=win(boss)*.50; fx=np.zeros_like(beat); t=ts(len(beat)/R); g=t*0+1
    for i in (1.1,1.27,1.44,2.8,3.0,3.2,5.00,5.19,5.4,6.8,7.0,9.5,9.7,10.4,12.1,12.3):
        a=read('shoot')*1.18; p=round(i*R); fx[p:p+len(a)]+=a[:,None]
    for i,k in [(1.45,'hit'),(3.29,'hit'),(4.0,'boss_warning'),(5.46,'enemy_death'),(7.35,'player_hurt'),(10.8,'shield_break'),(12.5,'hit')]:
        a=read(k); p=round(i*R); fx[p:p+len(a)]+=a[:,None]
        if k in ('boss_warning','player_hurt'):
            g=np.minimum(g,1-.43*np.clip((t-i+.035)/.035,0,1)*np.exp(-np.maximum(t-i,0)/.30))
    mix=beat*g[:,None]+fx
    print('cue-mix peak',round(20*np.log10(abs(mix).max()),1),'dBFS')
    save('arcade-cue-preview.wav',mix)
print('stage',round(N/R,3),'sec each; clip',round(len(clip)/R,3),'sec', 'peak',round(20*np.log10(abs(clip).max()),1),'dBFS', 'rms',round(20*np.log10(rms(clip)),1),'dBFS')
