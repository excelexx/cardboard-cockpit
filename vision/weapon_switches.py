"""Debounced two-sided ArUco switches; same detector, no held gestures required."""
class WeaponSwitches:
    IDS = {31: ('primary', True), 32: ('primary', False), 41: ('salvo', True), 42: ('salvo', False)}
    def __init__(self):
        self.configured = False
        self.state = {name: dict(value=False, candidate=None, since=0.0, seen=-100.0, confidence=0.0) for name in ('primary', 'salvo')}
    def step(self, observations, now):
        for name, state in self.state.items():
            observation = observations.get(name)
            if observation is not None:
                value, confidence = observation
                self.configured = True
                if state['candidate'] != value:
                    state['candidate'], state['since'] = value, now
                if now-state['since'] >= .09:
                    state['value'] = bool(value)
                state['seen'], state['confidence'] = now, confidence
            if now-state['seen'] > .8:
                state['value'], state['confidence'], state['candidate'] = False, 0.0, None
        return {name: state['value'] for name,state in self.state.items()} | {name+'_confidence': state['confidence'] for name,state in self.state.items()}
