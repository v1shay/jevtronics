import React, { useEffect, useMemo, useState } from 'react';
import { createRoot } from 'react-dom/client';
import { BorderBeam } from 'border-beam';
import { ThinkingOrb } from 'thinking-orbs';
import { Liquid } from 'liquid-gooey';
import { VoiceBeam } from 'voice-glow';
import { MetalFx, MetalText, MetalBadge } from 'metal-fx';
import { ImageGeneration } from 'img-fx';
import './styles.css';

const INITIAL = {
  phase: 'idle',
  transcript: '',
  detail: 'Hold Command to speak',
  level: 0,
  expanded: false,
  tool: '',
  confidence: 0,
  needsConfirmation: false,
};

const PHASE_COPY = {
  idle: 'Ready',
  listening: 'Listening',
  routing: 'Deciding',
  executing: 'Working',
  success: 'Done',
  error: 'Couldn’t complete',
  confirm: 'Confirm action',
};

function send(action, payload = {}) {
  const bridge = window.webkit?.messageHandlers?.notch;
  if (bridge) bridge.postMessage({ action, ...payload });
}

function Notch() {
  const [state, setState] = useState(INITIAL);

  useEffect(() => {
    window.notch = {
      setState(next) {
        setState(current => ({ ...current, ...next }));
      },
      reset() { setState(INITIAL); },
    };
    send('ready');
    return () => { delete window.notch; };
  }, []);

  const busy = ['routing', 'executing'].includes(state.phase);
  const active = state.phase !== 'idle';
  const orbState = useMemo(() => ({
    listening: 'listening', routing: 'searching', executing: 'working',
    success: 'breathing', error: 'shaping', confirm: 'connecting', idle: 'breathing',
  }[state.phase] || 'breathing'), [state.phase]);

  return (
    <main className={`stage phase-${state.phase} ${state.expanded || active ? 'is-open' : ''}`}>
      <BorderBeam
        size={state.phase === 'error' ? 'pulse-outside' : 'line'}
        colorVariant={state.phase === 'error' ? 'sunset' : 'ocean'}
        strength={active ? 0.82 : 0.24}
        active
        theme="dark"
      >
        <VoiceBeam
          type="default"
          level={state.phase === 'listening' ? state.level : 0}
          processing={busy}
          colorVariant={state.phase === 'error' ? 'sunset' : 'ice'}
          theme="dark"
          strength={active ? 0.9 : 0.22}
          active
        >
          <section className="notch-shell" aria-live="polite">
            <div className="notch-cap">
              <div className="camera" aria-hidden="true" />
              <div className="status-dot" />
              <span className="cap-label">{PHASE_COPY[state.phase]}</span>
              <kbd>⌘</kbd>
            </div>

            <div className="content">
              <div className="orb-wrap">
                <ThinkingOrb state={orbState} size={64} speed={state.phase === 'routing' ? 1.25 : 0.85} dark />
              </div>

              <div className="copy">
                <div className="eyebrow">
                  {state.tool ? <MetalBadge>{state.tool}</MetalBadge> : <span>JEV SYSTEM ONE</span>}
                  {state.confidence > 0 && <span>{Math.round(state.confidence * 100)}%</span>}
                </div>
                <MetalText font="600 15px/1.25 -apple-system" color="#F5F7FA">
                  {state.transcript || PHASE_COPY[state.phase]}
                </MetalText>
                <p>{state.detail}</p>
              </div>

              <div className="activity-visual" aria-hidden="true">
                <ImageGeneration
                  preset="sweep-gradient"
                  images={["data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='80' height='80'%3E%3Cdefs%3E%3CradialGradient id='g'%3E%3Cstop stop-color='%236CE5FF'/%3E%3Cstop offset='1' stop-color='%237B61FF'/%3E%3C/radialGradient%3E%3C/defs%3E%3Crect width='80' height='80' rx='22' fill='url(%23g)'/%3E%3C/svg%3E"]}
                  autoReveal={state.phase === 'success'}
                >
                  <div className="image-seed" />
                </ImageGeneration>
              </div>
            </div>

            <div className={`actions ${state.needsConfirmation ? 'visible' : ''}`}>
              <Liquid blur={7} contrast={20} fill="#101318" shadow="0 8px 28px rgba(0,0,0,.5)">
                <Liquid.Item x={state.needsConfirmation ? -62 : 0} y={0} transition="bouncy">
                  <MetalFx preset="silver" variant="button" strength={0.7} theme="dark">
                    <button onClick={() => send('cancel')} aria-label="Cancel action">Cancel</button>
                  </MetalFx>
                </Liquid.Item>
                <Liquid.Item x={state.needsConfirmation ? 62 : 0} y={0} transition="bouncy" delay={50}>
                  <MetalFx preset="chromatic" variant="button" strength={0.9} theme="dark" innerShadow>
                    <button className="confirm" onClick={() => send('confirm')} aria-label="Confirm action">Run</button>
                  </MetalFx>
                </Liquid.Item>
              </Liquid>
            </div>
          </section>
        </VoiceBeam>
      </BorderBeam>
    </main>
  );
}

createRoot(document.getElementById('root')).render(<Notch />);
