"""Versioned, bounded badge instrument snapshots; RGB frames never cross BLE."""
import binascii,math,struct
HEADER=struct.Struct('<2sBBBBHhhHHiIHHB12sHB')
CONTACT=struct.Struct('<hhBB')
MAX_CONTACTS=12

def number(data,key,lo,hi):
 value=data.get(key)
 if isinstance(value,bool) or not isinstance(value,(int,float)) or not math.isfinite(value) or not lo<=value<=hi:
  raise ValueError('Invalid '+key)
 return value

def validate(data):
 if not isinstance(data,dict) or data.get('kind')!='instrument' or type(data.get('version')) is not int or data.get('version')!=1:raise ValueError('Unknown snapshot')
 for k,lo,hi in [('mode',0,4),('flags',0,255),('roll',-180,180),('pitch',-90,90),('heading',0,360),('speed',0,2000),('altitude',-2000,1000000),('score',0,4294967295),('kills',0,65535),('pilot',1,9999),('landing',0,4),('range',0,65535)]:
  v=number(data,k,lo,hi)
  if k in ('mode','flags','score','kills','pilot','landing') and int(v)!=v:raise ValueError('Fractional '+k)
 name=data.get('name')
 if not isinstance(name,str) or not 1<=len(name)<=12 or any(c not in 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 -' for c in name):raise ValueError('Invalid pilot name')
 contacts=data.get('contacts')
 if not isinstance(contacts,list) or len(contacts)>MAX_CONTACTS:raise ValueError('Too many contacts')
 for c in contacts:
  if not isinstance(c,dict):raise ValueError('Bad contact')
  number(c,'x',-32767,32767);number(c,'y',-32767,32767)
  if number(c,'kind',1,4) not in (1,2,3,4):raise ValueError('Bad kind')
  if number(c,'selected',0,1) not in (0,1):raise ValueError('Bad selection')
 return data

def encode(data,sequence):
 d=validate(data)
 b=HEADER.pack(b'SI',1,int(d['mode']),int(d['flags']),len(d['contacts']),sequence&65535,
  round(d['roll']*100),round(d['pitch']*100),round(d['heading']*100),round(d['speed']),round(d['altitude']),
  int(d['score']),int(d['kills']),int(d['pilot']),int(d['landing']),d['name'].encode().ljust(12,b'\0'),round(d['range']),0)
 for c in d['contacts']:b+=CONTACT.pack(round(c['x']),round(c['y']),int(c['kind']),int(c['selected']))
 return b+struct.pack('<H',binascii.crc_hqx(b,0xffff))

def fragments(packet,sequence,mtu_payload):
 size=max(1,min(180,int(mtu_payload))-4)
 if not 46<=len(packet)<=118:raise ValueError('Bad frame length')
 return [bytes([0xa7,sequence&255,off,len(packet)])+packet[off:off+size] for off in range(0,len(packet),size)]

def disconnected():
 return dict(kind='instrument',version=1,mode=4,flags=0,roll=0,pitch=0,heading=0,speed=0,altitude=0,score=0,kills=0,pilot=1,landing=0,name='PILOT',range=0,contacts=[])
