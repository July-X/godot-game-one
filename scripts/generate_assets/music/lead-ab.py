from argparse import ArgumentParser
from pathlib import Path

parser = ArgumentParser(description="Render the original soft-lead loops.")
parser.add_argument("output", type=Path, help="directory for rendered WAV files")
parser.add_argument("--effects-dir", type=Path, help="optional captured Godot SFX for the lead comparison")
args = parser.parse_args()
args.output.mkdir(parents=True, exist_ok=True)

a=Path(__file__).with_name('compose.py').read_text().split('flight=song();')[0]
a=a.replace('def song(boss=False):','def song(boss=False, smooth=False):').replace('m=np.zeros((N,2)); drums=', 'm=np.zeros((N,2)); ld=np.zeros((N,2)); drums=')
a=a.replace("v=voice(n,l*B,'lead')","v=smoother(n,l*B) if smooth else voice(n,l*B,'lead')")
a=a.replace('add(m,(o+p)*B,v*','add(ld,(o+p)*B,v*').replace('add(m,(o+p)*B+.76*B,v*.028','add(ld,(o+p)*B+.76*B,v*(.012 if smooth else .028)').replace('add(m,(o+p)*B+1.23*B,v*.014','add(ld,(o+p)*B+1.23*B,v*(.006 if smooth else .014)').replace('return m\ndef save','return m,ld\ndef save')
ns={}
exec(compile(a,'compose.py','exec'),ns)
import numpy as np, wave
R=ns['R']; B=ns['B']; rms=ns['rms']; snd=ns['sine']; t0=ns['ts']; gate=ns['gate']; hz=ns['hz']
def smoother(note,s):
    s+=.036
    t=t0(s); f=hz(note)
    v=snd(f,t)+.16*snd(f*2,t)+.072*snd(f*3,t)+.013*snd(f*5,t)
    v+=.16*snd(f*1.003,t)+.13*snd(f*.997,t)
    return v*(gate(t,s,.042,.095)**1.32)*(.89+.11*np.exp(-t*8))
ns['smoother']=smoother
def make(boss,smooth):
    ns['rng']=np.random.default_rng(61412)
    return ns['song'](boss,smooth)
a0,al=make(False,False);b0,bl=make(False,True)
at,alt=make(True,False);bt,blt=make(True,True)
assert np.array_equal(a0,b0) and np.array_equal(at,bt)
bl*=rms(al)/rms(bl);blt*=rms(alt)/rms(blt)
ns['save'](str(args.output / 'cruise-softlead-loop.wav'),(b0+bl)*.54)
ns['save'](str(args.output / 'boss-softlead-loop.wav'),(bt+blt)*.54)
if args.effects_dir is None:
    raise SystemExit(0)
data=args.effects_dir
def sfx(k):
    with wave.open(str(data/(k+'.wav'))) as w:
        assert w.getframerate()==R and w.getnchannels()==1
        return np.frombuffer(w.readframes(w.getnframes()),'<i2').astype(float)/32768
N=round(16*B*R)
mix=np.zeros((N,2))
for key,seq,vol in [('shoot',[1.18,1.39,1.60,4.51,4.68,4.89,5.87,6.11],.85),('hit',[1.52,2.06,4.80,5.25,6.06],.9),('enemy_death',[5.06],.8)]:
    v=sfx(key)*vol
    for sec in seq:
        i=round(sec*R);mix[i:i+len(v)]+=v[:,None]
# First bar is clean in both sections; then identical capture of existing Godot SFX.
p=ns['win']((a0[:N]+al[:N])*.54+mix)
q=ns['win']((b0[:N]+bl[:N])*.54+mix)
gap=np.zeros((round(.65*R),2))
ns['save'](str(args.output / 'lead-ab.wav'),np.vstack((p,gap,q)))
db=lambda x:20*np.log10(x)
v1=ns['voice'](74,.30*B,'lead');v2=smoother(74,.30*B)
print('clip duration',round((len(p)*2+len(gap))/R,2),'B begins',round((len(p)+len(gap))/R,2))
print('same accompaniment bit-for-bit; same mono SFX gain/time; lead matched',round(db(rms(al)),2),round(db(rms(bl)),2))
print('D5 first 35ms, vs own total RMS:',round(db(rms(v1[:round(.035*R)])/rms(v1)),2),round(db(rms(v2[:round(.035*R)])/rms(v2)),2))
print('A/B mix peak',round(db(abs(p).max()),2),round(db(abs(q).max()),2))
