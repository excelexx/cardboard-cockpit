#!/usr/bin/env python3
"""Rebuild licensed Kenney radio cues and short original squelch/static accents.
Source: Kenney Voiceover Pack, CC0; see assets/audio/radio/LICENSE.txt.
Requires ffmpeg plus numpy from vision/requirements.txt. Never calls a paid API.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import wave
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'simulator/assets/audio/radio'
RATE = 22050
CUES = {
 'intro': ('CONTROL', 'Ready? Go!', ['Male/ready.ogg','Male/go.ogg'], 2, 10),
 'target_locked': ('PILOT','Target engaged.',['Female/war_target_engaged.ogg'],0,16),
 'target_down': ('PILOT','Target destroyed.',['Female/war_target_destroyed.ogg'],0,10),
 'target_down_alt': ('CONTROL','Target destroyed.',['Male/war_target_destroyed.ogg'],0,10),
 'warning': ('CONTROL','Look out!',['Male/war_look_out.ogg'],3,8),
 'reload': ('PILOT','Reloading.',['Female/war_reloading.ogg'],1,12),
 'cleared': ('CONTROL','Ready? Go!',['Male/ready.ogg','Male/go.ogg'],1,15),
 'checkpoint': ('CONTROL','Objective achieved.',['Male/objective_achieved.ogg'],0,14),
 'approach': ('CONTROL','Hold.',['Male/hold.ogg'],1,25),
 'touchdown': ('CONTROL','Objective achieved.',['Female/objective_achieved.ogg'],2,15),
 'landed': ('CONTROL','Mission completed.',['Male/mission_completed.ogg'],2,15),
 'success': ('CONTROL','Mission completed.',['Male/mission_completed.ogg'],3,15),
 'failure': ('CONTROL','Mission failed.',['Male/mission_failed.ogg'],3,15),
 'eject': ('CONTROL','Look out!',['Female/war_look_out.ogg'],3,15),
 'countdown': ('CONTROL','Three. Two. One.',['Male/3.ogg','Male/2.ogg','Male/1.ogg'],2,30),
}

def decode(path):
    p = subprocess.run(['ffmpeg','-v','error','-i',str(path),'-ac','1','-ar',str(RATE),'-f','f32le','-'],check=True,stdout=subprocess.PIPE)
    return np.frombuffer(p.stdout,dtype='<f4').copy()

def write_wav(path, data):
    with wave.open(str(path),'wb') as out:
        out.setnchannels(1); out.setsampwidth(2); out.setframerate(RATE)
        out.writeframes((np.clip(data,-.98,.98)*32767).astype('<i2').tobytes())

def noise(seconds, seed, gain):
    rng=np.random.default_rng(seed); n=int(round(seconds*RATE))
    data=rng.normal(0,1,n)
    spec=np.fft.rfft(data); freq=np.fft.rfftfreq(n,1/RATE)
    spec[(freq<350)|(freq>5000)]=0
    data=np.fft.irfft(spec,n); data/=max(np.max(np.abs(data)),1e-9)
    envelope=np.minimum(np.arange(n)/(RATE*.012),(n-1-np.arange(n))/(RATE*.018)).clip(0,1)
    return data*envelope*gain

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--source',type=Path,required=True);args=parser.parse_args()
    OUT.mkdir(parents=True,exist_ok=True); (OUT/'source').mkdir(exist_ok=True)
    shutil.copy2(args.source/'License.txt',OUT/'LICENSE.txt')
    shutil.copy2(args.source/'Credits.txt',OUT/'ACTORS.txt')
    manifest={'source':'https://kenney.nl/assets/voiceover-pack','license':'CC0','provider':'licensed recordings; not ElevenLabs','cues':{}}
    for index,(name,(speaker,text,parts,priority,cooldown)) in enumerate(CUES.items()):
        samples=[]
        for part in parts:
            source=args.source/part; target=OUT/'source'/part;target.parent.mkdir(exist_ok=True);shutil.copy2(source,target)
            samples.extend([decode(source),np.zeros(int(RATE*.12))])
        joined=np.concatenate(samples)
        raw=OUT/(name+'.raw.wav');write_wav(raw,joined)
        filtered=subprocess.run(['ffmpeg','-v','error','-i',str(raw),'-af','highpass=f=280,lowpass=f=3400,acompressor=threshold=0.12:ratio=3:attack=5:release=80','-f','f32le','-'],check=True,stdout=subprocess.PIPE)
        voice=np.frombuffer(filtered.stdout,dtype='<f4').copy();raw.unlink()
        voice*=.78/max(np.max(np.abs(voice)),1e-9)
        hiss=noise(len(voice)/RATE,225+index,.014)
        final=np.concatenate([noise(.10,index,.15),np.zeros(int(RATE*.035)),voice+hiss,noise(.09,index+900,.09)])
        target=OUT/(name+'.wav');write_wav(target,final)
        manifest['cues'][name]={'speaker':speaker,'text':text,'file':name+'.wav','duration':len(final)/RATE,'priority':priority,'cooldown':cooldown,'sha256':hashlib.sha256(target.read_bytes()).hexdigest(),'source_files':parts}
    (OUT/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
    write_wav(OUT/'squelch.wav',noise(.18,180,.14))
    print('Built',len(CUES),'radio cues from licensed recordings.')
if __name__=='__main__': main()
