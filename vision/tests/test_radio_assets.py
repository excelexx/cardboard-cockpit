"""Validate the shipped, offline radio recordings without any network or TTS API."""
import hashlib
import json
from pathlib import Path
import unittest
import wave
import numpy as np

RADIO = Path(__file__).resolve().parents[2] / 'simulator/assets/audio/radio'

class RadioAssetTests(unittest.TestCase):
    def test_shipped_cues_match_manifest_and_do_not_clip(self):
        manifest = json.loads((RADIO / 'manifest.json').read_text())
        self.assertEqual(manifest['license'], 'CC0')
        self.assertIn('licensed', manifest['provider'])
        self.assertEqual(len(manifest['cues']), 20)
        for name, cue in manifest['cues'].items():
            with self.subTest(cue=name):
                path = RADIO / cue['file']
                self.assertEqual(hashlib.sha256(path.read_bytes()).hexdigest(), cue['sha256'])
                with wave.open(str(path), 'rb') as audio:
                    self.assertEqual(audio.getnchannels(), 1)
                    self.assertEqual(audio.getsampwidth(), 2)
                    self.assertEqual(audio.getframerate(), 22050)
                    self.assertAlmostEqual(audio.getnframes()/audio.getframerate(), cue['duration'], places=5)
                    samples = np.frombuffer(audio.readframes(audio.getnframes()), dtype='<i2').astype(np.int32)
                    self.assertLess(np.max(np.abs(samples)), 32000)
                    self.assertGreater(np.max(np.abs(samples)), 1000)
                for source in cue['source_files']:
                    self.assertTrue((RADIO / 'source' / source).is_file())
