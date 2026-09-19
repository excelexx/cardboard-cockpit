"""Loop the included GPL FlightGear cannon recording; preserve original source."""
import wave, numpy as np
from pathlib import Path
p=Path(__file__).resolve().parents[1]/'simulator/assets/audio'
with wave.open(str(p/'cannon.wav')) as w:
    rate=w.getframerate();channels=w.getnchannels();width=w.getsampwidth()
    assert width==2
    samples=np.frombuffer(w.readframes(w.getnframes()),dtype='<i2').reshape(-1,channels).astype(np.float64)/32768
# Use the sustained body; circular crossfade removes the waveform seam.
a=samples[int(.16*rate):int(.96*rate)].copy();n=int(.035*rate)
t=np.linspace(0,1,n)[:,None]
a[-n:]=a[-n:]*(1-t)+a[:n]*t;a=a[n:]
a*=.82/max(np.max(np.abs(a)),.01)
with wave.open(str(p/'gatling_loop.wav'),'wb') as w:
    w.setnchannels(channels);w.setsampwidth(2);w.setframerate(rate);w.writeframes((a*32767).astype('<i2').tobytes())
print('GATLING_LOOP',len(a)/rate,rate,channels)
